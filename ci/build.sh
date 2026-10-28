#!/usr/bin/env bash
# CI build, run by Codemagic (codemagic.yaml). Produces:
#   KelaketFilm-unsigned.ipa   install on an iPhone with Sideloadly (from Windows)
#   KelaketFilm-simulator.zip  run in a browser on appetize.io
#   screenshots/               the app in the simulator
#
# Optional environment: KF_SITE_HOST, KF_API_KEY (override Config.xcconfig),
# GOOGLE_SERVICE_INFO_PLIST (base64 of GoogleService-Info.plist, turns on
# Firebase), SAMPLE_POST_ID (also screenshots that film's page).
set -euo pipefail

command -v xcodegen >/dev/null || brew install xcodegen
command -v pod >/dev/null || sudo gem install cocoapods

if [ -n "${GOOGLE_SERVICE_INFO_PLIST:-}" ]; then
  echo "$GOOGLE_SERVICE_INFO_PLIST" | base64 --decode > KelaketFilm/Resources/GoogleService-Info.plist
fi

xcodegen generate
pod install --repo-update

overrides=()
[ -n "${KF_SITE_HOST:-}" ] && overrides+=("KF_SITE_HOST=$KF_SITE_HOST")
[ -n "${KF_API_KEY:-}" ] && overrides+=("KF_API_KEY=$KF_API_KEY")

build() {
  xcodebuild \
    -workspace KelaketFilm.xcworkspace \
    -scheme KelaketFilm \
    -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    ${overrides[@]+"${overrides[@]}"} \
    "$@" \
    build 2>&1 | tee -a build.log
}

# iPhone build. Sideloadly re-signs it with your Apple ID; an ad-hoc signature
# on every framework and the app gives it a consistent bundle to re-sign
# (a bare binary next to Google's half-signed frameworks fails on the device
# with "No code signature found").
build -configuration Release -sdk iphoneos -destination 'generic/platform=iOS'
rm -rf Payload && mkdir Payload
cp -R build/Build/Products/Release-iphoneos/KelaketFilm.app Payload/
for framework in Payload/KelaketFilm.app/Frameworks/*.framework; do
  [ -e "$framework" ] && codesign --force --sign - --timestamp=none "$framework"
done
codesign --force --sign - --timestamp=none --generate-entitlement-der Payload/KelaketFilm.app
codesign --verify --deep --strict --verbose=2 Payload/KelaketFilm.app
zip -qry KelaketFilm-unsigned.ipa Payload
rm -rf Payload

# Simulator build for appetize.io and the screenshots.
build -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator'
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
