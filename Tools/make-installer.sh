#!/bin/bash
# Builds build/PuggleSlides.pkg, an installer that puts PuggleSlides.app in /Applications for all users.
#
#   Tools/make-installer.sh
#
# There's no Developer ID yet, so the app is ad-hoc signed and the installer is unsigned. With one:
# sign the app with "Developer ID Application", pass --sign "Developer ID Installer: …" to
# productbuild, then notarize the installer (xcrun notarytool submit --wait) and staple it
# (xcrun stapler staple).
set -euo pipefail

cd "$(dirname "$0")/.."
WORK="$PWD/build/Installer"
OUTPUT="$PWD/build/PuggleSlides.pkg"
rm -rf "$WORK" "$OUTPUT"
mkdir -p "$WORK/root" "$WORK/packages"

# 1. A Release archive of the app, for Apple silicon and Intel Macs. The build log is only shown if it fails.
echo "Building PuggleSlides.app…"
if ! xcodebuild -project PuggleSlides.xcodeproj -scheme PuggleSlides -configuration Release \
        -derivedDataPath "$WORK/DerivedData" -archivePath "$WORK/PuggleSlides.xcarchive" \
        ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO archive > "$WORK/build.log" 2>&1; then
    grep -E "error:|\*\* ARCHIVE FAILED" "$WORK/build.log" || tail -40 "$WORK/build.log"
    echo "The build failed. The full log is in $WORK/build.log" >&2
    exit 1
fi
APP="$WORK/PuggleSlides.xcarchive/Products/Applications/PuggleSlides.app"
codesign --verify --strict "$APP"

info() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }
IDENTIFIER=$(info CFBundleIdentifier)
VERSION=$(info CFBundleShortVersionString)
MIN_OS=$(info LSMinimumSystemVersion)
HOST_ARCHS=$(lipo -archs "$APP/Contents/MacOS/PuggleSlides" | tr ' ' ',')

# 2. The app package. Installers normally update any other copy of an app they find on the disk
#    (in a build folder, say) instead of installing it where they should, so relocation is turned off.
echo "Packaging…"
ditto "$APP" "$WORK/root/PuggleSlides.app"
pkgbuild --quiet --analyze --root "$WORK/root" "$WORK/components.plist"
index=0
while plutil -extract "$index" xml1 -o /dev/null "$WORK/components.plist" 2>/dev/null; do
    plutil -replace "$index.BundleIsRelocatable" -bool NO "$WORK/components.plist"
    index=$((index + 1))
done
pkgbuild --quiet --root "$WORK/root" --component-plist "$WORK/components.plist" --install-location /Applications \
    --identifier "$IDENTIFIER" --version "$VERSION" "$WORK/packages/PuggleSlidesApp.pkg"

# 3. The installer: the startup disk only, macOS $MIN_OS or later.
cat > "$WORK/Distribution.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>PuggleSlides</title>
    <options customize="never" require-scripts="false" hostArchitectures="$HOST_ARCHS"/>
    <domains enable_anywhere="false" enable_currentUserHome="false" enable_localSystem="true"/>
    <volume-check>
        <allowed-os-versions>
            <os-version min="$MIN_OS"/>
        </allowed-os-versions>
    </volume-check>
    <choices-outline>
        <line choice="default">
            <line choice="$IDENTIFIER"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$IDENTIFIER" visible="false">
        <pkg-ref id="$IDENTIFIER"/>
    </choice>
    <pkg-ref id="$IDENTIFIER" version="$VERSION" onConclusion="none">#PuggleSlidesApp.pkg</pkg-ref>
</installer-gui-script>
EOF
productbuild --quiet --distribution "$WORK/Distribution.xml" --package-path "$WORK/packages" "$OUTPUT"
echo "Built $OUTPUT (PuggleSlides $VERSION, $IDENTIFIER, $HOST_ARCHS)"
