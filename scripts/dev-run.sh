#!/bin/bash
# 本机开发启动：编译并前台运行，不生成 .app，不需要安装。
# 用法：
#   ./scripts/dev-run.sh              # debug 构建，启动后自动打开面板
#   ./scripts/dev-run.sh --release    # release 构建
#   ./scripts/dev-run.sh --once      # 参数会透传给程序
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG=debug
if [[ "${1:-}" == "--release" ]]; then
  CONFIG=release
  shift
fi

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/carapace"
if [[ ! -x "$BIN" ]]; then
  echo "找不到可执行文件：$BIN" >&2
  exit 1
fi

# 单实例锁会让第二个实例静默退出，先收掉旧的开发进程。
pkill -f "$BIN" 2>/dev/null || true
sleep 0.3

echo "==> 启动 $BIN"
echo "    数据库：${CARAPACE_DB:-$HOME/Library/Application Support/Carapace/store.sqlite3}"
echo "    Ctrl-C 退出"
export CARAPACE_SHOW_PANEL="${CARAPACE_SHOW_PANEL:-1}"
exec "$BIN" "$@"
