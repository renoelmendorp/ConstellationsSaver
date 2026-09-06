#!/bin/bash
#
# Builds a distributable Constellations.saver and zips it for a GitHub release.
#
# The bundle is ad-hoc signed: arm64 code needs at least an ad-hoc signature to run at all, but
# this is not a Developer ID signature and it is not notarized, so anyone who downloads the zip
# has to clear the quarantine flag before macOS will load it. See README.md.

set -euo pipefail

cd "$(dirname "$0")/.."

BUILD_DIR="${BUILD_DIR:-.build}"
OUTPUT="${OUTPUT:-Constellations.saver.zip}"

# Since Xcode 26 the Metal compiler is a separate component, and it is not always present.
if ! xcrun -sdk macosx metal --version >/dev/null 2>&1; then
    echo "==> Metal toolchain missing, downloading it"
    xcodebuild -downloadComponent MetalToolchain
fi

echo "==> Building"
rm -rf "$BUILD_DIR" "$OUTPUT"
xcodebuild \
    -project Constellations.xcodeproj \
    -scheme Constellations \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="-" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    DEVELOPMENT_TEAM="" \
    build

SAVER="$BUILD_DIR/Build/Products/Release/Constellations.saver"

echo "==> Checking the bundle"
lipo -archs "$SAVER/Contents/MacOS/Constellations"
test -f "$SAVER/Contents/Resources/default.metallib" || { echo "default.metallib is missing"; exit 1; }
codesign --verify --deep --strict --verbose=2 "$SAVER"

echo "==> Packaging"
# --norsrc --noextattr keeps the AppleDouble "._" companion files out of the archive.
ditto -c -k --keepParent --norsrc --noextattr "$SAVER" "$OUTPUT"

# Unpack it again and check the signature survived, since the zip is what people actually get.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto -x -k "$OUTPUT" "$STAGING"
codesign --verify --deep --strict "$STAGING/Constellations.saver"

echo "==> Wrote $OUTPUT ($(du -h "$OUTPUT" | cut -f1))"
