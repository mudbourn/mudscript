#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INDEX="$ROOT/registry/index.json"
SIGN_SH="$SCRIPT_DIR/registry_sign.sh"

PKG=""
ID=""
REPO=""
TAG=""
TRUST="trusted"
DO_UPLOAD=true
REPLACE=false
DO_SIGN=false
DRY_RUN=false
KEY_FILE=""
P_NAME=""
P_VERSION=""
P_AUTHOR=""
P_WEBSITE=""
P_DESCRIPTION=""

usage() {
    cat <<'USAGE'
Usage: registry_publish.sh <package> [options]

  <package>            a .spoon bundle directory or a .mspkg file
                       (a profile .mspkg also uploads its theme, sound and
                       macro component packages to the same release)

Metadata (overrides the .mspkg manifest when given):
  --name <name>        display name
  --version <v>        version to publish
  --author <author>    author
  --website <url>      website
  --description <d>    description

Registry:
  --id <id>            registry entry id
  --repo <owner/repo>  GitHub repo that hosts the asset
  --release <tag>      release tag for the assets (default: <id>-v<version>)
  --replace            overwrite assets already in the release
  --trust <level>      trust level (default: trusted)

Steps:
  --no-upload          edit the index without uploading the asset
  --sign               sign the index locally
  --key <file>         key file for --sign
  --dry-run            show what would change, touch nothing
  -h, --help           show this help

Example:
  ms.publish plugins/Roblox.spoon --version 0.2.1
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --id)        ID="${2:-}"; shift 2 ;;
        --repo)      REPO="${2:-}"; shift 2 ;;
        --release)   TAG="${2:-}"; shift 2 ;;
        --trust)     TRUST="${2:-}"; shift 2 ;;
        --name)      P_NAME="${2:-}"; shift 2 ;;
        --version)   P_VERSION="${2:-}"; shift 2 ;;
        --author)    P_AUTHOR="${2:-}"; shift 2 ;;
        --website)   P_WEBSITE="${2:-}"; shift 2 ;;
        --description) P_DESCRIPTION="${2:-}"; shift 2 ;;
        --no-upload) DO_UPLOAD=false; shift ;;
        --sign)      DO_SIGN=true; shift ;;
        --key)       KEY_FILE="${2:-}"; shift 2 ;;
        --dry-run)   DRY_RUN=true; shift ;;
        --replace)   REPLACE=true; shift ;;
        -h|--help)   usage; exit 0 ;;
        -*)          echo "ERROR: unknown argument '$1'"; exit 2 ;;
        *)           [ -z "$PKG" ] && PKG="$1" || { echo "ERROR: only one package at a time (got extra '$1')."; exit 2; }; shift ;;
    esac
done

