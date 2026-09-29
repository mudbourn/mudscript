#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# registry_golive.sh - ship a package end to end in one command.
#
# This is the orchestrator behind `ms.publish`. It chains the two single-purpose
# scripts in the correct order so the version bump can never be signed stale:
#
#   1. registry_publish.sh <args>   edit registry/index.json + upload the asset
#   2. git add + commit index.json  (auto; NOT pushed - see below)
#   3. WAIT for you to push          poll mudbourn/mudscript main until it serves
#                                    the bytes we just committed
#   4. registry_sign_ci.sh          dispatch Sign Registry, watch, verify live
#   5. git pull --ff-only            receive CI's signature commit
#
# Why the pause at step 3: CI signs whatever is committed and pushed on
# mudbourn/mudscript main - it signs the REMOTE bytes, not the local file. So
# the index must be pushed before signing or CI re-signs the previous version.
# By project convention commits are pushed from Zed, so this script commits for
# you but stops and waits for the push, then continues on its own once it sees
# the pushed index land. Push from Zed when prompted; no need to re-run.
#
# All arguments are forwarded verbatim to registry_publish.sh:
#   ms.publish Roblox.spoon --version 0.1.5
#   ms.publish aurora.mspkg --id aurora-theme
#
# --dry-run / -h / --help short-circuit to registry_publish.sh and do NOT chain
# (nothing is committed, pushed, signed, or pulled).
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INDEX="$ROOT/registry/index.json"
PUBLISH_SH="$SCRIPT_DIR/registry_publish.sh"
SIGN_SH="$SCRIPT_DIR/registry_sign_ci.sh"

SIGN_REPO="mudbourn/mudscript"          # the repo CI signs and the client reads
SIGN_BRANCH="main"
WAIT_TIMEOUT=1800                       # give up waiting for the push after 30 min

# Canonical hash of an index the exact way CI/the client canonicalize it - the
# signature field is excluded on purpose, since CI rewrites it when it signs.
canon() { jq -c -S '{formatVersion, generated, entries}' | shasum -a 256 | cut -c1-64; }

# Canonical hash of the index currently on SIGN_REPO's branch, read through the
# GitHub *contents API* rather than raw.githubusercontent.com. The raw CDN caches
# aggressively and can serve a pushed file's OLD bytes for minutes, which would
# stall the push-wait forever; the API reflects a push immediately.
remote_canon() {
    gh api "repos/$SIGN_REPO/contents/registry/index.json?ref=$SIGN_BRANCH" \
        -q '.content' 2>/dev/null | base64 -D 2>/dev/null | canon 2>/dev/null || true
}

for a in "$@"; do
    case "$a" in
        --dry-run|-h|--help) exec bash "$PUBLISH_SH" "$@" ;;
    esac
done

bash "$PUBLISH_SH" "$@"

cd "$ROOT"

if git diff --quiet -- registry/index.json && git diff --cached --quiet -- registry/index.json; then
    echo
    echo "index.json has no uncommitted change - assuming it is already committed."
else
    git add -- registry/index.json
    # Name the package + version that changed, sniffed from the row publish wrote.
    SUMMARY="$(jq -r '
        [.entries[] | "\(.id) v\(.version // "?")"] | . as $rows
        | ($rows | length) as $n
        | ($rows | join(", "))
    ' "$INDEX" 2>/dev/null || true)"
    git commit -q -m "registry: publish index" -m "${SUMMARY:-}" -- registry/index.json
    echo
    echo "Committed registry/index.json locally ($(git rev-parse --short HEAD))."
fi

WANT="$(canon < "$INDEX")"

# Already live? (re-run with no real change, or you pushed before this got here)
if [ "$(remote_canon)" = "$WANT" ]; then
    echo "The committed index is already on $SIGN_REPO $SIGN_BRANCH - skipping the push wait."
else
    echo
    echo "================================================================"
    echo "  PUSH registry/index.json from Zed now."
    echo "  Waiting for it to land on $SIGN_REPO $SIGN_BRANCH ..."
    echo "  (this continues on its own once the push is detected; Ctrl-C to abort)"
    echo "================================================================"
    START="$(date +%s)"
    while true; do
        if [ "$(remote_canon)" = "$WANT" ]; then
            echo "-> Push detected."
            break
        fi
        if [ $(( $(date +%s) - START )) -ge "$WAIT_TIMEOUT" ]; then
            echo "FAIL: timed out after ${WAIT_TIMEOUT}s waiting for the push."
            echo "      Push registry/index.json, then run: ms.sign && git -C '$ROOT' pull --ff-only"
            exit 1
        fi
        sleep 5
    done
fi

echo
bash "$SIGN_SH"

echo
echo "-> Pulling CI's signature commit ..."
git pull --ff-only
echo "Done - package is published, signed, and live."
