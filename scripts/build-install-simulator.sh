#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/LevyHome.xcodeproj"
SCHEME="LevyHome"
CONFIGURATION="Debug"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/${CONFIGURATION}-iphonesimulator/LevyHome.app"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 17 Pro}"

cd "$ROOT_DIR"

echo "==> Using simulator: $SIMULATOR_NAME"
DEVICE_ID="$(
  xcrun simctl list devices available "$SIMULATOR_NAME" |
    awk -F '[()]' '/\((Booted|Shutdown)\)/ { print $2; exit }'
)"

if [[ -z "$DEVICE_ID" ]]; then
  echo "Could not find an available simulator named '$SIMULATOR_NAME'." >&2
  echo "Run 'xcrun simctl list devices available' to choose one, then retry:" >&2
  echo "  SIMULATOR_NAME='Exact Device Name' scripts/build-install-simulator.sh" >&2
  exit 1
fi

echo "==> Booting simulator if needed: $DEVICE_ID"
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
xcrun simctl bootstatus "$DEVICE_ID" -b

echo "==> Opening Simulator"
open -a Simulator

echo "==> Fresh building $SCHEME"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  clean build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded, but expected app bundle was not found at:" >&2
  echo "  $APP_PATH" >&2
  exit 1
fi

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP_PATH/Info.plist")"
API_BASE_URL="$(/usr/libexec/PlistBuddy -c 'Print LevyHomeAPIBaseURL' "$APP_PATH/Info.plist" 2>/dev/null || true)"

echo "==> Installing latest build"
xcrun simctl install "$DEVICE_ID" "$APP_PATH"

echo "==> Installed $BUNDLE_ID on $SIMULATOR_NAME ($DEVICE_ID)"
if [[ -n "$API_BASE_URL" ]]; then
  echo "==> Built app API base URL: $API_BASE_URL"
fi
echo "==> Done. Simulator is open; launch Levy Home from the home screen when ready."
