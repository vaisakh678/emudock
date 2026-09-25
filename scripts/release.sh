#!/usr/bin/env bash
# Builds a Developer ID–signed, notarized EmuDock.app and zips it for a GitHub
# Release / Homebrew cask.
#
# Usage: scripts/release.sh 0.1.0
#
# One-time setup:
#   - A "Developer ID Application" certificate for team KTJUU8D53Q in the keychain.
#   - Notary credentials saved in the keychain:
#       xcrun notarytool store-credentials emudock-notary \
#         --key <AuthKey.p8> --key-id <KEY_ID> --issuer <ISSUER_ID>
#     (or set NOTARY_PROFILE to the name of an existing profile)
set -euo pipefail

VERSION=${1:?usage: scripts/release.sh <version, e.g. 0.1.0>}
TEAM_ID=KTJUU8D53Q
NOTARY_PROFILE=${NOTARY_PROFILE:-emudock-notary}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/build/release/$VERSION
# Build numbers must increase between releases; the commit count does.
BUILD=$(git -C "$ROOT" rev-list --count HEAD)

step() { printf '\n==> %s\n' "$*"; }

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application: .*($TEAM_ID)"; then
    echo "No 'Developer ID Application' certificate for team $TEAM_ID in the keychain." >&2
    echo "Create one in Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application." >&2
    exit 1
fi

rm -rf "$OUT"
mkdir -p "$OUT"

step "Generating Xcode project"
(cd "$ROOT/macos" && xcodegen generate --quiet)

step "Archiving EmuDock $VERSION ($BUILD)"
xcodebuild -project "$ROOT/macos/EmuDock.xcodeproj" -scheme EmuDock -configuration Release \
    -destination 'generic/platform=macOS' -archivePath "$OUT/EmuDock.xcarchive" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
    archive -quiet

step "Exporting with Developer ID signing"
cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$OUT/EmuDock.xcarchive" -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" -quiet
APP=$OUT/export/EmuDock.app
codesign --verify --deep --strict --verbose=2 "$APP"

step "Notarizing (usually a few minutes)"
ditto -c -k --keepParent "$APP" "$OUT/EmuDock-notarize.zip"
xcrun notarytool submit "$OUT/EmuDock-notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
rm "$OUT/EmuDock-notarize.zip"

step "Stapling the notarization ticket"
xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=2 "$APP"

step "Packaging"
ZIP=$OUT/EmuDock-$VERSION.zip
ditto -c -k --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

printf '\nDone.\n  %s\n  sha256 %s\n' "$ZIP" "$SHA"
