#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if xcrun --sdk macosx --show-sdk-platform-path >/dev/null 2>&1; then
  swift test
  exit 0
fi

echo "Full Xcode platform metadata is unavailable; running the direct core harness."
SDK="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"
mkdir -p "$ROOT/.build"
swiftc \
  -parse-as-library \
  -sdk "$SDK" \
  -target "$ARCH-apple-macos13.0" \
  "$ROOT"/Sources/MussolFeinerCore/*.swift \
  "$ROOT"/scripts/core-harness.swift \
  -o "$ROOT/.build/mussol-feiner-core-harness"
"$ROOT/.build/mussol-feiner-core-harness"
