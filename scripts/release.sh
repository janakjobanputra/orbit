#!/bin/zsh
# Builds Orbit for release.
#   scripts/release.sh dmg         Developer ID–signed, notarized dist/Orbit-<version>.dmg
#   scripts/release.sh testflight  Uploads a build to App Store Connect for TestFlight
#   scripts/release.sh cask        Points the Homebrew cask at the DMG built by `dmg`
# One-time account setup is in docs/RELEASING.md.
set -euo pipefail
cd "${0:A:h}/.."

TEAM_ID="Y82QXWVLD9"
NOTARY_PROFILE="${NOTARY_PROFILE:-orbit-notary}"
DIST="dist"
VERSION=$(awk -F'"' '/MARKETING_VERSION/ {print $2}' project.yml)
# App Store Connect needs every upload to have a higher build number.
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"

archive() {
  xcodegen generate >/dev/null
  rm -rf "$DIST/Orbit.xcarchive"
  xcodebuild archive \
    -project Orbit.xcodeproj -scheme Orbit -configuration Release \
    -archivePath "$DIST/Orbit.xcarchive" \
    -allowProvisioningUpdates \
    -quiet \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
}

export_archive() { # method, destination
  local options="$DIST/ExportOptions-$1.plist"
  cat > "$options" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>$1</string>
  <key>destination</key><string>$2</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST
  rm -rf "$DIST/export"
  xcodebuild -exportArchive \
    -archivePath "$DIST/Orbit.xcarchive" \
    -exportOptionsPlist "$options" \
    -exportPath "$DIST/export" \
    -allowProvisioningUpdates
}

dmg() {
  archive
  export_archive developer-id export
  local app="$DIST/export/Orbit.app"
  local dmg="$DIST/Orbit-$VERSION.dmg"
  local stage="$DIST/dmg-stage"
  rm -rf "$stage" "$dmg"
  mkdir -p "$stage"
  cp -R "$app" "$stage/"
  ln -s /Applications "$stage/Applications"
  hdiutil create -volname "Orbit" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
  rm -rf "$stage"

  local identity
  identity=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
  [[ -n "$identity" ]] || { echo "No Developer ID Application certificate. See docs/RELEASING.md."; exit 1; }
  codesign --sign "$identity" --timestamp "$dmg"

  echo "Notarizing (this usually takes a few minutes)…"
  xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature -v "$dmg"
  cp "$dmg" "$DIST/Orbit.dmg"
  echo "Built $dmg (and $DIST/Orbit.dmg for the website's latest link)"
}

cask() {
  local dmg="$DIST/Orbit-$VERSION.dmg"
  [[ -f "$dmg" ]] || { echo "No $dmg. Run make dmg first."; exit 1; }
  local file="${TAP_DIR:-../homebrew-tap}/Casks/orbit-calendar.rb"
  [[ -f "$file" ]] || { echo "No cask at $file. Set TAP_DIR to your homebrew-tap checkout."; exit 1; }
  local sha
  sha=$(shasum -a 256 "$dmg" | awk '{print $1}')
  sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$sha\"/" "$file"
  echo "Updated $file to $VERSION ($sha). Commit and push the tap once the GitHub release is published."
}

testflight() {
  archive
  export_archive app-store-connect upload
  echo "Uploaded build $VERSION ($BUILD_NUMBER). It appears in App Store Connect › TestFlight after processing."
}

case "${1:-}" in
  archive) archive ;;
  dmg) dmg ;;
  testflight) testflight ;;
  cask) cask ;;
  *) echo "Usage: scripts/release.sh archive|dmg|testflight|cask"; exit 2 ;;
esac
