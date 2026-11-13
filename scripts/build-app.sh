#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/Carapace.app"
rm -rf "$APP"

# 优先用 xcbuild 一次产出通用二进制；只有 Command Line Tools 时分别编译再 lipo。
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
  # 新版 SwiftPM 产在 .build/out/Products/Release，旧版在 .build/apple/Products/Release。
  for dir in .build/apple/Products/Release .build/out/Products/Release; do
    if [ -x "$dir/carapace" ] && [ -x "$dir/carapace-cli" ]; then
      BIN="$dir/carapace"
      BIN_CLI="$dir/carapace-cli"
      break
    fi
  done
  [ -n "${BIN:-}" ] || { echo "未找到 universal 产物" >&2; exit 1; }
else
  swift build -c release --arch arm64 --scratch-path .build/arm64
  swift build -c release --arch x86_64 --scratch-path .build/x86
  ARM_BIN="$(find .build/arm64 -path "*/release/carapace" -type f | head -1)"
  ARM_CLI="$(find .build/arm64 -path "*/release/carapace-cli" -type f | head -1)"
  X86_BIN="$(find .build/x86 -path "*/release/carapace" -type f | head -1)"
  X86_CLI="$(find .build/x86 -path "*/release/carapace-cli" -type f | head -1)"
  mkdir -p .build/universal
  lipo -create "$ARM_BIN" "$X86_BIN" -output .build/universal/carapace
  lipo -create "$ARM_CLI" "$X86_CLI" -output .build/universal/carapace-cli
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
