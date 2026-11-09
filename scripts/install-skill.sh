#!/bin/bash
# 安装 carapace skill。支持个人级、项目级和任意目录。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$SCRIPT_DIR/skills/carapace" ]; then
  ROOT="$SCRIPT_DIR"
elif [ -d "$SCRIPT_DIR/../skills/carapace" ]; then
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  echo "找不到 skills/carapace，请在仓库根目录或 dmg 内运行。" >&2
  exit 1
fi
SRC="$ROOT/skills/carapace"

DEST="$HOME/.claude/skills"
LINK=""
BIN_DIR=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --personal)
      DEST="$HOME/.claude/skills"; shift ;;
    --project)
      DEST="$PWD/.claude/skills"; shift ;;
    --dir)
      DEST="${2:?--dir 需要目录}"; shift 2 ;;
    --link)
      LINK="${2:?--link 需要目录}"; shift 2 ;;
    --bin)
      BIN_DIR="${2:?--bin 需要目录}"; shift 2 ;;
    --force)
      FORCE=1; shift ;;
    -h|--help)
      cat <<'EOF'
用法：
  ./scripts/install-skill.sh [--personal | --project | --dir DIR] [选项]

选项：
  --personal        安装到 ~/.claude/skills（默认）
  --project         安装到当前项目 .claude/skills
  --dir DIR         安装到任意目录
  --link DIR        在 DIR 创建软链，指向安装目录
                    （Claude Code 只自动加载 ~/.claude/skills 和项目 .claude/skills）
  --bin DIR         在 DIR 创建 carapace 软链，指向 App 内的 CLI
  --force           覆盖已有安装
EOF
      exit 0 ;;
    *)
      echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

TARGET="$DEST/carapace"
if [ -e "$TARGET" ] && [ "$FORCE" -ne 1 ]; then
  echo "已存在：${TARGET}（用 --force 覆盖）" >&2
  exit 1
fi

mkdir -p "$DEST"
rm -rf "$TARGET"
cp -R "$SRC" "$TARGET"
chmod +x "$TARGET/scripts/find-carapace.sh" 2>/dev/null || true
echo "skill 已安装：$TARGET"

if [ -n "$LINK" ]; then
  mkdir -p "$LINK"
  if [ -e "$LINK/carapace" ] || [ -L "$LINK/carapace" ]; then
    if [ "$FORCE" -eq 1 ]; then rm -f "$LINK/carapace"; else
      echo "软链已存在：$LINK/carapace（用 --force 覆盖）" >&2; exit 1
    fi
  fi
  ln -s "$TARGET" "$LINK/carapace"
  echo "软链已创建：$LINK/carapace -> $TARGET"
fi

if [ -n "$BIN_DIR" ]; then
  CLI=""
  if [ -n "${CARAPACE_BIN:-}" ] && [ -x "$CARAPACE_BIN" ]; then
    CLI="$CARAPACE_BIN"
  elif [ -x "/Applications/Carapace.app/Contents/Helpers/carapace" ]; then
    CLI="/Applications/Carapace.app/Contents/Helpers/carapace"
  elif [ -x "$ROOT/Carapace.app/Contents/Helpers/carapace" ]; then
    CLI="$ROOT/Carapace.app/Contents/Helpers/carapace"
  elif [ -x "$ROOT/../Carapace.app/Contents/Helpers/carapace" ]; then
    CLI="$(cd "$ROOT/.." && pwd)/Carapace.app/Contents/Helpers/carapace"
  elif [ -x "$ROOT/build/Carapace.app/Contents/Helpers/carapace" ]; then
    CLI="$ROOT/build/Carapace.app/Contents/Helpers/carapace"
  elif [ -x "$ROOT/.build/debug/carapace-cli" ]; then
    CLI="$ROOT/.build/debug/carapace-cli"
  fi
  if [ -z "$CLI" ]; then
    echo "没有找到 carapace CLI；跳过 --bin。可先构建或安装 App。" >&2
  else
    mkdir -p "$BIN_DIR"
    ln -sfn "$CLI" "$BIN_DIR/carapace"
    echo "CLI 软链已创建：$BIN_DIR/carapace -> $CLI"
  fi
fi

if command -v carapace >/dev/null 2>&1; then
  carapace version --json || true
else
  HINT_DIR="${BIN_DIR:-$HOME/.local/bin}"
  echo "提示：把以下目录加入 PATH 后即可直接运行 carapace："
  echo "  export PATH=\"$HINT_DIR:\$PATH\""
fi

cat <<'EOF'

Claude Code 权限（可选，写入项目 .claude/settings.json 或全局设置）：
{
  "permissions": {
    "allow": ["Bash(carapace:*)"]
  }
}

Claude Code 只自动加载 ~/.claude/skills 和项目 .claude/skills。
如果用了 --dir 装到其它位置，请同时加 --link ~/.claude/skills。
EOF