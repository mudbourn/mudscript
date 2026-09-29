#!/usr/bin/env bash

LOG_DIR="$HOME/Library/Logs/Roblox"
CACHE_DIR="$HOME/Library/Caches/com.roblox.RobloxPlayer"
AGENT_LOG="$HOME/.hammerspoon/data/cache_cleaner.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$AGENT_LOG"; }

freed=0

if [ -d "$LOG_DIR" ]; then
    before=$(du -sk "$LOG_DIR" 2>/dev/null | awk '{print $1}')
    find "$LOG_DIR" -type f -name 'microprofile-*.html' -delete 2>/dev/null
    find "$LOG_DIR" -type f -name '*.log' -mtime +3 -delete 2>/dev/null
    after=$(du -sk "$LOG_DIR" 2>/dev/null | awk '{print $1}')
    freed=$(( before - after ))
    log "Logs/Roblox: cleaned ($(( freed / 1024 )) MB freed)."
else
    log "Logs/Roblox: directory not found - skipping."
fi

if [ -d "$CACHE_DIR" ]; then
    before=$(du -sk "$CACHE_DIR" 2>/dev/null | awk '{print $1}')
    rm -rf "${CACHE_DIR:?}/"*
    after=0
    freed=$(( freed + before - after ))
    log "Caches/RobloxPlayer: cleaned ($(( before / 1024 )) MB freed)."
else
    log "Caches/RobloxPlayer: directory not found - skipping."
fi

total_mb=$(( freed / 1024 ))
log "Total freed: ${total_mb} MB."
