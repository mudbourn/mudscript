#!/usr/bin/env bash

HAMMERSPOON_DIR="$HOME/.hammerspoon"
TRUST="$HAMMERSPOON_DIR/data/.ms_trusted_hash"
LOG="$HAMMERSPOON_DIR/data/guardian_agent.log"
SENTINEL="$HAMMERSPOON_DIR/data/.ms_update_pending"
DEVMODE="$HAMMERSPOON_DIR/data/.ms_devmode"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

if [ ! -f "$TRUST" ]; then
    log "No trusted manifest on record - skipping check."
    exit 0
fi

if [ -f "$DEVMODE" ]; then
    log "Developer mode on - skipping check."
    exit 0
fi

if [ -f "$SENTINEL" ]; then
    log "Update in progress (sentinel present) - skipping check."
    exit 0
fi

RAW=$(cat "$TRUST" 2>/dev/null)

if echo "$RAW" | grep -qE '^[[:space:]]*[0-9a-fA-F]{64}[[:space:]]*$'; then
    CORE="$HAMMERSPOON_DIR/ms_core.lua"
    trusted=$(echo "$RAW" | tr -d '[:space:]')
    current=$(shasum -a 256 "$CORE" 2>/dev/null | awk '{print $1}')

    if [ -z "$current" ]; then
        log "shasum failed - cannot verify ms_core.lua."
        exit 0
    fi

    if [ "$current" = "$trusted" ]; then
        log "OK - ms_core.lua matches trusted hash (${current:0:16}...)."
        exit 0
    fi

    log "MISMATCH - expected ${trusted:0:16}... got ${current:0:16}... - killing Hammerspoon."
    killall Hammerspoon 2>/dev/null
    osascript -e 'display notification "ms_core.lua integrity error. Hammerspoon has been stopped.\nVerify the file before restarting." with title "mudscript Guardian" subtitle "Integrity Error" sound name "Basso"' 2>/dev/null
    exit 1
fi

RESULT=$(python3 -c "
import json, hashlib, sys, os

trust_path = sys.argv[1]
hs_dir = sys.argv[2]

try:
    with open(trust_path) as f:
        manifest = json.load(f)
except:
    print('PARSE_ERROR')
    sys.exit(0)

mismatches = []
for rel_path, expected_hash in manifest.items():
    abs_path = os.path.join(hs_dir, rel_path)
    if not os.path.exists(abs_path):
        mismatches.append((rel_path, 'MISSING', expected_hash))
        continue
    try:
        with open(abs_path, 'rb') as f:
            current = hashlib.sha256(f.read()).hexdigest()
    except:
        mismatches.append((rel_path, 'READ_ERROR', expected_hash))
        continue
    if current.lower() != expected_hash.lower():
        mismatches.append((rel_path, current, expected_hash))

if mismatches:
    for rel, cur, exp in mismatches:
        print(f'MISMATCH|{rel}|{cur}|{exp}')
else:
    print('OK')
" "$TRUST" "$HAMMERSPOON_DIR" 2>/dev/null)

if [ -z "$RESULT" ]; then
    log "Python check failed - cannot verify manifest."
    exit 0
fi

if [ "$RESULT" = "OK" ]; then
    log "OK - all files match trusted manifest."
    exit 0
fi

if [ "$RESULT" = "PARSE_ERROR" ]; then
    log "Could not parse trusted manifest."
    exit 0
fi

FIRST=$(echo "$RESULT" | head -1)
FILE=$(echo "$FIRST" | cut -d'|' -f2)
EXPECTED=$(echo "$FIRST" | cut -d'|' -f4)
GOT=$(echo "$FIRST" | cut -d'|' -f3)

log "MISMATCH - $FILE: expected ${EXPECTED:0:16}... got ${GOT:0:16}... - killing Hammerspoon."

killall Hammerspoon 2>/dev/null

osascript -e "display notification \"$FILE integrity error. Hammerspoon has been stopped.\nVerify the file before restarting.\" with title \"mudscript Guardian\" subtitle \"Integrity Error\" sound name \"Basso\"" 2>/dev/null

exit 1
