#!/bin/zsh
# Builds Orbit for release.
#   scripts/release.sh dmg         Developer ID–signed, notarized dist/Orbit-v<version>.dmg
#   scripts/release.sh appcast     Writes dist/appcast.xml, the feed Sparkle reads, for the DMG built by `dmg`
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
  local dmg="$DIST/Orbit-v$VERSION.dmg"
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
  echo "Built $dmg (and $DIST/Orbit.dmg for releases/latest/download links)"
}

# The feed Orbit's updater reads. It's attached to the GitHub release, so it goes live with the DMG it describes.
appcast() {
  local dmg="$DIST/Orbit-v$VERSION.dmg"
  local notes="$DIST/release-notes-$VERSION.md"
  [[ -f "$dmg" ]] || { echo "No $dmg. Run make dmg first."; exit 1; }
  [[ -f "$notes" ]] || { echo "No $notes. Write the release notes first."; exit 1; }

  local bin="build/SourcePackages/artifacts/sparkle/Sparkle/bin"
  if [[ ! -x "$bin/sign_update" ]]; then
    xcodebuild -resolvePackageDependencies -project Orbit.xcodeproj -scheme Orbit -clonedSourcePackagesDirPath build/SourcePackages >/dev/null
  fi
  # Prints: sparkle:edSignature="…" length="…". The private key is in the login keychain; see docs/RELEASING.md.
  local signature
  signature=$("$bin/sign_update" --account orbit "$dmg")

  # Read from the archive, so the feed names exactly the build number inside the DMG.
  local plist="$DIST/Orbit.xcarchive/Products/Applications/Orbit.app/Contents/Info.plist"
  local build version
  build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")
  version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
  [[ "$version" == "$VERSION" ]] || { echo "The archive is $version, not $VERSION. Run make dmg first."; exit 1; }
  local minimum
  minimum=$(awk -F'"' '/MACOSX_DEPLOYMENT_TARGET/ {print $2}' project.yml)

  # Just "What's new": the install instructions above it don't apply to someone already updating.
  local what_is_new
  what_is_new=$(sed -n "/^### What's new/,\$p" "$notes")
  [[ -n "$what_is_new" ]] || { echo "No \"### What's new\" heading in $notes."; exit 1; }

  local base="${APPCAST_DOWNLOAD_BASE:-https://github.com/janakjobanputra/orbit/releases/download/v$VERSION}"
  cat > "$DIST/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Orbit</title>
    <item>
      <title>Orbit $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum</sparkle:minimumSystemVersion>
      <description sparkle:format="markdown"><![CDATA[$what_is_new]]></description>
      <enclosure url="$base/Orbit-v$VERSION.dmg" type="application/octet-stream" $signature/>
    </item>
  </channel>
</rss>
XML
  xmllint --noout "$DIST/appcast.xml"
  echo "Wrote $DIST/appcast.xml for $VERSION ($build)"
}

cask() {
  local dmg="$DIST/Orbit-v$VERSION.dmg"
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
  appcast) appcast ;;
  testflight) testflight ;;
  cask) cask ;;
  *) echo "Usage: scripts/release.sh archive|dmg|appcast|testflight|cask"; exit 2 ;;
esac
