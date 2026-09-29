#!/bin/bash
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
input_path=${1:?Pass a .xcarchive or Cold Down.app path}
expected_architectures=${EXPECTED_ARCHS:-"arm64 x86_64"}

if [[ "$input_path" == *.xcarchive ]]; then
    app_path="$input_path/Products/Applications/Cold Down.app"
else
    app_path="$input_path"
fi

executable="$app_path/Contents/MacOS/Cold Down"
info_plist="$app_path/Contents/Info.plist"

for required in "$app_path" "$executable" "$info_plist"; do
    [[ -e "$required" ]] || { echo "Missing required archive item: $required" >&2; exit 65; }
done

/usr/bin/plutil -lint "$info_plist"
minimum_os=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")
[[ "$minimum_os" == "14.0" ]] || { echo "Expected macOS 14.0 minimum, found $minimum_os" >&2; exit 65; }

normalize_archs() { printf '%s\n' "$1" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//'; }
expected=$(normalize_archs "$expected_architectures")
actual=$(normalize_archs "$(/usr/bin/lipo -archs "$executable")")
[[ "$actual" == "$expected" ]] || { echo "Unexpected architectures for $executable: $actual" >&2; exit 65; }

if /usr/bin/grep -F '$(' "$info_plist" >/dev/null; then
    echo "Unexpanded build-setting placeholder found in the bundled Info.plist" >&2
    exit 65
fi

temporary_root=$(mktemp -d /private/tmp/cold-down-sign.XXXXXX)
trap 'rm -rf "$temporary_root"' EXIT
/usr/bin/ditto "$app_path" "$temporary_root/Cold Down.app"
temporary_app="$temporary_root/Cold Down.app"
/usr/bin/codesign --force --sign - --options runtime \
    --entitlements "$project_root/Sources/ColdDownApp/ColdDownApp.entitlements" \
    "$temporary_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$temporary_app"

if /usr/bin/codesign -dvv "$app_path" 2>&1 | /usr/bin/grep -q '^Signature=adhoc$'; then
    echo "Validated layout, metadata, universal architectures, and ad-hoc signability."
elif /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"; then
    /usr/sbin/spctl --assess --type execute --verbose=2 "$app_path"
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        notarization_zip="$temporary_root/ColdDown.zip"
        /usr/bin/ditto -c -k --keepParent "$app_path" "$notarization_zip"
        /usr/bin/xcrun notarytool submit "$notarization_zip" --keychain-profile "$NOTARY_PROFILE" --wait
        /usr/bin/xcrun stapler staple "$app_path"
        /usr/bin/xcrun stapler validate "$app_path"
        /usr/sbin/spctl --assess --type execute --verbose=2 "$app_path"
    fi
    echo "Validated Developer ID signature and Gatekeeper assessment."
else
    echo "Archive is unsigned; ad-hoc rehearsal passed."
fi
