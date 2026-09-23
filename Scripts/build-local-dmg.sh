#!/bin/bash
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
input_path=${1:?Pass a Cold Down.app or .xcarchive path}
output_path=${2:-"$project_root/build/ColdDown-Local.dmg"}

if [[ "$input_path" == *.xcarchive ]]; then
    app_path="$input_path/Products/Applications/Cold Down.app"
else
    app_path="$input_path"
fi

[[ -d "$app_path" ]] || { echo "App not found: $app_path" >&2; exit 66; }
[[ ! -e "$output_path" ]] || { echo "Output already exists: $output_path" >&2; exit 64; }

staging_root=$(mktemp -d /private/tmp/cold-down-dmg.XXXXXX)
trap 'rm -rf "$staging_root"' EXIT
staging="$staging_root/Cold Down"
mkdir -p "$staging" "$(dirname "$output_path")"
/usr/bin/ditto "$app_path" "$staging/Cold Down.app"
ln -s /Applications "$staging/Applications"

staged_app="$staging/Cold Down.app"
helper="$staged_app/Contents/Library/HelperTools/ColdDownHelper"
if [[ -f "$helper" ]]; then
    /usr/bin/codesign --force --sign - --options runtime \
        --entitlements "$project_root/Sources/ColdDownHelper/ColdDownHelper.entitlements" \
        "$helper"
fi
/usr/bin/codesign --force --sign - --options runtime \
    --entitlements "$project_root/Sources/ColdDownApp/ColdDownApp.entitlements" \
    "$staged_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$staged_app"

/usr/bin/hdiutil create -fs HFS+ -format UDZO \
    -volname "Cold Down" -srcfolder "$staging" "$output_path"
/usr/bin/hdiutil verify "$output_path"
printf '%s\n' "$output_path"
