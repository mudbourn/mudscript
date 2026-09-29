#!/usr/bin/env bash

set -euo pipefail

HS="$HOME/.hammerspoon"
PLIST_TEMPLATE="$HS/bin/com.mudscript.guardian.plist"
AGENT_SCRIPT="$HS/bin/ms_guardian_agent.sh"
PLIST_DST="$HOME/Library/LaunchAgents/com.mudscript.guardian.plist"

if [ ! -f "$PLIST_TEMPLATE" ]; then
    echo "ERROR: plist template not found at $PLIST_TEMPLATE"
    echo "       Make sure mudscript is installed to ~/.hammerspoon/"
    exit 1
fi

if [ ! -f "$AGENT_SCRIPT" ]; then
    echo "ERROR: agent script not found at $AGENT_SCRIPT"
    exit 1
fi

chmod 755 "$AGENT_SCRIPT"
echo "Agent script: $AGENT_SCRIPT"

mkdir -p "$HOME/Library/LaunchAgents"

sed \
    -e "s|%%AGENT_PATH%%|$AGENT_SCRIPT|g" \
    -e "s|%%CORE_PATH%%|$HS/ms_core.lua|g" \
    -e "s|%%SPOONS_DIR%%|$HS/Spoons|g" \
    -e "s|%%UI_DIR%%|$HS/ui|g" \
    -e "s|%%BIN_DIR%%|$HS/bin|g" \
    -e "s|%%LOG_PATH%%|$HS/data/guardian_agent.log|g" \
    "$PLIST_TEMPLATE" > "$PLIST_DST"

echo "Plist written:  $PLIST_DST"

launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"

echo ""
echo "mudscript Guardian agent installed and running."
echo "It watches:  $HS/ms_core.lua + $HS/Spoons/ + $HS/ui/ + $HS/bin/"
echo "Log file:    $HS/data/guardian_agent.log"

echo ""
echo "Optional: make the stub read-only for stronger protection:"
echo "  chmod 444 ~/.hammerspoon/init.lua"
