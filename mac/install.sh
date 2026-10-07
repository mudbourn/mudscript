#!/usr/bin/env bash

set -euo pipefail

REPO="mudbourn/mudscript"
HS="$HOME/.hammerspoon"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || pwd)"

echo ""
echo "+==============================================+"
echo "|        mudscript :// macOS Installer           |"
echo "+==============================================+"
echo ""

if [ -d "/Applications/Hammerspoon.app" ]; then
    echo "1. Hammerspoon is already installed."
else
    echo "1. Hammerspoon not found - downloading latest release ..."
    HS_API="https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest"
    HS_ZIP_URL=$(curl -sf "$HS_API" \
        | grep -o '"browser_download_url": *"[^"]*\.zip"' \
        | head -1 | sed 's/.*": *"//; s/"//')

    if [ -z "$HS_ZIP_URL" ]; then
        echo "   FAIL Could not determine Hammerspoon download URL."
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
    echo "   OK   Hammerspoon installed to /Applications/."
fi

echo ""
if command -v jq >/dev/null 2>&1 || [ -x /usr/bin/jq ] || [ -x /opt/homebrew/bin/jq ] || [ -x /usr/local/bin/jq ]; then
    echo "2. jq is already installed."
else
    echo "2. jq not found - needed to verify the registry signature ..."
    if command -v brew >/dev/null 2>&1; then
        echo "   Installing jq via Homebrew ..."
        if brew install jq; then
            echo "   OK   jq installed."
        else
            echo "   WARN 'brew install jq' failed - install it manually later: brew install jq"
        fi
    else
        echo "   WARN Homebrew not found, so jq can't be auto-installed."
        echo "     The registry (Browse) will not work until jq is present."
        echo "     Install Homebrew, then jq:"
        echo "       /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        echo "       brew install jq"
    fi
fi

PROFILE_ROOT_FILES="ms_macros.lua data/ms_settings.json data/ms_settings_default.json data/ms_theme.json data/ms_macros_visual.json data/ms_macros_visual.lua data/ms_authored.json data/ms_authored_menus.json data/ms_helpervars.json"
STASH="$(mktemp -d)"
HAD_ROOT=0
HAD_DEFAULT=0
V2_NO_DEFAULT=0
RESTORED=0

restore_profiles() {
    [ "$RESTORED" = "1" ] && return 0
    RESTORED=1
    if [ "$HAD_DEFAULT" = "1" ] && [ -d "$STASH/ProfileDefault" ]; then
        rm -rf "$HS/profiles/Default"
        mkdir -p "$HS/profiles"
        cp -Rp "$STASH/ProfileDefault" "$HS/profiles/Default"
    fi
    if [ "$V2_NO_DEFAULT" = "1" ]; then
        rm -rf "$HS/profiles/Default"
    fi
    for f in $PROFILE_ROOT_FILES; do
        rm -f "$HS/$f"
    done
    if [ "$HAD_ROOT" = "1" ] || [ -f "$HS/profiles/.layout" ]; then
        for f in $PROFILE_ROOT_FILES; do
            if [ -f "$STASH/root/$f" ]; then
                mkdir -p "$HS/$(dirname "$f")"
                cp -p "$STASH/root/$f" "$HS/$f"
            fi
        done
    fi
    rm -rf "$STASH"
}
trap restore_profiles EXIT

for f in $PROFILE_ROOT_FILES; do
    if [ -f "$HS/$f" ]; then
        mkdir -p "$STASH/root/$(dirname "$f")"
        cp -p "$HS/$f" "$STASH/root/$f"
        HAD_ROOT=1
    fi
done
if [ -d "$HS/profiles/Default" ]; then
    cp -Rp "$HS/profiles/Default" "$STASH/ProfileDefault"
    HAD_DEFAULT=1
