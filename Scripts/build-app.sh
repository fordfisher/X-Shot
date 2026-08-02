#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/XShot.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

cd "$ROOT"

echo "==> Building XShot (release, universal)…"
# Build each arch then lipo — SPM may not support multi-arch in one invoke on all toolchains.
BUILD_DIR="$ROOT/.build"
swift build -c release --arch arm64
ARM_BIN="$BUILD_DIR/arm64-apple-macosx/release/XShot"

if swift build -c release --arch x86_64 2>/dev/null; then
  X86_BIN="$BUILD_DIR/x86_64-apple-macosx/release/XShot"
  UNIVERSAL=1
else
  echo "⚠︎ x86_64 build unavailable; shipping arm64-only binary"
  UNIVERSAL=0
fi

echo "==> Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

if [[ ! -f "$ROOT/Resources/AppIcon.icns" ]]; then
  echo "==> Generating AppIcon.icns…"
  swift "$ROOT/Scripts/generate-icon.swift" "$ROOT"
fi

cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"

if [[ "$UNIVERSAL" == "1" && -f "$X86_BIN" ]]; then
  lipo -create -output "$MACOS/XShot" "$ARM_BIN" "$X86_BIN"
else
  cp "$ARM_BIN" "$MACOS/XShot"
fi
chmod +x "$MACOS/XShot"

# Optional ad-hoc sign for local distribution
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep -s - "$APP" 2>/dev/null || true
fi

echo "==> Done: $APP"
echo "    Open with: open \"$APP\""
ls -lh "$MACOS/XShot"
file "$MACOS/XShot"
