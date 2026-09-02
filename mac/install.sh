#!/usr/bin/env bash
# install.sh — mudscript one-shot installer (macOS)
#
# Usage:
#   curl -L https://raw.githubusercontent.com/mudbourn/mudscript/main/mac/install.sh | bash
#   # or download and:
#   bash install.sh
#
# Works whether you have the full repo or just this file.
# Downloads the latest release from GitHub if the repo isn't local.
#
# To uninstall:
#   launchctl unload ~/Library/LaunchAgents/com.mudscript.guardian.plist 2>/dev/null
#   rm -f ~/Library/LaunchAgents/com.mudscript.guardian.plist
#   launchctl unload ~/Library/LaunchAgents/com.mudscript.cache-cleaner.plist 2>/dev/null
#   rm -f ~/Library/LaunchAgents/com.mudscript.cache-cleaner.plist
#   rm -rf ~/.hammerspoon/

set -euo pipefail

REPO="mudbourn/mudscript"
HS="$HOME/.hammerspoon"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || pwd)"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║        mudscript :// macOS Installer           ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Step 1: Ensure Hammerspoon is installed ───────────────────────────────────

if [ -d "/Applications/Hammerspoon.app" ]; then
    echo "❶  Hammerspoon is already installed."
else
    echo "❶  Hammerspoon not found — downloading latest release …"
    HS_API="https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest"
    HS_ZIP_URL=$(curl -sf "$HS_API" \
        | grep -o '"browser_download_url": *"[^"]*\.zip"' \
        | head -1 | sed 's/.*": *"//; s/"//')

    if [ -z "$HS_ZIP_URL" ]; then
        echo "   ✗ Could not determine Hammerspoon download URL."
        echo "     Please install manually: https://www.hammerspoon.org"
        exit 1
    fi

    echo "   Downloading: $HS_ZIP_URL"
    HS_TMP=$(mktemp -d)
    curl -sfL "$HS_ZIP_URL" -o "$HS_TMP/hammerspoon.zip"
    unzip -qo "$HS_TMP/hammerspoon.zip" -d "$HS_TMP"
    # The zip contains Hammerspoon.app at the top level
    cp -R "$HS_TMP/Hammerspoon.app" /Applications/
    rm -rf "$HS_TMP"
    echo "   ✓ Hammerspoon installed to /Applications/."
fi

# ── Step 2: Ensure jq (registry signature verification) ───────────────────────
# The Browse/registry client rebuilds the signer's canonical bytes with `jq -c -S`
# to verify the index signature. macOS 26+ ships /usr/bin/jq, but older systems
# don't — without jq the registry reads as "signature did not verify" and Browse
# looks broken. Install it up front so the registry just works.

echo ""
if command -v jq >/dev/null 2>&1 || [ -x /usr/bin/jq ] || [ -x /opt/homebrew/bin/jq ] || [ -x /usr/local/bin/jq ]; then
    echo "❷  jq is already installed."
else
    echo "❷  jq not found — needed to verify the registry signature …"
    if command -v brew >/dev/null 2>&1; then
        echo "   Installing jq via Homebrew …"
        if brew install jq; then
            echo "   ✓ jq installed."
        else
            echo "   ⚠  'brew install jq' failed — install it manually later: brew install jq"
        fi
    else
        echo "   ⚠  Homebrew not found, so jq can't be auto-installed."
        echo "     The registry (Browse) will not work until jq is present."
        echo "     Install Homebrew, then jq:"
        echo "       /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        echo "       brew install jq"
    fi
fi

# ── Step 3: Source the files ──────────────────────────────────────────────────