command -v jq     >/dev/null || { echo "ERROR: jq is required.";     exit 1; }
command -v unzip  >/dev/null || { echo "ERROR: unzip is required.";  exit 1; }
command -v shasum >/dev/null || { echo "ERROR: shasum is required."; exit 1; }
[ -n "$PKG" ]     || { echo "ERROR: no package given."; usage; exit 2; }
[ -f "$INDEX" ]   || { echo "ERROR: index not found at $INDEX"; exit 1; }
[ "$TRUST" = "trusted" ] || [ "$TRUST" = "community" ] \
    || { echo "ERROR: --trust must be 'trusted' or 'community'."; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
FORMAT=""
PROVIDES="[]"
REQUIRES=""
REQUIRES_PLUGINS="[]"
COMP_ASSETS=()

tree_contents() {
    ( cd "$1" && find . -type f | sed 's#^\./##' | LC_ALL=C sort | while IFS= read -r rel; do
        h="$(shasum -a 256 "$rel" | cut -c1-64 | tr '[:upper:]' '[:lower:]')"
        printf '%s\t%s\n' "$rel" "$h"
    done | jq -R -s 'split("\n") | map(select(length > 0) | split("\t")) | map({(.[0]): .[1]}) | add // {}' )
}

case "$PKG" in
    *.spoon)
        [ -d "$PKG" ]              || { echo "ERROR: a .spoon must be a Spoon bundle directory: $PKG"; exit 1; }
        command -v zip >/dev/null  || { echo "ERROR: zip is required to pack a .spoon."; exit 1; }

        SPOON_DIR="${PKG%/}"
        SPOON_NAME="$(basename "$SPOON_DIR")"
        SPOON_BASE="${SPOON_NAME%.spoon}"
        INIT="$SPOON_DIR/init.lua"

        sniff() {
            [ -f "$INIT" ] || return 0
            grep -oE "\\.$1[[:space:]]*=[[:space:]]*\"[^\"]*\"" "$INIT" 2>/dev/null \
                | head -1 | sed -E 's/.*"([^"]*)".*/\1/' || true
        }
        PK_NAME="${P_NAME:-$(sniff name)}";           PK_NAME="${PK_NAME:-$SPOON_BASE}"
        PK_VERSION="${P_VERSION:-$(sniff version)}";  PK_VERSION="${PK_VERSION:-1.0.0}"
        PK_AUTHOR="${P_AUTHOR:-$(sniff author)}"
        PK_WEBSITE="${P_WEBSITE:-$(sniff homepage)}"
        if [ -f "$SPOON_DIR/meta.json" ]; then
            PROVIDES="$(jq -c '(.provides // []) | if type=="array" then map(select(type=="string")) else [] end' "$SPOON_DIR/meta.json" 2>/dev/null || echo '[]')"
        fi

        STAGE="$TMPROOT/stage"
        mkdir -p "$STAGE"
        cp -R "$SPOON_DIR" "$STAGE/$SPOON_NAME"
        find "$STAGE/$SPOON_NAME" \( -name '.DS_Store' -o -name '._*' \) -delete 2>/dev/null || true
        [ -n "$(find "$STAGE/$SPOON_NAME" -type f | head -1)" ] \
            || { echo "ERROR: $SPOON_NAME has no files to pack."; exit 1; }

        ZIP="$TMPROOT/$SPOON_NAME.zip"
        ( cd "$STAGE" && zip -qq -r -X "$ZIP" "$SPOON_NAME" )
        [ -f "$ZIP" ] || { echo "ERROR: could not zip $SPOON_NAME."; exit 1; }
        echo "Zipped $SPOON_NAME (v$PK_VERSION)."
        PKG="$ZIP"
        FORMAT="spoon"
        ;;
    *.mspkg)
        [ -f "$PKG" ] || { echo "ERROR: package not found: $PKG"; exit 1; }
        if [ -n "$P_NAME$P_VERSION$P_AUTHOR$P_WEBSITE$P_DESCRIPTION" ]; then
            command -v zip >/dev/null || { echo "ERROR: zip is required to rewrite the manifest."; exit 1; }
            OVR_DIR="$TMPROOT/override"
            mkdir -p "$OVR_DIR"
            unzip -p "$PKG" mspkg.json > "$OVR_DIR/orig.json" 2>/dev/null \
                || { echo "ERROR: $PKG has no mspkg.json manifest."; exit 1; }
            jq \
                --arg name "$P_NAME" --arg version "$P_VERSION" \
                --arg author "$P_AUTHOR" --arg website "$P_WEBSITE" \
                --arg description "$P_DESCRIPTION" '
                (if $name        != "" then .name = $name               else . end)
                | (if $version     != "" then .version = $version         else . end)
                | (if $author      != "" then .author = $author           else . end)
                | (if $website     != "" then .website = $website         else . end)
                | (if $description != "" then .description = $description else . end)
            ' "$OVR_DIR/orig.json" > "$OVR_DIR/mspkg.json"
            OVR_PKG="$OVR_DIR/$(basename "$PKG")"
            cp "$PKG" "$OVR_PKG"
            ( cd "$OVR_DIR" && zip -qq -X "$OVR_PKG" mspkg.json )
            PKG="$OVR_PKG"
            echo "Rewrote manifest metadata from the command line."
        fi
        ;;
    *)
        echo "ERROR: not a .mspkg or .spoon: $PKG"; exit 1 ;;
esac

ASSET_SRC="$(basename "$PKG")"
ASSET="$(printf '%s' "$ASSET_SRC" | LC_ALL=C sed -E 's/[^A-Za-z0-9._-]+/./g')"

MANIFEST=""
MANIFEST_ID=""
if [ "$FORMAT" = "spoon" ]; then
    TYPE="plugin"
    NAME="$PK_NAME"
    VERSION="$PK_VERSION"
    AUTHOR="$PK_AUTHOR"
    WEBSITE="$PK_WEBSITE"
    DESCRIPTION="$P_DESCRIPTION"
