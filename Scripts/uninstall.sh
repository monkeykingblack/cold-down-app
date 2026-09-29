#!/bin/sh
# Uninstalls Cold Down: hands the cooler back to its own control, removes the app and its settings.
#
#   sh "/Applications/Cold Down.app/Contents/Resources/Scripts/uninstall.sh"
#
# Administrator privileges are required to remove the app from /Applications; sudo asks for them when needed.

set -u

APP_NAME="Cold Down"
LEGACY_APP_ID="com.example.ColdDown"

if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    HOME=$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory | awk '{print $2}')
fi

run_as_user() {
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        sudo -u "$SUDO_USER" "$@"
    else
        "$@"
    fi
}

# Read the identifier from the installed app so renamed builds are removed too.
APP_ID="dev.monkeykingblack.ColdDown"
for app in "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"; do
    plist="$app/Contents/Info.plist"
    [ -f "$plist" ] || continue
    APP_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null || echo "$APP_ID")
    break
done

echo "Uninstalling $APP_NAME..."

# Quitting lets the app hand the cooler back to its own gear.
echo "Quitting $APP_NAME and returning the cooler to its own control..."
run_as_user osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    sleep 1
done
pkill -x "$APP_NAME" 2>/dev/null || true

for app in "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"; do
    if [ -d "$app" ]; then
        echo "Removing $app..."
        sudo rm -rf "$app"
    fi
done

echo "Removing preferences..."
for id in "$APP_ID" "$LEGACY_APP_ID"; do
    run_as_user defaults delete "$id" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/Preferences/$id.plist"
    rm -rf "$HOME/Library/Saved Application State/$id.savedState"
    rm -rf "$HOME/Library/Caches/$id"
    rm -rf "$HOME/Library/HTTPStorages/$id"
done

echo "$APP_NAME has been uninstalled."
echo "Its entry under System Settings > General > Login Items disappears once macOS notices the app is gone."
