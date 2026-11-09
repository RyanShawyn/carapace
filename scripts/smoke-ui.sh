#!/bin/bash
# 本机 UI 冒烟：临时库启动 App，确认进程存活、数据库健康、面板可打开。
# 用独立 CARAPACE_LOCK，不会和正在运行的 Carapace 抢单实例锁。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build >/dev/null
BIN="$ROOT/.build/debug/carapace"
CLI="$ROOT/.build/debug/carapace-cli"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/carapace-smoke.XXXXXX")"

export CARAPACE_DB="$TMP/store.sqlite3"
export CARAPACE_DEFAULTS_SUITE="com.ryan.carapace.test.smoke.$$"
export CARAPACE_LOCK="$TMP/app.lock"
export CARAPACE_SHOW_PANEL=1
export CARAPACE_PIN_PANEL=1

cleanup() {
  [ -n "${PID:-}" ] && kill "$PID" 2>/dev/null || true
  rm -rf "$TMP"
  defaults delete "$CARAPACE_DEFAULTS_SUITE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

"$BIN" > "$TMP/app.log" 2>&1 &
PID=$!
sleep 8

if ! kill -0 "$PID" 2>/dev/null; then
  echo "FAIL: App exited early" >&2
  cat "$TMP/app.log" >&2
  exit 1
fi

"$CLI" doctor --json --db "$CARAPACE_DB" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["ok"] and d["data"]["healthy"], d; print("UI SMOKE PASS")'
