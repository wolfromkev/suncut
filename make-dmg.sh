#!/usr/bin/env bash
# Build a Release app and pack it into a DMG for another Mac.
# The other Mac does not need Xcode. First launch needs one Gatekeeper approval.
# Signs with the same stable keychain identity as install.sh.
# Refuses to ad-hoc sign: that signature changes every build, so macOS re-asks
# for Screen Recording, Microphone, and Accessibility after each update.
# Usage: ./make-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$ROOT/UmbrellaHelper.xcodeproj"
SCHEME="UmbrellaHelper"
APP_NAME="Suncut"
BUILD_DIR="$ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
ENTITLEMENTS="$ROOT/UmbrellaHelper/UmbrellaHelper.entitlements"
IDENTITY_FILE="$ROOT/.signing-identity"
STAGING=""

cleanup() {
  if [[ -n "$STAGING" && -d "$STAGING" ]]; then
    rm -rf "$STAGING"
  fi
}
trap cleanup EXIT

# Keep this in sync with install.sh. Prefer UMBRELLA_SIGN_IDENTITY, then the
# identity saved in .signing-identity, then Apple Development.
resolve_sign_identity() {
  local identities saved name
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  identity_is_valid() {
    printf '%s\n' "$identities" | grep -F -q "\"$1\""
  }

  if [[ -n "${UMBRELLA_SIGN_IDENTITY:-}" ]]; then
    if identity_is_valid "$UMBRELLA_SIGN_IDENTITY"; then
      printf '%s\n' "$UMBRELLA_SIGN_IDENTITY"
      return 0
    fi
    echo "Warning: UMBRELLA_SIGN_IDENTITY is not a valid codesigning identity: ${UMBRELLA_SIGN_IDENTITY}" >&2
    return 1
  fi

  if [[ -f "$IDENTITY_FILE" ]]; then
    saved="$(tr -d '\n' < "$IDENTITY_FILE")"
    if [[ -n "$saved" ]] && identity_is_valid "$saved"; then
      printf '%s\n' "$saved"
      return 0
    fi
  fi

  name="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)"
  if [[ -z "$name" ]]; then
    name="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Mac Developer:[^"]*\)".*/\1/p' | head -n 1)"
  fi
  if [[ -z "$name" ]]; then
    name="$(printf '%s\n' "$identities" | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)"
  fi
  if [[ -n "$name" ]]; then
    printf '%s\n' "$name"
    return 0
  fi
  return 1
}

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  if [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
  elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
fi

build_release() {
  local archs="$1"
  echo "Building ${APP_NAME} (${archs})..."
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="$archs" \
    build
}

if ! build_release "arm64 x86_64"; then
  echo "Universal build failed. Building for this Mac (arm64) only..." >&2
  build_release "arm64"
fi

BUILT_APP="$DERIVED/Build/Products/Release/${APP_NAME}.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build failed: app bundle not found at $BUILT_APP" >&2
  exit 1
fi

if ! SIGN_IDENTITY="$(resolve_sign_identity)"; then
  echo "No stable codesigning identity found. Refusing to ad-hoc sign, because that signature changes every build and macOS asks for Screen Recording, Microphone, and Accessibility again." >&2
  echo "Install an Apple Development certificate in Xcode, or set UMBRELLA_SIGN_IDENTITY." >&2
  exit 1
fi

printf '%s\n' "$SIGN_IDENTITY" > "$IDENTITY_FILE"
echo "Signing with stable identity: $SIGN_IDENTITY"
codesign --force --deep --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --identifier "com.kevinwolfrom.umbrella" \
  --sign "$SIGN_IDENTITY" \
  "$BUILT_APP"
codesign --verify --deep --strict "$BUILT_APP"

SIGN_DETAILS="$(codesign -dv --verbose=4 "$BUILT_APP" 2>&1 || true)"
if printf '%s\n' "$SIGN_DETAILS" | grep -q '^Signature=adhoc$'; then
  echo "Refusing to pack an ad-hoc signed app." >&2
  exit 1
fi
if ! printf '%s\n' "$SIGN_DETAILS" | grep -F -q "Authority=${SIGN_IDENTITY}"; then
  echo "Signed authority does not match the stable identity. Refusing to pack the disk image." >&2
  exit 1
fi
printf '%s\n' "$SIGN_DETAILS" | awk -F= '/^TeamIdentifier=|^Signature=|^Authority=/{ print }'

EXECUTABLE="$BUILT_APP/Contents/MacOS/${APP_NAME}"
echo "Architectures: $(lipo -archs "$EXECUTABLE")"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_APP/Contents/Info.plist")"
DMG="$BUILD_DIR/Suncut ${VERSION}.dmg"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/suncut-dmg.XXXXXX")"
ditto "$BUILT_APP" "$STAGING/${APP_NAME}.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Read Me.txt" <<'EOF'
Suncut

1. Drag Suncut onto the Applications folder.
2. Eject this disk image.
3. In Applications, right-click Suncut and choose Open, then Open again.
   macOS blocks apps that did not come from the App Store the first time you open them.
4. If macOS says the app is damaged, open Terminal and run:

   xattr -cr "/Applications/Suncut.app"

   Then right-click the app and choose Open again.
5. Grant Screen Recording when asked (and Microphone if you record audio).
6. Later updates: right-click the menu-bar icon and choose Check for Updates.

Requires macOS 14 or later. No Xcode needed.
EOF

mkdir -p "$BUILD_DIR"
rm -f "$DMG"
if diskutil image create from --help >/dev/null 2>&1; then
  diskutil image create from \
    --format UDZO \
    --volumeName "Suncut" \
    "$STAGING" \
    "$DMG"
else
  hdiutil create \
    -volname "Suncut" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG"
fi

STABLE="$BUILD_DIR/Suncut.dmg"
cp -f "$DMG" "$STABLE"

echo ""
echo "DMG ready: $DMG"
echo "GitHub asset: $STABLE"
echo "Signed with stable identity: $SIGN_IDENTITY"
echo "Copy that file to the other Mac, open it, and drag the app to Applications."
echo "The first open needs the steps in Read Me.txt."
