#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/Carapace.app"
rm -rf "$APP"

# 优先用 xcbuild 一次产出通用二进制；只有 Command Line Tools 时分别编译再 lipo。
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
  BIN=".build/apple/Products/Release/carapace"
  BIN_CLI=".build/apple/Products/Release/carapace-cli"
else
  swift build -c release --arch arm64 --scratch-path .build/arm64
  swift build -c release --arch x86_64 --scratch-path .build/x86
  mkdir -p .build/universal
  lipo -create .build/arm64/release/carapace .build/x86/release/carapace \
    -output .build/universal/carapace
  lipo -create .build/arm64/release/carapace-cli .build/x86/release/carapace-cli \
    -output .build/universal/carapace-cli
  BIN=".build/universal/carapace"
  BIN_CLI=".build/universal/carapace-cli"
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$BIN" "$APP/Contents/MacOS/carapace"
cp "$BIN_CLI" "$APP/Contents/Helpers/carapace"
chmod +x "$APP/Contents/Helpers/carapace"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep --sign - "$APP" >/dev/null
echo "$APP"
lipo -info "$APP/Contents/MacOS/carapace" || true
lipo -info "$APP/Contents/Helpers/carapace" || true
