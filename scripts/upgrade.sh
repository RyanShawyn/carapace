#!/bin/bash
# 一键升级：从 GitHub Release 下载最新 dmg，校验后原地替换 App。
# 只替换 .app，不碰 ~/Library/Application Support/Carapace 里的数据。
# 用法：./scripts/upgrade.sh [--check] [--force] [--no-relaunch] [--app PATH] [--tag TAG]
set -euo pipefail

REPO="${CARAPACE_REPO:-RyanShawyn/carapace}"
APP="${CARAPACE_APP:-/Applications/Carapace.app}"
TAG=""
CHECK_ONLY=0
FORCE=0
RELAUNCH=1

usage() {
  cat <<'EOF'
用法：./scripts/upgrade.sh [选项]

选项：
  --check          只显示本机版本和最新版本，不下载
  --force          已是最新也重新安装
  --no-relaunch    替换后不自动启动
  --app PATH       指定 App 路径（默认 /Applications/Carapace.app）
  --tag TAG        指定版本（默认最新 Release）
  -h, --help       显示帮助

依赖：gh（已登录 GitHub）、hdiutil、ditto。
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1; shift ;;
    --force) FORCE=1; shift ;;
    --no-relaunch) RELAUNCH=0; shift ;;
    --app) APP="${2:?--app 需要路径}"; shift 2 ;;
    --tag) TAG="${2:?--tag 需要版本号}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数：$1" >&2; usage >&2; exit 2 ;;
  esac
done

die() { echo "错误：$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "没有找到 gh，请先安装 GitHub CLI"
gh auth status --hostname github.com >/dev/null 2>&1 || die "gh 未登录，请先执行 gh auth login"

installed_version() {
  [ -d "$1" ] || return 0
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$1/Contents/Info.plist" 2>/dev/null || true
}

if [ -n "$TAG" ]; then
  LATEST_TAG="$TAG"
else
  LATEST_TAG=$(gh release view --repo "$REPO" --json tagName --jq '.tagName') \
    || die "读取最新 Release 失败"
fi
LATEST_VERSION="${LATEST_TAG#v}"
CURRENT=$(installed_version "$APP")

echo "本机：${CURRENT:-未安装}"
echo "最新：${LATEST_VERSION}（${LATEST_TAG}）"

if [ "$CHECK_ONLY" -eq 1 ]; then
  exit 0
fi

if [ -n "$CURRENT" ] && [ "$CURRENT" = "$LATEST_VERSION" ] && [ "$FORCE" -ne 1 ]; then
  echo "已是最新版本，无需升级（需要重装加 --force）。"
  exit 0
fi

if [ ! -w "$(dirname "$APP")" ]; then
  die "$(dirname "$APP") 不可写，无法替换。可加 --app 指定用户目录下的 App"
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/carapace-upgrade.XXXXXX")
NEW="$APP.upgrade.$$"
OLD="$APP.old.$$"
MP=""

cleanup() {
  if [ -n "$MP" ] && [ -d "$MP" ]; then hdiutil detach "$MP" -quiet >/dev/null 2>&1 || true; fi
  rm -rf "$TMP"
  rm -rf "$NEW"
}
trap cleanup EXIT

ASSET=$(gh release view "$LATEST_TAG" --repo "$REPO" --json assets \
  --jq '[.assets[] | select(.name | endswith(".dmg")) | .name] | first // empty')
[ -n "$ASSET" ] || die "Release $LATEST_TAG 里没有 dmg"

echo "下载 $ASSET ..."
ok=0
for attempt in 1 2 3; do
  if gh release download "$LATEST_TAG" --repo "$REPO" --pattern "$ASSET" \
       --dir "$TMP" --clobber; then ok=1; break; fi
  echo "第 $attempt 次下载失败，2 秒后重试" >&2
  sleep 2
done
[ "$ok" -eq 1 ] || die "下载失败（已重试 3 次）"
DMG="$TMP/$ASSET"

EXPECTED=$(gh api "repos/$REPO/releases/tags/$LATEST_TAG" \
  --jq ".assets[] | select(.name == \"$ASSET\") | .digest // empty" 2>/dev/null || true)
EXPECTED="${EXPECTED#sha256:}"
if [ -z "$EXPECTED" ]; then
  EXPECTED=$(gh release view "$LATEST_TAG" --repo "$REPO" --json body --jq .body \
    | grep -oiE 'sha-?256[^0-9a-f]*[0-9a-f]{64}' | grep -oiE '[0-9a-f]{64}' | head -1 || true)
fi
if [ -n "$EXPECTED" ]; then
  ACTUAL=$(shasum -a 256 "$DMG" | awk '{print $1}')
  [ "$ACTUAL" = "$EXPECTED" ] || die "校验失败：期望 ${EXPECTED}，实际 $ACTUAL"
  echo "SHA-256 校验通过"
else
  echo "提示：Release 没有提供校验值，跳过 SHA-256 校验" >&2
fi

MP=$(hdiutil attach -nobrowse -readonly "$DMG" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')
[ -n "$MP" ] && [ -d "$MP/Carapace.app" ] || die "dmg 里没有 Carapace.app"

NEW_VERSION=$(installed_version "$MP/Carapace.app")
[ "$NEW_VERSION" = "$LATEST_VERSION" ] || die "dmg 版本 $NEW_VERSION 与 Release $LATEST_VERSION 不一致"

if pgrep -x carapace >/dev/null 2>&1; then
  echo "退出正在运行的 Carapace ..."
  osascript -e 'tell application "Carapace" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -x carapace >/dev/null 2>&1 || break
    sleep 0.25
  done
  pgrep -x carapace >/dev/null 2>&1 && kill "$(pgrep -x carapace)" 2>/dev/null || true
  sleep 0.5
fi

echo "安装 $NEW_VERSION 到 $APP ..."
ditto "$MP/Carapace.app" "$NEW"
xattr -dr com.apple.quarantine "$NEW" 2>/dev/null || true
codesign --verify --deep --strict "$NEW" >/dev/null 2>&1 || {
  rm -rf "$NEW"
  die "新 App 签名校验失败，未替换"
}

if [ -d "$APP" ]; then mv "$APP" "$OLD"; fi
if ! mv "$NEW" "$APP"; then
  [ -d "$OLD" ] && mv "$OLD" "$APP"
  die "替换失败，已回滚"
fi
rm -rf "$OLD"

echo "已升级到 $NEW_VERSION"

if [ "$RELAUNCH" -eq 1 ]; then
  open "$APP"
  echo "已启动 Carapace"
fi