else
    MANIFEST="$(unzip -p "$PKG" mspkg.json 2>/dev/null || true)"
    [ -n "$MANIFEST" ] || { echo "ERROR: $ASSET has no mspkg.json manifest (is it a typed package?)."; exit 1; }
    echo "$MANIFEST" | jq empty 2>/dev/null || { echo "ERROR: $ASSET manifest is not valid JSON."; exit 1; }

    field() { printf '%s' "$MANIFEST" | jq -r --arg k "$1" '.[$k] // "" | if type=="string" then . else "" end'; }
    TYPE="$(field type)"
    NAME="$(field name)"
    VERSION="$(field version)"
    AUTHOR="$(field author)"
    WEBSITE="$(field website)"
    DESCRIPTION="$(field description)"
    REQUIRES="$(printf '%s' "$MANIFEST" | jq -r '.requires | if type=="string" then . elif type=="object" then (.mudscript // "" | if type=="string" then . else "" end) else "" end')"
    REQUIRES_PLUGINS="$(printf '%s' "$MANIFEST" | jq -c '(.requires.plugins // []) | if type=="array" then map(select(type=="string")) else [] end' 2>/dev/null || echo '[]')"
    MANIFEST_ID="$(field id)"
fi

[ -n "$TYPE" ] || { echo "ERROR: manifest has no type."; exit 1; }
[ -n "$NAME" ] || NAME="$ASSET"

COMPONENTS='{}'
if [ -n "$MANIFEST" ]; then
    COMPONENTS="$(printf '%s' "$MANIFEST" | jq -c '
        (.components // {}) as $c
        | reduce (["theme","sound","macro"][]) as $k ({};
            if $c[$k] != null then
                .[$k] = (if $k == "theme"
                         then {includesSounds: (($c.theme.includesSounds) == true)}
                         else {present: true} end)
            else . end)
    ' 2>/dev/null || echo '{}')"
    [ -n "$COMPONENTS" ] || COMPONENTS='{}'
fi

slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }
if [ -z "$ID" ]; then
    if [ -n "$MANIFEST_ID" ]; then ID="$MANIFEST_ID"; else ID="$(slug "$TYPE-$NAME")"; fi
fi
[ -n "$ID" ] || { echo "ERROR: could not derive an id; pass --id."; exit 1; }
if [ -z "$TAG" ]; then
    if [ -n "$VERSION" ]; then TAG="$ID-v$VERSION"; else TAG="$ID"; fi
fi

SHA="$(shasum -a 256 "$PKG" | cut -c1-64 | tr '[:upper:]' '[:lower:]')"
SIZE="$(wc -c < "$PKG" | tr -d ' ')"

