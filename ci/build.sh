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
  [ -e "$framework" ] || continue
  # Google ships these as fat files holding one arm64 slice; a signed Xcode
  # build thins them on embed, an unsigned one does not.
  binary="$framework/$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$framework/Info.plist")"
  if lipo -info "$binary" | grep -q '^Architectures in the fat file'; then
    lipo "$binary" -thin arm64 -output "$binary.thin" && mv "$binary.thin" "$binary"
  fi
  codesign --force --sign - --timestamp=none "$framework"
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

# Unit tests (models, subtitles, localization, offline cache). Reported, but
# a failure doesn't stop the build artifacts.
xcodebuild test \
  -workspace KelaketFilm.xcworkspace \
  -scheme KelaketFilmTests \
  -destination "id=$UDID" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO > test.log 2>&1 && echo "Unit tests passed" || echo "Unit tests FAILED"
grep -E "error:|failed|Executed|TEST (SUCCEEDED|FAILED)" test.log | tail -40 || true

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" || true
mkdir -p screenshots

# UI tests: tap through home, categories, search and the explore lists into
# film pages, in both modes, against the live site. Each step saves a
# screenshot into screenshots/ (ui-*.png).
TEST_RUNNER_KF_SHOTS="$PWD/screenshots" xcodebuild test \
  -workspace KelaketFilm.xcworkspace \
  -scheme KelaketFilmUITests \
  -destination "id=$UDID" \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  ${overrides[@]+"${overrides[@]}"} > uitest.log 2>&1 && echo "UI tests passed" || echo "UI tests FAILED"
grep -E "error:|' (passed|failed)|Executed|TEST (SUCCEEDED|FAILED)" uitest.log | tail -60 || true
cp uitest.log screenshots/ 2>/dev/null || true

# One known film page in each mode (Debug builds read `-kf.open <link>`;
# `simctl openurl` would make iOS ask "Open in …?" over the app).
xcrun simctl install "$UDID" "$APP"
POST_ID=${SAMPLE_POST_ID:-81141}
for mode in ir intl; do
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -kf.region.override "$mode" \
    -kf.open "kelaketfilm://app/film/$POST_ID" >/dev/null
  sleep 15
  xcrun simctl io "$UDID" screenshot "screenshots/$mode-film.png" >/dev/null 2>&1 || true
done
xcrun simctl spawn "$UDID" log show --last 5m --predicate 'process == "KelaketFilm"' --style compact \
  > screenshots/app.log || true
cp test.log screenshots/ 2>/dev/null || true

# Small copies in the build log, readable where the artifact storage is blocked.
echo "=== THUMBNAILS ==="
for shot in screenshots/*.png; do
  sips -s format jpeg -s formatOptions 35 -Z 360 "$shot" --out /tmp/thumb.jpg >/dev/null 2>&1 || continue
  echo "THUMB $(basename "$shot" .png) $(base64 -i /tmp/thumb.jpg | tr -d '\n')"
done
echo "=== END THUMBNAILS ==="
