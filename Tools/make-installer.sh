#!/bin/bash
# Builds build/PuggleSlides.pkg, an installer that puts PuggleSlides.app in /Applications for all users.
#
#   Tools/make-installer.sh
#
# By default the app is ad-hoc signed and the installer is unsigned. That's fine on the Mac that built
# it, but macOS blocks a downloaded copy until the user clicks Open Anyway. To sign for distribution
# with a Developer ID, set these first (the release workflow does this on GitHub):
#
#   DEVELOPER_ID_APPLICATION   the identity that signs the app, "Developer ID Application: Name (TEAMID)"
#   DEVELOPER_ID_INSTALLER     the identity that signs the installer, "Developer ID Installer: Name (TEAMID)"
#
# To sign the app for iCloud too, which sharing presentations goes through, also set
#
#   DEVELOPER_ID_PROFILE       a Developer ID provisioning profile for com.pugglesoft.PuggleSlides with iCloud
#                              (CloudKit, container iCloud.com.pugglesoft.PuggleSlides) and Push Notifications
#
# Without it, the app can’t share presentations: it says so in the Collaborate sheet.
#
# To also notarize the signed installer with Apple and staple the ticket to it, set either
#
#   NOTARY_PROFILE             a profile saved with `xcrun notarytool store-credentials`, or
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
#                              an App Store Connect API key: the .p8 file, its key ID and its issuer ID
set -euo pipefail

cd "$(dirname "$0")/.."
WORK="$PWD/build/Installer"
OUTPUT="$PWD/build/PuggleSlides.pkg"
fail() { echo "make-installer: $*" >&2; exit 1; }

NOTARIZE=false
if [ -n "${NOTARY_PROFILE:-}" ] || [ -n "${NOTARY_KEY_PATH:-}" ]; then
    NOTARIZE=true
    [ -n "${DEVELOPER_ID_APPLICATION:-}" ] && [ -n "${DEVELOPER_ID_INSTALLER:-}" ] \
        || fail "notarizing needs both DEVELOPER_ID_APPLICATION and DEVELOPER_ID_INSTALLER"
    if [ -z "${NOTARY_PROFILE:-}" ]; then
        [ -f "$NOTARY_KEY_PATH" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ] \
            || fail "an API key needs NOTARY_KEY_PATH (an existing .p8 file), NOTARY_KEY_ID and NOTARY_ISSUER_ID"
    fi
fi

if [ -n "${DEVELOPER_ID_PROFILE:-}" ] && [ -z "${DEVELOPER_ID_APPLICATION:-}" ]; then
    fail "DEVELOPER_ID_PROFILE needs DEVELOPER_ID_APPLICATION, to sign the app with"
fi

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

# The iCloud container shared presentations are kept in. With a provisioning profile that allows it, the profile goes
# inside the app and the entitlements for iCloud (and, if it allows them, pushes) join the build's own.
CONTAINER=iCloud.com.pugglesoft.PuggleSlides
add_icloud_entitlements() {
    [ -f "$DEVELOPER_ID_PROFILE" ] || fail "DEVELOPER_ID_PROFILE ($DEVELOPER_ID_PROFILE) isn't a file"
    security cms -D -i "$DEVELOPER_ID_PROFILE" > "$WORK/profile.plist" 2>/dev/null \
        || fail "DEVELOPER_ID_PROFILE can't be read as a provisioning profile"
    profile() { /usr/libexec/PlistBuddy -c "Print :$1" "$WORK/profile.plist" 2>/dev/null; }
    local team app_id containers environments pushes
    team=$(profile TeamIdentifier:0) || fail "the provisioning profile names no team"
    app_id=$(profile Entitlements:com.apple.application-identifier) || app_id=""
    [ "$app_id" = "$team.$IDENTIFIER" ] || fail "the provisioning profile is for ${app_id:-no app}, not $team.$IDENTIFIER"
    containers=$(profile Entitlements:com.apple.developer.icloud-container-identifiers) || containers=""
    case "$containers" in
        *"$CONTAINER"*) ;;
        *) fail "the provisioning profile doesn't allow the iCloud container $CONTAINER" ;;
    esac
    if [ ! -s "$WORK/entitlements.plist" ]; then
        printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
            '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
            '<plist version="1.0"><dict/></plist>' > "$WORK/entitlements.plist"
    fi
    entitle() { /usr/libexec/PlistBuddy -c "$1" "$WORK/entitlements.plist" > /dev/null; }
    for key in com.apple.application-identifier com.apple.developer.team-identifier com.apple.developer.icloud-container-identifiers \
               com.apple.developer.icloud-services com.apple.developer.icloud-container-environment com.apple.developer.aps-environment; do
        entitle "Delete :$key" 2> /dev/null || true
    done
    entitle "Add :com.apple.application-identifier string $team.$IDENTIFIER"
    entitle "Add :com.apple.developer.team-identifier string $team"
    entitle "Add :com.apple.developer.icloud-container-identifiers array"
    entitle "Add :com.apple.developer.icloud-container-identifiers:0 string $CONTAINER"
    entitle "Add :com.apple.developer.icloud-services array"
    entitle "Add :com.apple.developer.icloud-services:0 string CloudKit"
    environments=$(profile Entitlements:com.apple.developer.icloud-container-environment) || environments=""
    case "$environments" in
        *Production*) entitle "Add :com.apple.developer.icloud-container-environment string Production" ;;
    esac
    if pushes=$(profile Entitlements:com.apple.developer.aps-environment); then
        entitle "Add :com.apple.developer.aps-environment string $pushes"
    else
        echo "make-installer: the provisioning profile doesn't allow pushes, so shared presentations are only checked for changes while they are open and when PuggleSlides comes to the front, and collaborators get no notifications" >&2
    fi
    cp "$DEVELOPER_ID_PROFILE" "$APP/Contents/embedded.provisionprofile"
    ICLOUD=", for iCloud"
}
ICLOUD=""

