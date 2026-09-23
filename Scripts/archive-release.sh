#!/bin/bash
set -euo pipefail

project_root=$(cd "$(dirname "$0")/.." && pwd)
configuration=${CONFIGURATION:-Release}
architectures=${ARCHS:-"arm64 x86_64"}
signing_mode=${SIGNING_MODE:-unsigned}
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
archive_path=${ARCHIVE_PATH:-"$project_root/build/ColdDown-$timestamp.xcarchive"}
derived_data_path=${DERIVED_DATA_PATH:-"/private/tmp/ColdDownArchiveDerived"}
package_cache_path=${PACKAGE_CACHE_PATH:-"/private/tmp/ColdDownArchivePackages"}

mkdir -p "$(dirname "$archive_path")"
if [[ -e "$archive_path" ]]; then
    echo "Archive path already exists: $archive_path" >&2
    exit 64
fi

settings=(
    -project "$project_root/ColdDown.xcodeproj"
    -scheme ColdDownApp
    -configuration "$configuration"
    -destination 'generic/platform=macOS'
    -archivePath "$archive_path"
    -derivedDataPath "$derived_data_path"
    -clonedSourcePackagesDirPath "$package_cache_path"
    "ARCHS=$architectures"
    ONLY_ACTIVE_ARCH=NO
    COMPILER_INDEX_STORE_ENABLE=NO
    "THERMAL_APP_BUNDLE_ID=${THERMAL_APP_BUNDLE_ID:-com.example.ColdDown}"
    "THERMAL_HELPER_BUNDLE_ID=${THERMAL_HELPER_BUNDLE_ID:-com.example.ColdDown.Helper}"
    "THERMAL_HELPER_MACH_SERVICE=${THERMAL_HELPER_MACH_SERVICE:-com.example.ColdDown.Helper}"
)

case "$signing_mode" in
    unsigned)
        settings+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
        ;;
    developer-id)
        : "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION for Developer ID mode}"
        : "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM for Developer ID mode}"
        [[ "$DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]] || { echo "DEVELOPMENT_TEAM must be a 10-character team ID" >&2; exit 64; }
        # The helper pins client connections to this team; shipping placeholder identifiers is never valid.
        for identifier in "${THERMAL_APP_BUNDLE_ID:-}" "${THERMAL_HELPER_BUNDLE_ID:-}" "${THERMAL_HELPER_MACH_SERVICE:-}"; do
            if [[ -z "$identifier" || "$identifier" == com.example.* ]]; then
                echo "Set THERMAL_APP_BUNDLE_ID, THERMAL_HELPER_BUNDLE_ID and THERMAL_HELPER_MACH_SERVICE to real identifiers for Developer ID mode" >&2
                exit 64
            fi
        done
        settings+=(
            CODE_SIGN_STYLE=Manual
            "CODE_SIGN_IDENTITY=$DEVELOPER_ID_APPLICATION"
            "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
            'OTHER_CODE_SIGN_FLAGS=--timestamp --options runtime'
        )
        ;;
    *)
        echo "SIGNING_MODE must be 'unsigned' or 'developer-id'" >&2
        exit 64
        ;;
esac

xcodebuild "${settings[@]}" archive
printf '%s\n' "$archive_path"
