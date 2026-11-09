#!/bin/bash
# 发布当前版本到公开的 releases 仓库，供应用内自动更新使用。
# 用法：./scripts/publish-release.sh [--repo owner/name] [--notes FILE]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REPO="${CARAPACE_RELEASES_REPO:-RyanShawyn/carapace}"
NOTES=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:?--repo 需要 owner/name}"; shift 2 ;;
    --notes) NOTES="${2:?--notes 需要文件}"; shift 2 ;;
    -h|--help)
      echo "用法：./scripts/publish-release.sh [--repo owner/name] [--notes FILE]"
      exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
TAG="v$VERSION"
DMG="$ROOT/dist/Carapace-$VERSION.dmg"
SUMS="$DMG.sha256"
[ -z "$NOTES" ] && NOTES="$ROOT/docs/发布说明-$TAG.md"

command -v gh >/dev/null 2>&1 || { echo "需要 gh 并登录 GitHub" >&2; exit 1; }
gh repo view "$REPO" >/dev/null 2>&1 || {
  echo "目标仓库不存在：$REPO" >&2
  echo "先执行：gh repo create $REPO --public --add-readme" >&2
  exit 1
}

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $TAG 已存在：https://github.com/$REPO/releases/tag/$TAG" >&2
  exit 1
fi

"$ROOT/scripts/package-dmg.sh"
"$ROOT/scripts/check-privacy.sh" || { echo "隐私检查未通过，停止发布" >&2; exit 1; }

SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
printf '%s  %s\n' "$SHA" "$(basename "$DMG")" > "$SUMS"

if [ ! -f "$NOTES" ]; then
  NOTES="$ROOT/dist/release-notes-$TAG.md"
  cat > "$NOTES" <<EOF
# Carapace $VERSION

## 安装

下载 \`$(basename "$DMG")\`，拖进 Applications。ad-hoc 签名，首次打开需右键 → 打开。

## 升级

App 内会自动检查并更新；也可以在设置 → 更新里手动检查。

SHA-256：\`$SHA\`
EOF
fi

gh release create "$TAG" --repo "$REPO" \
  --title "Carapace $VERSION" \
  --notes-file "$NOTES" \
  "$DMG" "$SUMS"

echo "已发布：https://github.com/$REPO/releases/tag/$TAG"
echo "SHA-256：$SHA"