# 2. With a Developer ID, sign the app again for distribution: the hardened runtime, a secure timestamp,
#    and the same entitlements the build gave it (with iCloud's, given a profile). The app has no nested
#    code, so one signature covers it.
if [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then
    echo "Signing PuggleSlides.app with the Developer ID…"
    codesign -d --entitlements - --xml "$APP" > "$WORK/entitlements.plist" 2>/dev/null || true
    if [ -n "${DEVELOPER_ID_PROFILE:-}" ]; then
        echo "Signing it for iCloud, with the provisioning profile…"
        add_icloud_entitlements
    fi
    if [ -s "$WORK/entitlements.plist" ]; then
        codesign --force --options runtime --timestamp --entitlements "$WORK/entitlements.plist" \
            --sign "$DEVELOPER_ID_APPLICATION" "$APP"
    else
        codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP"
    fi
    codesign --verify --strict "$APP"
fi

# 3. The app package. Installers normally update any other copy of an app they find on the disk
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

# 4. The installer: the startup disk only, macOS $MIN_OS or later. Signed when there's a Developer ID.
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
if [ -n "${DEVELOPER_ID_INSTALLER:-}" ]; then
    echo "Signing the installer with the Developer ID…"
    productbuild --quiet --distribution "$WORK/Distribution.xml" --package-path "$WORK/packages" \
        --sign "$DEVELOPER_ID_INSTALLER" --timestamp "$OUTPUT"
    pkgutil --check-signature "$OUTPUT" > /dev/null
else
    productbuild --quiet --distribution "$WORK/Distribution.xml" --package-path "$WORK/packages" "$OUTPUT"
fi

# 5. Notarization: Apple checks the installer and the app inside it, then the ticket is stapled to the
#    installer so Gatekeeper accepts it even offline.
notary() {
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        xcrun notarytool "$@" --keychain-profile "$NOTARY_PROFILE"
    else
        xcrun notarytool "$@" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID"
    fi
}
if $NOTARIZE; then
    echo "Notarizing with Apple (usually a few minutes)…"
    notary submit "$OUTPUT" --wait --timeout 1h --output-format json > "$WORK/notary.json" || true
    STATUS=$(plutil -extract status raw -o - "$WORK/notary.json" 2>/dev/null || echo "no answer")
    if [ "$STATUS" != Accepted ]; then
        SUBMISSION=$(plutil -extract id raw -o - "$WORK/notary.json" 2>/dev/null || true)
        [ -n "$SUBMISSION" ] && notary log "$SUBMISSION" "$WORK/notary-log.json" > /dev/null 2>&1 && cat "$WORK/notary-log.json"
        fail "notarization failed ($STATUS). Apple's answer is in $WORK/notary.json"
    fi
    xcrun stapler staple -q "$OUTPUT"
    xcrun stapler validate -q "$OUTPUT"
    spctl --assess --type install "$OUTPUT" 2>/dev/null || fail "Gatekeeper doesn't accept the notarized installer"
fi

if $NOTARIZE; then STATE="signed with the Developer ID and notarized"
elif [ -n "${DEVELOPER_ID_APPLICATION:-}" ] && [ -n "${DEVELOPER_ID_INSTALLER:-}" ]; then STATE="signed with the Developer ID, not notarized"
elif [ -n "${DEVELOPER_ID_APPLICATION:-}" ]; then STATE="app signed with the Developer ID, installer unsigned, not notarized"
elif [ -n "${DEVELOPER_ID_INSTALLER:-}" ]; then STATE="app ad-hoc signed, installer signed with the Developer ID, not notarized"
else STATE="ad-hoc signed, not notarized"
fi
echo "Built $OUTPUT (PuggleSlides $VERSION, $IDENTIFIER, $HOST_ARCHS, $STATE$ICLOUD)"