REPO="${REPO:-mudbourn/mudscript}"
case "$REPO" in
    */*) ;;
    *) echo "ERROR: invalid --repo '$REPO', expected owner/name."; exit 1 ;;
esac

BASE_URL="https://github.com/$REPO/releases/download/$TAG"
ASSET_URL="$BASE_URL/$ASSET"

UPLOAD_DIR="$TMPROOT/upload"
mkdir -p "$UPLOAD_DIR"
cp "$PKG" "$UPLOAD_DIR/$ASSET"
ALL_SHAS="[\"$SHA\"]"

if [ "$TYPE" = "profile" ] && [ -z "$FORMAT" ]; then
    PROFILE_BASE="$(printf '%s' "$NAME" | sed -E 's/[[:space:]]+[Pp]rofile$//')"
    [ -n "$PROFILE_BASE" ] || PROFILE_BASE="$NAME"
    UNPACK="$TMPROOT/unpack"
    mkdir -p "$UNPACK"
    unzip -qq -o "$PKG" -d "$UNPACK"
    PARCH="$(printf '%s' "$MANIFEST" | jq -c '.platform // {os: "macos", arch: "unknown", mudscript: "unknown"}')"

    for K in theme sound macro; do
        FILES="$(printf '%s' "$MANIFEST" | jq -r --arg k "$K" '(.components[$k].files // []) | if type=="array" then map(select(type=="string")) else [] end | .[]')"
        [ -n "$FILES" ] || continue

        CNAME="$(printf '%s' "$MANIFEST" | jq -r --arg k "$K" '.components[$k].name // "" | if type=="string" then . else "" end')"
        [ -n "$CNAME" ] || CNAME="$PROFILE_BASE"

        CSTAGE="$TMPROOT/comp-$K"
        rm -rf "$CSTAGE"
        mkdir -p "$CSTAGE"
        while IFS= read -r rel; do
            case "$rel" in
                /*|*..*|.*) echo "ERROR: unsafe path in $K component: $rel"; exit 1 ;;
            esac
            [ -f "$UNPACK/$rel" ] || continue
            FLAT="${rel#data/}"
            mkdir -p "$CSTAGE/$(dirname "$FLAT")"
            cp "$UNPACK/$rel" "$CSTAGE/$FLAT"
        done <<< "$FILES"
        [ -n "$(find "$CSTAGE" -type f | head -1)" ] || continue

        CCONTENTS="$(tree_contents "$CSTAGE")"
        jq -n \
            --arg k "$K" --arg name "$CNAME" --arg version "$VERSION" \
            --arg author "$AUTHOR" --arg website "$WEBSITE" \
            --argjson platform "$PARCH" --argjson contents "$CCONTENTS" '
            {formatVersion: 1, type: $k, name: $name}
            + (if $version != "" then {version: $version} else {version: "1.0.0"} end)
            + (if $author  != "" then {author: $author}   else {} end)
            + (if $website != "" then {website: $website} else {} end)
            + {created: (now | todate), platform: $platform, contents: $contents}
        ' > "$CSTAGE/mspkg.json"

        CSLUG="$(slug "$CNAME")"
        CSLUG="${CSLUG%-${K}s}"
        CSLUG="${CSLUG%-$K}"
        [ -n "$CSLUG" ] || CSLUG="$(slug "$ID")"
        CASSET="$CSLUG-$K.mspkg"
        ( cd "$CSTAGE" && zip -qq -r -X "$UPLOAD_DIR/$CASSET" . )
        [ -f "$UPLOAD_DIR/$CASSET" ] || { echo "ERROR: could not build $K component package."; exit 1; }

        CSHA="$(shasum -a 256 "$UPLOAD_DIR/$CASSET" | cut -c1-64 | tr '[:upper:]' '[:lower:]')"
        CSIZE="$(wc -c < "$UPLOAD_DIR/$CASSET" | tr -d ' ')"
        COMPONENTS="$(printf '%s' "$COMPONENTS" | jq -c \
            --arg k "$K" --arg name "$CNAME" --arg url "$BASE_URL/$CASSET" \
            --arg sha "$CSHA" --argjson size "$CSIZE" '
            .[$k] = ((.[$k] // {present: true}) + {name: $name, url: $url, sha256: $sha, size: $size})')"
        ALL_SHAS="$(printf '%s' "$ALL_SHAS" | jq -c --arg h "$CSHA" '. + [$h]')"
        COMP_ASSETS+=("$CASSET")
    done
fi

ENTRY="$(jq -n \
    --arg id "$ID" --arg type "$TYPE" --arg name "$NAME" --arg version "$VERSION" \
    --arg author "$AUTHOR" --arg description "$DESCRIPTION" --arg website "$WEBSITE" \
    --arg sha256 "$SHA" --arg url "$ASSET_URL" --argjson size "$SIZE" --arg format "$FORMAT" \
    --arg requires "$REQUIRES" --argjson reqPlugins "$REQUIRES_PLUGINS" --argjson provides "$PROVIDES" --arg trust "$TRUST" --argjson components "$COMPONENTS" '
    {id: $id, type: $type, name: $name}
    + (if $version     != "" then {version: $version}         else {} end)
    + (if $author      != "" then {author: $author}           else {} end)
    + (if $description != "" then {description: $description}  else {} end)
    + (if $website     != "" then {website: $website}         else {} end)
    + {sha256: $sha256, url: $url, size: $size}
    + (if $format != "" then {format: $format} else {} end)
    + (if ($reqPlugins | length) > 0
        then {requires: ((if $requires != "" then {mudscript: $requires} else {} end) + {plugins: $reqPlugins})}
        elif $requires != "" then {requires: $requires}
        else {} end)
    + (if ($provides | length) > 0 then {provides: $provides} else {} end)
    + (if ($components | length) > 0 then {components: $components} else {} end)
    + {trust: $trust}
')"

echo "-- Entry -----------------------------------------"
printf '%s\n' "$ENTRY" | jq .
echo "  release : $TAG"
echo "  asset   : $ASSET  ($SIZE bytes)"
echo "  url     : $ASSET_URL"
for CA in ${COMP_ASSETS[@]+"${COMP_ASSETS[@]}"}; do
    echo "  asset   : $CA  ($(wc -c < "$UPLOAD_DIR/$CA" | tr -d ' ') bytes)"
done
echo "--------------------------------------------------"

ID_HITS="$(jq --arg id "$ID" '[.entries[] | select(.id == $id)] | length' "$INDEX")"
if [ "$ID_HITS" != "0" ]; then
    OLD_VER="$(jq -r --arg id "$ID" 'first(.entries[] | select(.id == $id) | .version) // ""' "$INDEX")"
    OLD_SHA="$(jq -r --arg id "$ID" 'first(.entries[] | select(.id == $id) | .sha256) // ""' "$INDEX")"
    echo "Updating existing entry '$ID' (v${OLD_VER:-?} -> v${VERSION:-?})."
    [ "$OLD_SHA" = "$SHA" ] && echo "  note: the package bytes are unchanged (same sha256)."
fi
SHA_OTHER="$(jq -r --arg id "$ID" --argjson shas "$ALL_SHAS" '
    [.entries[] | select(.id != $id) | . as $e
        | ([$e.sha256] + [($e.components // {}) | to_entries[] | .value | objects | .sha256 // empty])
        | map(ascii_downcase)
        | select(any(.[]; . as $h | any($shas[]; . == $h)))
        | $e.id] | first // empty' "$INDEX")"
[ -z "$SHA_OTHER" ] || { echo "ERROR: a sha256 in this package is already published under id '$SHA_OTHER'."; exit 1; }

if [ "$DRY_RUN" = true ]; then
    echo "Dry run: nothing uploaded, index untouched."
    exit 0
fi

if [ "$DO_UPLOAD" = true ]; then
    command -v gh >/dev/null || { echo "ERROR: gh (GitHub CLI) is required to upload - or pass --no-upload if the asset already exists."; exit 1; }
    if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
        echo "Release '$TAG' does not exist; creating it."
        gh release create "$TAG" --repo "$REPO" \
            --title "$NAME" \
            --notes "${DESCRIPTION:-Registry package assets for $NAME. Managed by registry_publish.sh.}" \
            >/dev/null
    fi
    UPLOADS=("$UPLOAD_DIR/$ASSET")
    for CA in ${COMP_ASSETS[@]+"${COMP_ASSETS[@]}"}; do UPLOADS+=("$UPLOAD_DIR/$CA"); done
    EXISTING="$(gh release view "$TAG" --repo "$REPO" --json assets -q '.assets[].name' 2>/dev/null || true)"
    if [ "$REPLACE" != true ]; then
        for U in "${UPLOADS[@]}"; do
            if printf '%s\n' "$EXISTING" | grep -qxF "$(basename "$U")"; then
                echo "ERROR: release '$TAG' already has $(basename "$U")."
                echo "       Installed clients may still hold its old sha256. Bump --version,"
                echo "       or pass --replace to overwrite it anyway."
                exit 1
            fi
        done
    fi
    echo "Uploading ${#UPLOADS[@]} asset(s) to release '$TAG'..."
    gh release upload "$TAG" "${UPLOADS[@]}" --repo "$REPO" --clobber
else
    echo "Skipping upload (--no-upload). Assuming $ASSET_URL already exists."
fi

TMP="$(mktemp)"
jq --argjson entry "$ENTRY" '
    .entries = ((.entries // []) | map(select(.id != $entry.id)) + [$entry])
' "$INDEX" > "$TMP"
mv "$TMP" "$INDEX"
echo "Wrote entry '$ID' into $INDEX ($(jq '.entries | length' "$INDEX") total)."

echo "-- Validating index ------------------------------"
if [ "$DO_SIGN" = true ]; then
    if [ -n "$KEY_FILE" ]; then
        bash "$SIGN_SH" --sign --key "$KEY_FILE"
    else
        bash "$SIGN_SH" --sign
    fi
else
    bash "$SIGN_SH"
    echo
    echo "Index updated but UNSIGNED - it serves zero entries until re-signed."
    echo "Commit registry/index.json and run the Sign Registry workflow, or"
    echo "re-run with --sign --key <file> if you hold the signing key."
fi
