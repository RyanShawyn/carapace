#!/bin/bash
# Skill 文档契约测试：验证 skills/carapace 示例依赖的 CLI 返回结构。
# 始终使用临时库和临时偏好域，不碰真实数据；不访问外部行情。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN="$ROOT/.build/debug/carapace-cli"
if [ ! -x "$BIN" ]; then
  swift build --product carapace-cli
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/carapace-skill-contract.XXXXXX")"
export CARAPACE_DB="$TMP/store.sqlite3"
export CARAPACE_DEFAULTS_SUITE="com.ryan.carapace.test.$$"

cleanup() {
  rm -rf "$TMP"
  defaults delete "$CARAPACE_DEFAULTS_SUITE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

json_field() {
  python3 -I -c '
import json, sys
data = json.load(sys.stdin)
for key in sys.argv[1].split("."):
    if isinstance(data, list):
        data = data[int(key)]
    else:
        data = data[key]
print(data)
' "$1"
}

expect_json() {
  local json="$1" path="$2" expected="$3"
  local actual
  actual="$(printf '%s' "$json" | json_field "$path")"
  [ "$actual" = "$expected" ] || fail "$path 期望 ${expected}，实际 $actual"
}

echo "== doctor envelope"
OUT="$("$BIN" doctor --json)"
expect_json "$OUT" "ok" "True"
expect_json "$OUT" "data.healthy" "True"
expect_json "$OUT" "data.api_version" "1"
expect_json "$OUT" "data.schema_version" "8"
expect_json "$OUT" "meta.api_version" "1"
expect_json "$OUT" "meta.schema_version" "8"
printf '%s' "$OUT" | python3 -I -c '
import json, sys
data = json.load(sys.stdin)
assert "as_of" in data["meta"], data
assert "healthy" not in data["meta"], data
assert {"name", "ok"} <= set(data["data"]["checks"][0]), data
'

echo "== synthetic position and write preview"
OUT="$("$BIN" positions add --code 000000 --name 示例股份 --quantity 100 --cost 10 \
  --request-id skill-contract-position --dry-run --json)"
expect_json "$OUT" "ok" "True"
expect_json "$OUT" "data.dry_run" "True"
OUT="$("$BIN" positions list --json)"
expect_json "$OUT" "data" "[]"
OUT="$("$BIN" positions add --code 000000 --name 示例股份 --quantity 100 --cost 10 \
  --request-id skill-contract-position --json)"
expect_json "$OUT" "ok" "True"
expect_json "$OUT" "data.dry_run" "False"
expect_json "$OUT" "data.code" "000000"
PID="$(printf '%s' "$OUT" | json_field data.id)"

echo "== request-id idempotency"
OUT="$("$BIN" trades record --position "$PID" --side buy --quantity 100 --price 10 \
  --request-id skill-contract-trade --json)"
CHANGE_ID="$(printf '%s' "$OUT" | json_field data.change.id)"
OUT="$("$BIN" trades record --position "$PID" --side buy --quantity 100 --price 10 \
  --request-id skill-contract-trade --json)"
expect_json "$OUT" "data.change.id" "$CHANGE_ID"
OUT="$("$BIN" positions changes --id "$PID" --json)"
printf '%s' "$OUT" | python3 -I -c '
import json, sys
rows = json.load(sys.stdin)["data"]
assert len(rows) == 2, rows
'

echo "== destructive command requires --yes even for --dry-run"
set +e
OUT="$("$BIN" positions clear --id "$PID" --price 10 --dry-run --json 2>&1)"
STATUS=$?
set -e
[ "$STATUS" -eq 2 ] || fail "positions clear 预览缺 --yes 应退出 2，实际 $STATUS"
printf '%s' "$OUT" | grep -q -- '--yes' || fail "错误提示应包含 --yes"
OUT="$("$BIN" positions clear --id "$PID" --price 10 --yes \
  --request-id skill-contract-clear --dry-run --json)"
expect_json "$OUT" "data.dry_run" "True"
OUT="$("$BIN" positions changes --id "$PID" --json)"
printf '%s' "$OUT" | python3 -I -c '
import json, sys
rows = json.load(sys.stdin)["data"]
assert len(rows) == 2, rows
'

echo "== plan draft version contract"
cat > "$TMP/levels.json" <<'JSON'
[{"kind":"buy","price":9,"quantity":100,"condition":"回落"}]
JSON
OUT="$("$BIN" plans update --position "$PID" --levels-file "$TMP/levels.json" \
  --request-id skill-contract-plan --json)"
VERSION="$(printf '%s' "$OUT" | json_field data.plan.version)"
cat > "$TMP/plan.json" <<'JSON'
{"levels":[{"kind":"sell","price":12,"quantity":100,"condition":"止盈"}],"description":"复核后的计划","nextReview":"2026-12-01"}
JSON
OUT="$("$BIN" drafts create --kind plan --position "$PID" --payload-file "$TMP/plan.json" \
  --base-version "$VERSION" --request-id skill-contract-draft --json)"
DID="$(printf '%s' "$OUT" | json_field data.id)"
OUT="$("$BIN" drafts apply --id "$DID" --yes --request-id skill-contract-apply --json)"
expect_json "$OUT" "data.plan.version" "$((VERSION + 1))"

OUT="$("$BIN" drafts create --kind plan --position "$PID" --payload-file "$TMP/plan.json" \
  --base-version "$VERSION" --request-id skill-contract-stale --json)"
STALE="$(printf '%s' "$OUT" | json_field data.id)"
set +e
OUT="$("$BIN" drafts apply --id "$STALE" --yes --request-id skill-contract-stale-apply --json)"
STATUS=$?
set -e
[ "$STATUS" -eq 5 ] || fail "过期草稿应退出 5，实际 $STATUS"
expect_json "$OUT" "error.code" "CONFLICT"

echo "== import dry-run requires --yes and leaves no batch"
OUT="$("$BIN" accounts add --broker 示例券商 --name 示例账户 --default \
  --request-id skill-contract-account --json)"
cat > "$TMP/import.csv" <<'CSV'
成交日期,证券代码,证券名称,买卖方向,成交数量,成交价格,成交金额,佣金,印花税,过户费,成交编号
2026-01-02,000000,示例股份,买入,100,10.00,1000.00,1.00,0,0,T001
CSV
OUT="$("$BIN" import preview --file "$TMP/import.csv" --json)"
expect_json "$OUT" "data.summary.ready" "1"
OUT="$("$BIN" import commit --file "$TMP/import.csv" --yes \
  --request-id skill-contract-import --dry-run --json)"
expect_json "$OUT" "data.dry_run" "True"
expect_json "$OUT" "data.summary.ready" "1"
OUT="$("$BIN" import batches --json)"
expect_json "$OUT" "data" "[]"

echo "== memory context contract"
OUT="$("$BIN" memories add --scope global --kind principle --title 不追高 \
  --content 只在计划档位买入 --confidence 0.8 \
  --request-id skill-contract-memory --json)"
expect_json "$OUT" "data.scope" "global"
OUT="$("$BIN" memories context --position "$PID" --json)"
printf '%s' "$OUT" | python3 -I -c '
import json, sys
data = json.load(sys.stdin)["data"]
assert isinstance(data["memories"], list), data
assert "[M1]" in data["text"], data
'

echo "SKILL CONTRACT TESTS PASS"
