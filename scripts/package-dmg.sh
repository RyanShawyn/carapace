#!/bin/bash
# 打包 macOS 安装包（DMG）：先构建 .app，再生成 dist/Carapace-<版本>.dmg。
# 用法：./scripts/package-dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

"$ROOT/scripts/build-app.sh"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
  "$ROOT/Resources/Info.plist")
APP="$ROOT/build/Carapace.app"
DMG="$ROOT/dist/Carapace-$VERSION.dmg"

if [[ ! -d "$APP" ]]; then
  echo "构建产物不存在：$APP" >&2
  exit 1
fi

mkdir -p "$ROOT/dist"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/carapace-dmg.XXXXXX")
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# 安装包只放 App 本体。skill 只随仓库分发，不打进 dmg：
# 它面向 Claude Code，不是 App 运行所需，混在安装包里容易被误装。
# 需要时从仓库运行 scripts/install-skill.sh。

rm -f "$DMG"
hdiutil create -volname "Carapace $VERSION" -srcfolder "$STAGE" \
  -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

echo "$DMG"
shasum -a 256 "$DMG"
echo "提示：ad-hoc 签名，首次打开请右键 → 打开，或执行"
echo "      xattr -dr com.apple.quarantine \"$DMG\""
