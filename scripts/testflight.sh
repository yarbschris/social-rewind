#!/usr/bin/env bash
# Archives Social Rewind, checks the signed app, and uploads it to App Store Connect.
#
#   scripts/testflight.sh                       full app with Screen Time: archive, verify, upload
#   scripts/testflight.sh --no-upload           same, but export the .ipa to build/testflight/export instead
#   scripts/testflight.sh --preview [--no-upload]
#                                               the preview without Screen Time (ios/project-preview.yml), for
#                                               teams without the Family Controls distribution entitlement
#
# Needs: your Team ID in ios/Config/Local.xcconfig, your Apple ID signed in to Xcode (Settings → Accounts),
# and for uploading, an App Store Connect app record for the bundle ID. The full app also needs Apple's
# approval for Family Controls (Distribution).
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/testflight"
ARCHIVE="$OUT/SocialRewind.xcarchive"
UPLOAD=1
PREVIEW=0
for arg in "$@"; do
  case "$arg" in
    --no-upload) UPLOAD=0 ;;
    --preview) PREVIEW=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if ! grep -qE '^DEVELOPMENT_TEAM = [A-Z0-9]{10}$' "$ROOT/ios/Config/Local.xcconfig" 2>/dev/null; then
  echo "Set DEVELOPMENT_TEAM in ios/Config/Local.xcconfig first (see Local.xcconfig.example)." >&2
  exit 1
fi

if [[ $PREVIEW == 1 ]]; then
  SPEC=project-preview.yml
  PROJECT="$ROOT/ios/SocialRewindPreview.xcodeproj"
else
  SPEC=project.yml
  PROJECT="$ROOT/ios/SocialRewind.xcodeproj"
fi

# Every upload needs a higher build number than the last. A timestamp always is.
BUILD_NUMBER="$(date -u +%Y%m%d.%H%M)"

rm -rf "$OUT"
mkdir -p "$OUT"

(cd "$ROOT/ios" && xcodegen generate --spec "$SPEC" --quiet)

echo "Archiving $([[ $PREVIEW == 1 ]] && echo "the preview" || echo "the full app"), build $BUILD_NUMBER…"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme SocialRewind \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -quiet

APP="$ARCHIVE/Products/Applications/SocialRewind.app"
fail() { echo "$1" >&2; exit 1; }
entitlements() { codesign -d --entitlements - --xml "$1" 2>/dev/null; }

# Check the artifact, not the config.
APP_ENTITLEMENTS="$(entitlements "$APP")"
grep -q "application-groups" <<<"$APP_ENTITLEMENTS" || fail "The archived app lost its App Group entitlement."
for file in Generated/social-rewind-page.js Generated/social-rewind-isolated.js PrivacyInfo.xcprivacy Assets.car; do
  [[ -e "$APP/$file" ]] || fail "The archived app is missing $file."
done

if [[ $PREVIEW == 1 ]]; then
  grep -q "family-controls" <<<"$APP_ENTITLEMENTS" && fail "The preview has the Family Controls entitlement."
  [[ -d "$APP/PlugIns" ]] && fail "The preview contains extensions: $(ls "$APP/PlugIns" | tr '\n' ' ')"
else
  grep -q "family-controls" <<<"$APP_ENTITLEMENTS" || fail "The archived app is missing the Family Controls entitlement."
  for ext in ShieldConfiguration ShieldAction DeviceActivityMonitor; do
    APPEX="$APP/PlugIns/$ext.appex"
    [[ -d "$APPEX" ]] || fail "The archived app is missing the $ext extension."
    [[ -e "$APPEX/PrivacyInfo.xcprivacy" ]] || fail "$ext is missing its privacy manifest."
    EXT_ENTITLEMENTS="$(entitlements "$APPEX")"
    grep -q "family-controls" <<<"$EXT_ENTITLEMENTS" || fail "$ext is missing the Family Controls entitlement."
    grep -q "application-groups" <<<"$EXT_ENTITLEMENTS" || fail "$ext is missing the App Group entitlement."
  done
fi
echo "Archive checks passed."

OPTIONS="$OUT/ExportOptions.plist"
DESTINATION=$([[ $UPLOAD == 1 ]] && echo upload || echo export)
cat > "$OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>$DESTINATION</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTIONS" \
  -exportPath "$OUT/export" \
  -allowProvisioningUpdates \
  -quiet

if [[ $UPLOAD == 1 ]]; then
  echo "Uploaded build $BUILD_NUMBER. It shows up in App Store Connect → TestFlight after processing (about 5–30 min)."
else
  echo "Exported to $OUT/export"
fi
