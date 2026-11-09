# Carapace CLI 命令

所有命令默认输出 JSON。通用参数：

| 参数 | 说明 |
|---|---|
| `--json` | JSON 输出（默认） |
| `--format text` | 人类可读输出 |
| `--db PATH` | 覆盖数据库路径，默认 `~/Library/Application Support/Carapace/store.sqlite3` |
| `--dry-run` | 只预览，不写入 |
| `--yes` | 确认破坏性操作 |
| `--request-id ID` | 写操作幂等键 |
| `--no-notify` | 不通知运行中的 App 刷新 |

## 自检

```bash
carapace doctor --json
carapace schema --json
carapace version --json
```

## 组合

```bash
carapace portfolio --json
carapace portfolio --no-quotes --json
carapace portfolio --refresh --json
```

## 持仓

```bash
carapace positions list --json
carapace positions list --closed --json
carapace positions get --id 12 --json
carapace positions get --code 600000 --json
carapace positions add --code 600000 --name 浦发银行 --quantity 100 --cost 10 --json
carapace positions add --code 600000 --name 浦发银行 --quantity 100 --cost 10 \
  --plan-file /tmp/plan.json --description "首仓" --next-review 2026-12-01 --json
carapace positions correct --id 12 --quantity 200 --cost 10.5 --reason "补录" --json
carapace positions clear --id 12 --price 12 --fee 2 --yes --json
carapace positions changes --id 12 --limit 50 --json
```

## 成交

```bash
carapace trades record --position 12 --side buy --quantity 100 --price 10.2 --fee 1 \
  --request-id "$(uuidgen)" --json
carapace trades record --position 12 --side sell --quantity 100 --price 12.5 \
  --level-id <计划档位 ID> --request-id "$(uuidgen)" --json
carapace trades list --position 12 --json
carapace trades list --type buy --limit 100 --json
```

## 计划

```bash
carapace plans get --position 12 --json
carapace plans update --position 12 --levels-file /tmp/levels.json \
  --if-version 3 --note "复核后调整" --json

# 修改已有计划必须带 --if-version；不带会返回 VALIDATION。
```

`levels.json` 可以是数组：

```json
[
  {"kind": "buy", "price": 9.5, "quantity": 1000, "condition": "回到 20 日线"},
  {"kind": "sell", "price": 15, "quantity": 500, "condition": "估值上沿"},
  {"kind": "stop", "price": 8.2, "quantity": null, "condition": "逻辑失效"}
]
```

也可以是 `{"levels": [...]}`。

## 草稿

```bash
carapace drafts list --status pending --json
carapace drafts create --kind plan --position 12 --payload-file /tmp/plan.json \
  --base-version 3 --note "Claude 复核" --json
carapace drafts apply --id 5 --yes --json
carapace drafts discard --id 5 --json
```

`plan.json` 格式：

```json
{
  "levels": [
    {"kind": "buy", "price": 9.5, "quantity": 1000, "condition": "回到 20 日线"}
  ],
  "description": "复核后的计划",
  "nextReview": "2026-12-01"
}
```

## 观察

```bash
carapace watch list --json
carapace watch add --code 00700 --name 腾讯控股 --market hk --watch-price 380 --json
carapace watch add --code 000001 --name 上证指数 --market index --quote-key 1.000001 --json
carapace watch update --id 3 --watch-price 360 --note "等财报" --json
carapace watch remove --id 3 --yes --json
carapace watch convert --id 3 --quantity 100 --cost 370 --json
carapace watch carry --id 9 --watch-price 12 --note "清仓后观察" --json
```

## 交割单

```bash
carapace accounts list --json
carapace accounts add --broker 测试券商 --name 主账户 --currency CNY --default --json
carapace import preview --file /path/statement.csv --json
carapace import commit --file /path/statement.csv --broker 测试券商 --yes --json
carapace import commit --file /path/statement.csv --yes --include-needs-review --json
carapace import preview --file /path/statement.csv --mapping-file /tmp/mapping.json --json
carapace import rollback --batch 3 --yes --json
carapace import batches --json
carapace import executions --batch 3 --json
```

## 复盘与记忆

```bash
carapace reviews list --include-done --json
carapace reviews get --id 7 --json
carapace reviews create --position 12 --kind plan --due 2026-12-01 --json
carapace reviews save --id 7 --notes-file /tmp/notes.md --json
carapace reviews save --id 7 --notes "复盘结论" --complete --json

carapace memories list --scope global --json
carapace memories context --position 12 --json
carapace memories add --scope global --kind principle --title "不追高" \
  --content "只在计划档位买入" --confidence 0.8 --json
carapace memories update --id 4 --content "更新后的内容" --json
carapace memories archive --id 4 --json
```

## 指标

```bash
carapace metrics list --position 12 --json
carapace metrics set --position 12 --key pe --label "市盈率" --value 18.5 --json
```

## 风格

```bash
carapace style compute --json
carapace style snapshots --limit 20 --json
carapace style save --narrative-file /tmp/style.md --json
```

## 提醒与通知

```bash
carapace alerts list --json
carapace alerts list --resolved --json
carapace alerts ack --id "hit:12:abc" --json
carapace alerts ack-all --json

carapace notifications list --unread --json
carapace notifications read --id 3 --json
carapace notifications read-all --json
```

## 行情与搜索

```bash
carapace quotes get --code 600000 --json
carapace quotes get --code 00700 --market hk --json
carapace quotes get --code 00700 --market hk --quote-key 116.00700 --json
carapace quotes tracked --refresh --json
carapace quotes indices --json
carapace search --keyword 平安 --json
```

## 设置与维护

```bash
carapace settings list --json
carapace settings get --key hkdRate --json
carapace settings set --key hkdRate --value 0.86 --json
carapace settings set --key autoReview --value true --json
carapace settings set --key quietHours --value true --json
carapace settings set --key singlePositionLimit --value 0.2 --json

carapace backup --to /tmp/carapace-backup.sqlite3 --json
carapace verify --json
carapace export-csv --to /tmp/changes.csv --json
carapace maintenance purge-ai-keys --yes --json
```