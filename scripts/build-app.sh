#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
ARCHES="${MUSSOL_ARCHES:-$(uname -m)}"
APP="$ROOT/dist/Mussol Feiner.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
ICON_SOURCE="$ROOT/assets/mussol-feiner-icon.png"
ICONSET="$ROOT/.build/MussolFeiner.iconset"
RELEASE_DIR="$ROOT/.build/release"
BINARY="$RELEASE_DIR/mussol-feiner"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ROOT/Support/Info.plist")"

read -r -a ARCH_LIST <<< "$ARCHES"
mkdir -p "$RELEASE_DIR"
ARCH_BINARIES=()

for arch in "${ARCH_LIST[@]}"; do
  case "$arch" in
    arm64|x86_64) ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
  esac

  arch_binary="$RELEASE_DIR/mussol-feiner-$arch"
  swiftc \
    -parse-as-library \
    -sdk "$SDK" \
    -target "$arch-apple-macos13.0" \
    -O \
    -whole-module-optimization \
    -framework AppKit \
    -framework Charts \
    -framework SwiftUI \
    -framework UniformTypeIdentifiers \
    "$ROOT"/Sources/MussolFeinerCore/*.swift \
    "$ROOT"/Sources/MussolFeiner/*.swift \
    -o "$arch_binary"
  ARCH_BINARIES+=("$arch_binary")
done

if [[ ${#ARCH_BINARIES[@]} -eq 1 ]]; then
  cp "${ARCH_BINARIES[0]}" "$BINARY"
else
  lipo -create "${ARCH_BINARIES[@]}" -output "$BINARY"
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BINARY" "$MACOS/mussol-feiner"
cp "$ROOT/Support/Info.plist" "$CONTENTS/Info.plist"

if [[ -f "$ICON_SOURCE" ]]; then
  cp "$ICON_SOURCE" "$RESOURCES/mussol-feiner-icon.png"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
  cp "$ICON_SOURCE" "$ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
fi

xattr -cr "$APP"
/usr/bin/codesign \
  --force \
  --deep \
  --sign - \
  --requirements "=designated => identifier \"$BUNDLE_ID\"" \
  "$APP" >/dev/null

echo "$APP"
