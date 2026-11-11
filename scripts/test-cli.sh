#!/bin/bash
# CLI 契约测试。始终使用临时库和临时偏好域，不碰真实数据。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BIN="$ROOT/.build/debug/carapace-cli"
if [ ! -x "$BIN" ]; then
  swift build --product carapace-cli
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/carapace-cli-tests.XXXXXX")"
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
  python3 -c '
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

expect_ok() {
  local json="$1"
  expect_json "$json" "ok" "True"
}

echo "== doctor"
OUT="$("$BIN" doctor --json)"
expect_ok "$OUT"
expect_json "$OUT" "data.healthy" "True"
expect_json "$OUT" "meta.schema_version" "8"

echo "== positions"
OUT="$("$BIN" positions add --code 600000 --name 浦发银行 --quantity 100 --cost 10 --json)"
expect_ok "$OUT"
PID="$(printf '%s' "$OUT" | json_field data.id)"
OUT="$("$BIN" positions list --json)"
expect_json "$OUT" "data.0.id" "$PID"

echo "== trades + idempotency"
OUT="$("$BIN" trades record --position "$PID" --side buy --quantity 100 --price 10 \
  --request-id test-1 --json)"
expect_ok "$OUT"
OUT2="$("$BIN" trades record --position "$PID" --side buy --quantity 100 --price 10 \
  --request-id test-1 --json)"
expect_ok "$OUT2"
expect_json "$OUT2" "data.change.id" "$(printf '%s' "$OUT" | json_field data.change.id)"
OUT="$("$BIN" positions changes --id "$PID" --json)"
python3 -c 'import json,sys; assert len(json.load(sys.stdin)["data"]) == 2' <<<"$OUT" \
  || fail "重复 request-id 不应重复记账"

echo "== watch and plans"
OUT="$("$BIN" watch add --code 00700 --name 腾讯控股 --market hk --watch-price 380 --json)"
expect_ok "$OUT"
expect_json "$OUT" "data.currency" "HKD"
cat > "$TMP/levels.json" <<'JSON'
[{"kind":"buy","price":9,"quantity":100,"condition":"回落"}]
JSON
OUT="$("$BIN" plans update --position "$PID" --levels-file "$TMP/levels.json" --json)"
expect_ok "$OUT"
VERSION="$(printf '%s' "$OUT" | json_field data.plan.version)"

echo "== drafts"
cat > "$TMP/plan.json" <<'JSON'
{"levels":[{"kind":"buy","price":9,"quantity":100,"condition":"回落"},{"kind":"sell","price":12,"quantity":100,"condition":"止盈"}],"description":"测试","nextReview":"2026-12-01"}
JSON
OUT="$("$BIN" drafts create --position "$PID" --payload-file "$TMP/plan.json" \
  --base-version "$VERSION" --json)"
expect_ok "$OUT"
DID="$(printf '%s' "$OUT" | json_field data.id)"
OUT="$("$BIN" drafts apply --id "$DID" --yes --json)"
expect_ok "$OUT"
expect_json "$OUT" "data.plan.version" "$((VERSION + 1))"

echo "== remove plan"
set +e
OUT="$("$BIN" plans remove --position "$PID" --json 2>&1)"
STATUS=$?
set -e
[ "$STATUS" -eq 2 ] || fail "plans remove 缺 --yes 应退出 2，实际 $STATUS"
OUT="$("$BIN" plans remove --position "$PID" --yes --json)"
expect_ok "$OUT"
expect_json "$OUT" "data.removed" "True"
OUT="$("$BIN" plans get --position "$PID" --json || true)"
expect_json "$OUT" "error.code" "NOT_FOUND"

echo "== reviews and memories"
OUT="$("$BIN" reviews create --position "$PID" --kind plan --due 2026-12-01 --json)"
expect_ok "$OUT"
RID="$(printf '%s' "$OUT" | json_field data.id)"
echo "notes" > "$TMP/notes.md"
OUT="$("$BIN" reviews save --id "$RID" --notes-file "$TMP/notes.md" --json)"
expect_ok "$OUT"
OUT="$("$BIN" memories add --scope global --kind principle --title 不追高 \
  --content 只在计划档位买入 --json)"
expect_ok "$OUT"
OUT="$("$BIN" memories context --position "$PID" --json)"
expect_ok "$OUT"

echo "== settings"
OUT="$("$BIN" settings set --key hkdRate --value 0.86 --json)"
expect_ok "$OUT"
OUT="$("$BIN" settings get --key hkdRate --json)"
expect_ok "$OUT"

echo "== import"
OUT="$("$BIN" accounts add --broker 测试券商 --name 测试账户 --default --json)"
expect_ok "$OUT"
cat > "$TMP/import.csv" <<'CSV'
成交日期,证券代码,证券名称,买卖方向,成交数量,成交价格,成交金额,佣金,印花税,过户费,成交编号
2026-01-02,600000,浦发银行,买入,100,10.00,1000.00,1.00,0,0,T001
2026-01-03,600000,浦发银行,卖出,40,12.00,480.00,1.00,0.48,0,T002
CSV
OUT="$("$BIN" import preview --file "$TMP/import.csv" --json)"
expect_ok "$OUT"
expect_json "$OUT" "data.summary.ready" "2"
OUT="$("$BIN" import commit --file "$TMP/import.csv" --yes --json)"
expect_ok "$OUT"
expect_json "$OUT" "data.imported" "2"

echo "== maintenance"
OUT="$("$BIN" verify --json)"
expect_ok "$OUT"
expect_json "$OUT" "data.fixed" "0"
OUT="$("$BIN" backup --to "$TMP/backup.sqlite3" --json)"
expect_ok "$OUT"
OUT="$("$BIN" export-csv --to "$TMP/changes.csv" --json)"
expect_ok "$OUT"

echo "CLI TESTS PASS"