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
helper="$app_path/Contents/Library/HelperTools/ColdDownHelper"
daemon_plist="$app_path/Contents/Library/LaunchDaemons/ColdDownHelper.plist"
info_plist="$app_path/Contents/Info.plist"

for required in "$app_path" "$executable" "$helper" "$daemon_plist" "$info_plist"; do
    [[ -e "$required" ]] || { echo "Missing required archive item: $required" >&2; exit 65; }
done

/usr/bin/plutil -lint "$info_plist" "$daemon_plist"
minimum_os=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$info_plist")
[[ "$minimum_os" == "14.0" ]] || { echo "Expected macOS 14.0 minimum, found $minimum_os" >&2; exit 65; }

normalize_archs() { printf '%s\n' "$1" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//'; }
expected=$(normalize_archs "$expected_architectures")
for binary in "$executable" "$helper"; do
    actual=$(normalize_archs "$(/usr/bin/lipo -archs "$binary")")
    [[ "$actual" == "$expected" ]] || { echo "Unexpected architectures for $binary: $actual" >&2; exit 65; }
done

app_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")
mach_service=$(/usr/libexec/PlistBuddy -c 'Print :Label' "$daemon_plist")
associated_identifier=$(/usr/libexec/PlistBuddy -c 'Print :AssociatedBundleIdentifiers:0' "$daemon_plist")
bundle_program=$(/usr/libexec/PlistBuddy -c 'Print :BundleProgram' "$daemon_plist")
[[ "$associated_identifier" == "$app_identifier" ]] || { echo "Associated app identifier mismatch" >&2; exit 65; }
[[ "$bundle_program" == 'Contents/Library/HelperTools/ColdDownHelper' ]] || { echo "Unexpected BundleProgram" >&2; exit 65; }
/usr/libexec/PlistBuddy -c "Print :MachServices:$mach_service" "$daemon_plist" >/dev/null
if /usr/bin/grep -R -F '$(' "$daemon_plist" "$info_plist" >/dev/null; then
    echo "Unexpanded build-setting placeholder found in bundled plists" >&2
    exit 65
fi

temporary_root=$(mktemp -d /private/tmp/cold-down-sign.XXXXXX)
trap 'rm -rf "$temporary_root"' EXIT
/usr/bin/ditto "$app_path" "$temporary_root/Cold Down.app"
temporary_app="$temporary_root/Cold Down.app"
/usr/bin/codesign --force --sign - --options runtime \
    --entitlements "$project_root/Sources/ColdDownHelper/ColdDownHelper.entitlements" \
    "$temporary_app/Contents/Library/HelperTools/ColdDownHelper"
/usr/bin/codesign --force --sign - --options runtime \
    --entitlements "$project_root/Sources/ColdDownApp/ColdDownApp.entitlements" \
    "$temporary_app"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$temporary_app"

if /usr/bin/codesign -dvv "$app_path" 2>&1 | /usr/bin/grep -q '^Signature=adhoc$'; then
    echo "Validated layout, metadata, universal architectures, and ad-hoc signability."
elif /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path"; then
    # The helper must pin XPC clients to the same team that signed the app (see HelperClientRequirement).
    app_team=$(/usr/bin/codesign -dv "$app_path" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p')
    helper_team=$(/bin/launchctl plist __TEXT,__info_plist "$helper" 2>/dev/null \
        | /usr/bin/sed -n 's/.*"ThermalExpectedClientTeamIdentifier" = "\(.*\)";/\1/p')
    if [[ -z "$app_team" || "$app_team" == "not set" || "$helper_team" != "$app_team" ]]; then
        echo "Helper client team pin ('$helper_team') does not match the app's signing team ('$app_team')" >&2
        exit 65
    fi
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