elif [ -f "$HS/profiles/.layout" ] && [ "$(cat "$HS/profiles/.layout" 2>/dev/null)" -ge 2 ] 2>/dev/null; then
    for d in "$HS/profiles"/*/; do
        if [ -f "${d}profile.json" ]; then
            V2_NO_DEFAULT=1
        fi
    done
fi

if [ -f "$SCRIPT_DIR/ms_core.lua" ] && [ -f "$SCRIPT_DIR/init.lua" ]; then
    echo "3. Copying local repo to ~/.hammerspoon/ ..."
    mkdir -p "$HS"
    for item in "$SCRIPT_DIR"/*; do
        [ "$(basename "$item")" = "profiles" ] && continue
        cp -R "$item" "$HS/"
    done
    [ -f "$SCRIPT_DIR/../MANIFEST.json" ] && cp "$SCRIPT_DIR/../MANIFEST.json" "$HS/"
    if [ -d "$SCRIPT_DIR/../sounds" ]; then
        mkdir -p "$HS/sounds"
        cp "$SCRIPT_DIR/../sounds/"*.wav "$HS/sounds/" 2>/dev/null || true
    fi
    if [ -d "$SCRIPT_DIR/../profiles/Default" ] && [ ! -d "$HS/profiles/Default" ] && [ "$V2_NO_DEFAULT" = "0" ]; then
        mkdir -p "$HS/profiles"
        cp -R "$SCRIPT_DIR/../profiles/Default" "$HS/profiles/"
    fi
    for pkg in "$SCRIPT_DIR"/../*.mspkg; do
        [ -f "$pkg" ] && cp "$pkg" "$HS/"
    done
    rm -f "$HS/install.sh"
    echo "   OK   Files copied from $SCRIPT_DIR"
else
    echo "3. Downloading latest release from GitHub ..."
    mkdir -p "$HS"

    echo "   Checking for latest release..."
    API="https://api.github.com/repos/$REPO/releases/latest"
    ZIP_URL=$(curl -sf "$API" | grep -o '"browser_download_url": *"[^"]*macos[^"]*"' | head -1 | sed 's/.*": *"//; s/"//')

    if [ -n "$ZIP_URL" ]; then
        echo "   Downloading: $ZIP_URL"
        TMP_FILE=$(mktemp)
        curl -sfL "$ZIP_URL" -o "$TMP_FILE"
        if echo "$ZIP_URL" | grep -q '\.zip$'; then
            unzip -o "$TMP_FILE" -d "$HS" > /dev/null
            NESTED=$(find "$HS" -maxdepth 1 -type d -name "mudscript-*" | head -1)
            if [ -n "$NESTED" ]; then
                mv "$NESTED"/* "$HS/" 2>/dev/null || true
                rm -rf "$NESTED"
            fi
        else
            tar xzf "$TMP_FILE" -C "$HS" --strip-components=1
        fi
        rm -f "$TMP_FILE"
        echo "   OK   Release downloaded and extracted."
    else
        echo "   No release found - downloading main branch..."
        ZIP_URL="https://github.com/$REPO/archive/refs/heads/main.tar.gz"
        TMP_FILE=$(mktemp)
        curl -sfL "$ZIP_URL" -o "$TMP_FILE"
        mkdir -p "$HS-tmp"
        tar xzf "$TMP_FILE" -C "$HS-tmp" --strip-components=1
        cp -R "$HS-tmp"/* "$HS/"
        rm -rf "$HS-tmp" "$TMP_FILE"
        rm -f "$HS/install.bat" "$HS"/*.ahk
        rm -rf "$HS/bin"/*.bat "$HS/bin"/*.ps1
        echo "   OK   Repository downloaded and macOS files extracted."
    fi

    rm -f "$HS/install.sh" 2>/dev/null || true
fi

echo ""
echo "3b. Keeping profile files inside profiles/ ..."
restore_profiles
if [ "$HAD_ROOT" = "1" ] || [ "$HAD_DEFAULT" = "1" ] || [ "$V2_NO_DEFAULT" = "1" ]; then
    echo "   OK   Existing profile files left in place."
elif [ -f "$HS/profiles/Default/profile.json" ]; then
    printf '2\n' > "$HS/profiles/.layout"
    printf 'Default\n' > "$HS/profiles/.active"
    echo "   OK   Default profile installed."
fi

echo ""
echo "4. Installing OS-level Guardian ..."
if [ -f "$HS/bin/install_guardian_agent.sh" ]; then
    bash "$HS/bin/install_guardian_agent.sh"
    echo "   OK   Guardian installed."
else
    echo "   WARN install_guardian_agent.sh not found - skipping."
fi

echo ""
echo "5. Locking bootstrap stub (chmod 444) ..."
chmod 444 "$HS/init.lua" 2>/dev/null && echo "   OK   init.lua locked." || echo "   WARN Could not chmod init.lua."

echo ""
echo "6. Reloading Hammerspoon ..."
if command -v open &>/dev/null; then
    open -g "hammerspoon://reload" 2>/dev/null && echo "   OK   Hammerspoon reloaded." || echo "   WARN Reload manually (menubar icon -> Reload)."
else
    echo "   WARN Reload manually (menubar icon -> Reload)."
fi

echo ""
echo "+==============================================+"
echo "|          Installation complete               |"
echo "+==============================================+"
echo ""
echo "   Directory:  $HS"
echo "   Guardian:   ~/Library/LaunchAgents/com.mudscript.guardian.plist"
echo ""
echo "   The trusted hash is auto-seeded from MANIFEST.json on first load."
echo ""
echo "   Keybindings (target app focused):"
echo "     Opt+P      Toggle settings"
echo "     Opt+[      Reload script"
echo "     Opt+]      Reload settings"
echo "     Opt+F10    Panic (disable macros)"
echo "     /       Disable macros"
echo "     Return  Enable macros"
echo ""