if [ -f "$SCRIPT_DIR/ms_core.lua" ] && [ -f "$SCRIPT_DIR/init.lua" ]; then
    # Full repo detected — copy directly
    echo "❸  Copying local repo to ~/.hammerspoon/ …"
    mkdir -p "$HS"
    cp -R "$SCRIPT_DIR"/* "$HS/"
    # MANIFEST.json lives at the repo root (one level up from mac/)
    [ -f "$SCRIPT_DIR/../MANIFEST.json" ] && cp "$SCRIPT_DIR/../MANIFEST.json" "$HS/"
    # Include default settings and sounds from the repo root.
    if [ -d "$SCRIPT_DIR/../data" ]; then
        mkdir -p "$HS/data"
        cp "$SCRIPT_DIR/../data/"*.json "$HS/data/" 2>/dev/null || true
    fi
    if [ -d "$SCRIPT_DIR/../sounds" ]; then
        mkdir -p "$HS/sounds"
        cp "$SCRIPT_DIR/../sounds/"*.wav "$HS/sounds/" 2>/dev/null || true
    fi
    # Include the default profile if it exists.
    if [ -d "$SCRIPT_DIR/../profiles/Default" ]; then
        mkdir -p "$HS/profiles"
        cp -R "$SCRIPT_DIR/../profiles/Default" "$HS/profiles/"
    fi
    # Include bundled .mspkg profile packs.
    for pkg in "$SCRIPT_DIR"/../*.mspkg; do
        [ -f "$pkg" ] && cp "$pkg" "$HS/"
    done
    rm -f "$HS/install.sh"
    echo "   ✓ Files copied from $SCRIPT_DIR"
else
    # Standalone script — download latest release
    echo "❸  Downloading latest release from GitHub …"
    mkdir -p "$HS"

    # Try to get the latest release download URL via the GitHub API
    echo "   Checking for latest release..."
    API="https://api.github.com/repos/$REPO/releases/latest"
    ZIP_URL=$(curl -sf "$API" | grep -o '"browser_download_url": *"[^"]*macos[^"]*"' | head -1 | sed 's/.*": *"//; s/"//')

    if [ -n "$ZIP_URL" ]; then
        echo "   Downloading: $ZIP_URL"
        TMP_FILE=$(mktemp)
        curl -sfL "$ZIP_URL" -o "$TMP_FILE"
        # Detect format from URL
        if echo "$ZIP_URL" | grep -q '\.zip$'; then
            unzip -o "$TMP_FILE" -d "$HS" > /dev/null
            # Move contents out of the nested mudscript-* directory if present
            NESTED=$(find "$HS" -maxdepth 1 -type d -name "mudscript-*" | head -1)
            if [ -n "$NESTED" ]; then
                mv "$NESTED"/* "$HS/" 2>/dev/null || true
                rm -rf "$NESTED"
            fi
        else
            tar xzf "$TMP_FILE" -C "$HS" --strip-components=1
        fi
        rm -f "$TMP_FILE"
        echo "   ✓ Release downloaded and extracted."
    else
        # No release yet — download the repo archive directly
        echo "   No release found — downloading main branch..."
        ZIP_URL="https://github.com/$REPO/archive/refs/heads/main.tar.gz"
        TMP_FILE=$(mktemp)
        curl -sfL "$ZIP_URL" -o "$TMP_FILE"
        mkdir -p "$HS-tmp"
        tar xzf "$TMP_FILE" -C "$HS-tmp" --strip-components=1
        # Only copy macOS files
        cp -R "$HS-tmp"/* "$HS/"
        rm -rf "$HS-tmp" "$TMP_FILE"
        rm -f "$HS/install.bat" "$HS"/*.ahk
        rm -rf "$HS/bin"/*.bat "$HS/bin"/*.ps1
        echo "   ✓ Repository downloaded and macOS files extracted."
    fi

    # Remove the downloaded install script from the target
    rm -f "$HS/install.sh" 2>/dev/null || true
fi

# ── Step 4: Install Guardian Launch Agent ────────────────────────────────────

echo ""
echo "❹  Installing OS-level Guardian …"
if [ -f "$HS/bin/install_guardian_agent.sh" ]; then
    bash "$HS/bin/install_guardian_agent.sh"
    echo "   ✓ Guardian installed."
else
    echo "   ⚠  install_guardian_agent.sh not found — skipping."
fi

# ── Step 5: Lock init.lua ────────────────────────────────────────────────────

echo ""
echo "❺  Locking bootstrap stub (chmod 444) …"
chmod 444 "$HS/init.lua" 2>/dev/null && echo "   ✓ init.lua locked." || echo "   ⚠  Could not chmod init.lua."

# ── Step 6: Reload Hammerspoon ────────────────────────────────────────────────

echo ""
echo "❻  Reloading Hammerspoon …"
if command -v open &>/dev/null; then
    open -g "hammerspoon://reload" 2>/dev/null && echo "   ✓ Hammerspoon reloaded." || echo "   ⚠  Reload manually (menubar icon → Reload)."
else
    echo "   ⚠  Reload manually (menubar icon → Reload)."
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║          Installation complete               ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "   Directory:  $HS"
echo "   Guardian:   ~/Library/LaunchAgents/com.mudscript.guardian.plist"
echo ""
echo "   The trusted hash is auto-seeded from MANIFEST.json on first load."
echo ""
echo "   Keybindings (target app focused):"
echo "     ⌥P      Toggle settings"
echo "     ⌥[      Reload script"
echo "     ⌥]      Reload settings"
echo "     ⌥F10    Panic (disable macros)"
echo "     /       Disable macros"
echo "     Return  Enable macros"
echo ""
