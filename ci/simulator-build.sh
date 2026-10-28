#!/usr/bin/env bash
# Builds the app for the iOS simulator, zips it for appetize.io and takes
# screenshots. Shared by GitHub Actions and Codemagic.
#
# Optional environment: KF_SITE_HOST, KF_API_KEY (override Config.xcconfig),
# SAMPLE_POST_ID (also screenshots that film's page).
set -euo pipefail

command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

overrides=()
[ -n "${KF_SITE_HOST:-}" ] && overrides+=("KF_SITE_HOST=$KF_SITE_HOST")
[ -n "${KF_API_KEY:-}" ] && overrides+=("KF_API_KEY=$KF_API_KEY")

xcodebuild \
  -project KelaketFilm.xcodeproj \
  -scheme KelaketFilm \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  ${overrides[@]+"${overrides[@]}"} \
  build 2>&1 | tee build.log

# Upload this zip to appetize.io to run the app in a browser.
APP=build/Build/Products/Debug-iphonesimulator/KelaketFilm.app
(cd "$(dirname "$APP")" && zip -qry "$OLDPWD/KelaketFilm-simulator.zip" KelaketFilm.app)

BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
phones = [d for runtime, items in devices.items() if "iOS" in runtime for d in items if d["name"].startswith("iPhone")]
print(phones[-1]["udid"])')

xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" || true
xcrun simctl install "$UDID" "$APP"

mkdir -p screenshots
xcrun simctl launch "$UDID" "$BUNDLE_ID"
sleep 4
xcrun simctl io "$UDID" screenshot screenshots/1-launch.png
sleep 20
xcrun simctl io "$UDID" screenshot screenshots/2-home.png
# Film and series pages open through the app's own URL scheme.
if [ -n "${SAMPLE_POST_ID:-}" ]; then
  xcrun simctl openurl "$UDID" "kelaketfilm://app/film/$SAMPLE_POST_ID"
  sleep 12
  xcrun simctl io "$UDID" screenshot screenshots/3-film.png
fi
xcrun simctl spawn "$UDID" log show --last 2m --predicate 'process == "KelaketFilm"' --style compact \
  > screenshots/app.log || true
