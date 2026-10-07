#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# registry_sign_ci.sh - take the registry index live in one command.
#
# The client serves entries only from a SIGNED index, and a plain push does NOT
# sign (see .github/workflows/registry.yml - signing is a manual dispatch so a
# merged edit can't publish itself). After registry_publish.sh updates a row,
# the old signature is stale and Browse shows nothing until the index is
# re-signed. This script does the whole re-sign dance:
#
#   1. dispatch the "Sign Registry" workflow on main with sign=true
#   2. watch the run to completion
#   3. fetch the LIVE raw index and verify its signature the exact way the
#      client does (jq -c -S '{formatVersion,generated,entries}' + openssl)
#
# It signs whatever index.json is committed on main, so if you just ran
# ms.publish, commit and push registry/index.json FIRST (Zed) - this script
# warns if your local copy looks unpushed but does not commit for you.
#
# Usage:  ms.sign            # dispatch CI sign on main, wait, verify
#         ms.sign --verify   # skip the dispatch, just check the live signature
#
# Note: runtime strings are ASCII on purpose. A multibyte glyph placed directly
# after a $var (e.g. "$BRANCH...") gets folded into the variable name under
# `set -u` and aborts as an unbound variable.
# -----------------------------------------------------------------------------
set -euo pipefail

REPO="mudbourn/mudscript"
BRANCH="main"
RAW="https://raw.githubusercontent.com/$REPO/$BRANCH/registry/index.json"

# The public key lives in the client source; find the repo to read it from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${MS_UTILS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
KEYSRC="$REPO_DIR/mac/lib/ms_registry.lua"

VERIFY_ONLY=false
[ "${1:-}" = "--verify" ] && VERIFY_ONLY=true

for tool in gh jq openssl curl; do
    command -v "$tool" >/dev/null || { echo "FAIL: $tool is required but not on PATH."; exit 1; }
done
[ -f "$KEYSRC" ] || { echo "FAIL: cannot find ms_registry.lua at $KEYSRC (set MS_UTILS_DIR)."; exit 1; }

# -- Verify the live signature the way the client does ------------------------
verify_live() {
    local tmp; tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' RETURN
    curl -sf "$RAW" -o "$tmp/idx.json" || { echo "FAIL: could not fetch live index."; return 1; }
    awk '/-----BEGIN PUBLIC KEY-----/{f=1} f{print} /-----END PUBLIC KEY-----/{f=0}' \
        "$KEYSRC" > "$tmp/pub.pem"
    jq -c -S '{formatVersion, generated, entries}' "$tmp/idx.json" > "$tmp/canon.txt"
    # macOS base64 uses -D, GNU uses -d.
    if ! jq -r '.signature' "$tmp/idx.json" | base64 -D > "$tmp/sig.bin" 2>/dev/null; then
        jq -r '.signature' "$tmp/idx.json" | base64 -d > "$tmp/sig.bin"
    fi
    if openssl dgst -sha256 -verify "$tmp/pub.pem" -signature "$tmp/sig.bin" "$tmp/canon.txt" >/dev/null 2>&1; then
        local n; n="$(jq '.entries | length' "$tmp/idx.json")"
        local word="entries"; [ "$n" = "1" ] && word="entry"
        echo "OK: live index verified - serving $n $word."
        return 0
    fi
    echo "FAIL: live signature does NOT verify - the index is being served as empty."
    return 1
}

if $VERIFY_ONLY; then
    verify_live
    exit $?
fi

# -- Warn if the committed index looks unpushed (CI signs the pushed bytes) ----
if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    if ! git -C "$REPO_DIR" diff --quiet -- registry/index.json \
       || ! git -C "$REPO_DIR" diff --cached --quiet -- registry/index.json; then
        echo "WARN: registry/index.json has uncommitted changes - CI signs the pushed"
        echo "      version. Commit and push it first, then re-run ms.sign."
    fi
fi

echo "-> Dispatching Sign Registry on ${REPO}@${BRANCH} ..."
gh workflow run registry.yml -R "$REPO" --ref "$BRANCH" -f sign=true

echo "-> Waiting for the run to register ..."
RUN_ID=""
for _ in 1 2 3 4 5 6; do
    sleep 3
    RUN_ID="$(gh run list -R "$REPO" --workflow registry.yml --event workflow_dispatch \
              -L 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
    [ -n "$RUN_ID" ] && break
done
[ -n "$RUN_ID" ] || { echo "FAIL: could not find the dispatched run. Check: gh run list -R $REPO"; exit 1; }

echo "-> Watching run ${RUN_ID} ..."
gh run watch -R "$REPO" "$RUN_ID" --exit-status || { echo "FAIL: workflow run failed."; exit 1; }

echo "-> Verifying the live signature (raw CDN can lag up to 5 minutes) ..."
for attempt in $(seq 1 36); do
    if verify_live; then exit 0; fi
    [ "$attempt" -lt 36 ] && sleep 10
done
echo "FAIL: still unverified. The run may not have signed (sign input off, or the"
echo "      MS_SIGNING_KEY repo secret is missing). Inspect: gh run view $RUN_ID -R $REPO"
exit 1
