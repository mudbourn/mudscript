#!/usr/bin/env bash
# deploy.sh — Deploy repo files to ~/.hammerspoon safely.
# Creates a guardian sentinel before touching ms_core.lua so the
# launchd WatchPaths agent doesn't kill Hammerspoon on file change.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HS="$HOME/.hammerspoon"
SENTINEL="$HS/data/.ms_update_pending"

# Preflight: no native macOS dialogs in the shell UI. A native window
# (hs.dialog.blockAlert / hs.alert.show / hs.chooser) draws BEHIND the
# always-on-top shell and can softlock the instance — every confirm must
# go through ms.ui.modal, which renders inside the shell webview. Guardian
# is the one exception: it runs when the shell may be untrusted, so it is
# allowed native dialogs and is excluded from this scan.
NATIVE_UI_RE='hs\.dialog\.blockAlert|hs\.dialog\.textPrompt|hs\.alert\.show|hs\.chooser'
# Exclude Guardian (allowed native dialogs) and full-line Lua comments, so a
# comment that names one of these functions doesn't read as a call.
if hits=$(grep -rnE "$NATIVE_UI_RE" "$REPO/mac/lib" "$REPO/mac"/*.lua 2>/dev/null \
        | grep -v '/ms_guardian\.lua:' \
        | grep -vE ':[0-9]+:[[:space:]]*--'); then
    echo "deploy: native macOS dialog in shell UI — use ms.ui.modal instead:" >&2
    echo "$hits" >&2
    exit 1
fi

mkdir -p "$HS/data"

# Signal the guardian agent to stand down.
touch "$SENTINEL"

# Copy core file.
cp "$REPO/mac/ms_core.lua" "$HS/ms_core.lua"

# Copy the bootstrap stub. install.sh locks it 444, so unlock, copy, relock.
# Deploy used to skip it entirely: bootstrap changes (e.g. loadSpoon -> require)
# only landed on a fresh install, and a deploy left the stub pointing at files
# this script had just removed.
chmod u+w "$HS/init.lua" 2>/dev/null || true
cp "$REPO/mac/init.lua" "$HS/init.lua"
chmod 444 "$HS/init.lua"

# Copy all UI HTML files.
mkdir -p "$HS/ui"
for f in "$REPO/ui/"*.html; do
    cp "$f" "$HS/ui/$(basename "$f")" 2>/dev/null || true
done

# Prune UI files deleted from the repo (deploy only ever copied, so removals
# never propagated). ms_settings_ui.html: legacy settings UI, deleted 2026-07-13.
rm -f "$HS/ui/ms_settings_ui.html"

# Copy UI fonts.
if [ -d "$REPO/ui/fonts" ]; then
    mkdir -p "$HS/ui/fonts"
    cp -R "$REPO/ui/fonts/"* "$HS/ui/fonts/" 2>/dev/null || true
fi

# Copy UI modules (ES modules shared across panels).
if [ -d "$REPO/ui/modules" ]; then
    mkdir -p "$HS/ui/modules"
    cp -R "$REPO/ui/modules/"* "$HS/ui/modules/" 2>/dev/null || true
fi

# Copy UI SVGs (step icons).
if [ -d "$REPO/ui/svg" ]; then
    mkdir -p "$HS/ui/svg"
    cp -R "$REPO/ui/svg/"* "$HS/ui/svg/" 2>/dev/null || true
fi

# Copy Lua library modules (rm -rf first so deletions propagate).
if [ -d "$REPO/mac/lib" ]; then
    rm -rf "$HS/lib"
    mkdir -p "$HS/lib"
    cp -R "$REPO/mac/lib/"* "$HS/lib/" 2>/dev/null || true
fi

# mudscript no longer ships any Spoon — everything first-party is a lib module,
# and ~/.hammerspoon/Spoons is now purely the installed-plugin directory. Sweep
# out the spoons we used to ship so they stop hashing into Guardian's view of
# the install. Scoped to Ms*.spoon: anything else there is user content.
if [ -d "$HS/Spoons" ]; then
    for dest in "$HS/Spoons/"Ms*.spoon; do
        [ -e "$dest" ] && rm -rf "$dest"
    done
fi

# Copy guardian agent script.
cp "$REPO/mac/bin/ms_guardian_agent.sh" "$HS/bin/ms_guardian_agent.sh" 2>/dev/null || true

# Compile and copy gamepad reader binary.
if command -v swiftc &>/dev/null && [ -f "$REPO/mac/bin/ms_gc_read.swift" ]; then
    swiftc -O -o "$HOME/.local/bin/ms_gc_read" "$REPO/mac/bin/ms_gc_read.swift" -framework GameController 2>/dev/null || true
fi

# Compile and copy the Vision OCR reader binary (drives ms.screen.ocr and friends).
if command -v swiftc &>/dev/null && [ -f "$REPO/mac/bin/ms_ocr_read.swift" ]; then
    mkdir -p "$HOME/.local/bin"
    swiftc -O -o "$HOME/.local/bin/ms_ocr_read" "$REPO/mac/bin/ms_ocr_read.swift" -framework Vision -framework AppKit 2>/dev/null || true
fi

# Copy sounds (defaults + active + macro).
#
# The guard used to read $REPO/sounds/Default, which is not a directory in this
# repo — the library is sounds/defaults — so the branch never taken meant a
# deploy created three empty folders and shipped no audio at all.
#
# Copied over, not synced: sounds/active and sounds/macro are also where the
# user's own imports live, and a deploy has no business deleting those.
if [ -d "$REPO/sounds" ]; then
    mkdir -p "$HS/sounds/defaults" "$HS/sounds/active" "$HS/sounds/macro"
    for d in defaults active macro; do
        if [ -d "$REPO/sounds/$d" ]; then
            cp -R "$REPO/sounds/$d/." "$HS/sounds/$d/" 2>/dev/null || true
        fi
    done
fi

# Copy MANIFEST.json so version tracking stays in sync.
cp "$REPO/MANIFEST.json" "$HS/MANIFEST.json" 2>/dev/null || true

# Bundled registry index: ship the CURRENT signed registry/index.json as the
# offline / first-paint source the Browse client reads at data/registry_index.json.
# It is signed and re-verified by the client against the shipped public key, so the
# only correct bytes are the source-of-truth; a stale hand-committed copy has a body
# that no longer matches its own signature -> verify fails -> Browse shows no
# packages (bit the Windows port, which relies on this file when the network
# refresh is unavailable). Sync it on every deploy.
mkdir -p "$HS/data"
if [ -f "$REPO/registry/index.json" ]; then
    cp "$REPO/registry/index.json" "$HS/data/registry_index.json"
fi

# Increment build number (resets when stable version changes).
BUILD_NUM_FILE="$HS/data/.ms_build_num"
BUILD_BASE_FILE="$HS/data/.ms_build_base"
STABLE_VER=$(grep -o '"version": *"[^"]*"' "$REPO/MANIFEST.json" | head -1 | grep -o '[0-9][0-9.]*')

if [ -f "$BUILD_BASE_FILE" ]; then
    PREV_BASE=$(cat "$BUILD_BASE_FILE")
else
    PREV_BASE=""
fi

if [ "$STABLE_VER" != "$PREV_BASE" ]; then
    # Stable version changed — reset build counter.
    echo "0" > "$BUILD_NUM_FILE"
    echo "$STABLE_VER" > "$BUILD_BASE_FILE"
else
    # Same stable version — increment.
    if [ -f "$BUILD_NUM_FILE" ]; then
        OLD=$(cat "$BUILD_NUM_FILE")
        NEW=$((OLD + 1))
    else
        NEW=1
    fi
    echo "$NEW" > "$BUILD_NUM_FILE"
fi

# Re-seed the trusted hash from the files we just deployed.
#
# We write a FULL per-file manifest (JSON: {relpath: sha256}), not just the
# ms_core.lua hash. Guardian's legacy _checkAll only verifies files that appear
# in this manifest, so a core-only seed left all of lib/ui/bin unchecked between
# deploys — anything that could drop a file there got code execution on the next
# reload with no integrity signal. Listing every tracked file closes that window:
# a hand-edit (or any write) to a deployed file now mismatches on reload and
# Guardian blocks, until the next deploy re-seeds with the new hashes.
#
# Scope mirrors Guardian's _trackedFiles() EXCEPT Spoons/: plugins are governed
# by the signed plugin ledger, not this manifest, so including their hashes here
# would make a later plugin update spuriously trip _checkAll. A real signed
# release still overrides all of this with its own .ms_file_manifest.json.
HASH=$(shasum -a 256 "$HS/ms_core.lua" | awk '{print $1}')
(
    cd "$HS" || exit 1
    {
        echo "ms_core.lua"
        [ -d ui ]  && find ui -type f \( -name '*.js' -o \( -name '*.html' ! -name '_popout_*' \) \)
        [ -d bin ] && find bin -maxdepth 1 -type f -name '*.sh'
        [ -d lib ] && find lib -type f -name '*.lua'
    } | LC_ALL=C sort | tr '\n' '\0' | xargs -0 shasum -a 256 2>/dev/null | awk '
        BEGIN { printf "{" }
        {
            h = $1; $1 = ""; sub(/^ +\*?/, ""); path = $0
            if (seen++) printf ","
            printf "\"%s\":\"%s\"", path, h
        }
        END { print "}" }
    '
) > "$HS/data/.ms_trusted_hash"

# Drop the CI per-file manifest. A dev deploy edits files that a signed release
# manifest still vouches for, so leaving it in place makes Guardian block every
# edited file (it can't be re-signed without CI's key). Removing it hands the
# integrity check to the legacy single-hash path, which the re-seed above keeps
# correct. A real signed install restores the manifest; only local deploys skip
# it. Without this, `ms.deploy` on top of a fresh install self-blocks on boot.
rm -f "$HS/data/.ms_file_manifest.json"

# Remove sentinel — guardian agent can resume normal checks.
rm -f "$SENTINEL"

BUILD=$(cat "$BUILD_NUM_FILE" 2>/dev/null || echo "0")
echo "Deployed. Hash: ${HASH:0:16}… (build $STABLE_VER-pre.$BUILD)"
