#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
CORE="$ROOT/mac/ms_core.lua"
MANIFEST="$ROOT/MANIFEST.json"
URL="https://raw.githubusercontent.com/mudbourn/mudscript/main/mac/ms_core.lua"

if [ ! -f "$CORE" ]; then
    echo "ERROR: ms_core.lua not found at $CORE"
    exit 1
fi

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: MANIFEST.json not found at $MANIFEST"
    exit 1
fi

HASH=$(shasum -a 256 "$CORE" | awk '{print $1}')
echo "ms_core.lua  SHA-256: $HASH"

# Read current version from MANIFEST, fall back to 1.0.0 if unreadable.
CURRENT_VERSION=$(python3 -c "
import json, sys
try:
    d = json.load(open('$MANIFEST'))
    print(d.get('version', '1.0.0'))
except:
    print('1.0.0')
" 2>/dev/null || echo "1.0.0")

NEW_VERSION="${1:-$CURRENT_VERSION}"

cat > "$MANIFEST" <<EOF
{
  "version": "$NEW_VERSION",
  "sha256": "$HASH",
  "url": "$URL"
}
EOF

echo "MANIFEST.json updated  (version=$NEW_VERSION)"
echo ""
echo "To create an official release:"
echo "  1. git add ms_core.lua MANIFEST.json"
echo "  2. git commit -m 'release: v$NEW_VERSION'"
echo "  3. git push"
echo "  4. Trigger 'Release' workflow from GitHub Actions with version $NEW_VERSION"
