#!/usr/bin/env bash
# Archives the TestFlight preview (no Screen Time, see ios/project-preview.yml), checks the signed app,
# and uploads it to App Store Connect.
#
#   scripts/testflight.sh             archive, verify, upload
#   scripts/testflight.sh --no-upload archive, verify, and export the .ipa to build/testflight/export
#
# Needs: your Team ID in ios/Config/Local.xcconfig, your Apple ID signed in to Xcode (Settings → Accounts),
# and for uploading, an App Store Connect app record for the bundle ID.
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/testflight"
ARCHIVE="$OUT/SocialRewind.xcarchive"
UPLOAD=1
[[ "${1:-}" == "--no-upload" ]] && UPLOAD=0

if ! grep -qE '^DEVELOPMENT_TEAM = [A-Z0-9]{10}$' "$ROOT/ios/Config/Local.xcconfig" 2>/dev/null; then
  echo "Set DEVELOPMENT_TEAM in ios/Config/Local.xcconfig first (see Local.xcconfig.example)." >&2
  exit 1
fi

# Every upload needs a higher build number than the last. A timestamp always is.
BUILD_NUMBER="$(date -u +%Y%m%d.%H%M)"

rm -rf "$OUT"
mkdir -p "$OUT"

(cd "$ROOT/ios" && xcodegen generate --spec project-preview.yml --quiet)

echo "Archiving build $BUILD_NUMBER…"
xcodebuild archive \
  -project "$ROOT/ios/SocialRewindPreview.xcodeproj" \
  -scheme SocialRewind \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -quiet

APP="$ARCHIVE/Products/Applications/SocialRewind.app"

# Check the artifact, not the config: no Screen Time entitlement and no extensions.
ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null)"
if grep -q "family-controls" <<<"$ENTITLEMENTS"; then
  echo "The archived app has the Family Controls entitlement. Refusing to upload." >&2
  exit 1
fi
if ! grep -q "application-groups" <<<"$ENTITLEMENTS"; then
  echo "The archived app lost its App Group entitlement." >&2
  exit 1
fi
if [[ -d "$APP/PlugIns" ]]; then
  echo "The archived app contains extensions: $(ls "$APP/PlugIns" | tr '\n' ' ')" >&2
  exit 1
fi
for file in Generated/social-rewind-page.js Generated/social-rewind-isolated.js PrivacyInfo.xcprivacy Assets.car; do
  [[ -e "$APP/$file" ]] || { echo "The archived app is missing $file." >&2; exit 1; }
done
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
