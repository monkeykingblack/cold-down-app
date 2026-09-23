#!/bin/sh
set -eu

plist_path=${1:?launch daemon plist path is required}
mach_service=${2:?Mach service name is required}
app_identifier=${3:?application identifier is required}

case "$mach_service:$app_identifier" in
    *[!A-Za-z0-9.:-]*)
        echo "Invalid bundle or Mach-service identifier" >&2
        exit 64
        ;;
esac

/usr/bin/plutil -replace Label -string "$mach_service" "$plist_path"
/usr/bin/plutil -replace MachServices -json "{\"$mach_service\":true}" "$plist_path"
/usr/bin/plutil -replace AssociatedBundleIdentifiers -json "[\"$app_identifier\"]" "$plist_path"
/usr/bin/plutil -lint "$plist_path"
