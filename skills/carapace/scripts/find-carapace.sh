#!/bin/bash
# 输出可用的 carapace CLI 路径；找不到时退出 1。
set -euo pipefail

if [ -n "${CARAPACE_BIN:-}" ] && [ -x "$CARAPACE_BIN" ]; then
  echo "$CARAPACE_BIN"; exit 0
fi
if command -v carapace >/dev/null 2>&1; then
  command -v carapace; exit 0
fi
for candidate in \
  "/Applications/Carapace.app/Contents/Helpers/carapace" \
  "$HOME/Applications/Carapace.app/Contents/Helpers/carapace" \
  "./build/Carapace.app/Contents/Helpers/carapace" \
  "./.build/debug/carapace-cli"; do
  if [ -x "$candidate" ]; then
    echo "$candidate"; exit 0
  fi
done
echo "找不到 carapace CLI；运行 ./scripts/install-skill.sh --personal --bin ~/.local/bin" >&2
exit 1