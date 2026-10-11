#!/usr/bin/env bash

set -euo pipefail

HS_BIN="$(command -v hs || true)"
[ -z "$HS_BIN" ] && [ -x /usr/local/bin/hs ] && HS_BIN=/usr/local/bin/hs
[ -z "$HS_BIN" ] && [ -x /opt/homebrew/bin/hs ] && HS_BIN=/opt/homebrew/bin/hs

if [ -z "$HS_BIN" ]; then
    echo "The hs command was not found."
    echo "In the Hammerspoon console run: hs.ipc.cliInstall()"
    exit 1
fi

LINE="$*"
LINE="${LINE//\\/\\\\}"
LINE="${LINE//\"/\\\"}"

if ! OUT="$("$HS_BIN" -q -t 5 -c "return ms.cli.run(\"$LINE\")" 2>&1)"; then
    echo "Could not reach mudscript."
    echo "Turn on Settings > Developer > Command Line Access, then reload."
    exit 1
fi

printf '%s\n' "$OUT"
