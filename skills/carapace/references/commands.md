# Carapace CLI 命令

所有命令默认输出 JSON。示例里的 `carapace` 指 PATH 中的 CLI；找不到时先运行随 skill 分发的
`scripts/find-carapace.sh`，把输出作为可执行文件路径。示例标的均为合成数据。
写命令示例省略了部分 `--request-id` 和 `--dry-run`，实际按 `SKILL.md` 的硬规则补齐；
标有 `--yes` 的命令在 `--dry-run` 预览时也必须保留 `--yes`。

通用参数：

| 参数 | 说明 |
|---|---|
| `--json` | JSON 输出（默认） |
| `--format text` | 人类可读输出 |
| `--db PATH` | 覆盖数据库路径，默认 `~/Library/Application Support/Carapace/store.sqlite3`；测试时必须用临时库 |
| `--dry-run` | 只预览，不写入；`performWrite` 支持的命令会返回 `data.dry_run=true` |
| `--yes` | 确认破坏性操作 |
| `--request-id ID` | 写操作幂等键；预览与执行使用同一个 ID |
| `--no-notify` | 不通知运行中的 App 刷新 |

## 自检

```bash
carapace doctor --json
carapace schema --json
carapace version --json
```

`doctor` 的 `data` 里有 `healthy`、`checks`、`api_version`、`app_version`、`schema_version`、
`db`、`app_running`；成功响应的 `meta.as_of` 是数据时间。

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
carapace positions get --code 000000 --json
carapace positions add --code 000000 --name 示例股份 --quantity 100 --cost 10 \
  --request-id "$(uuidgen)" --dry-run --json
carapace positions add --code 000000 --name 示例股份 --quantity 100 --cost 10 \
  --plan-file /tmp/plan.json --description "首仓" --next-review 2026-12-01 --json
carapace positions correct --id 12 --quantity 200 --cost 10 --reason "补录" --json
carapace positions clear --id 12 --price 12 --fee 2 --yes --json
carapace positions changes --id 12 --limit 50 --json
```

`positions add` 还支持 `--market cn|hk|us|index`、`--source`、`--unit`、
`--opened-at`、`--quote-key`。`positions correct`、`changes` 支持 `--type` 过滤，
取值见「成交」。写操作应带 `--request-id`，并按 skill 规则先 `--dry-run`。
`positions clear` 的预览还必须带 `--yes`；`--dry-run` 保证预览不写入。

## 成交

```bash
carapace trades record --position 12 --side buy --quantity 100 --price 10 --fee 1 \
  --request-id "$(uuidgen)" --json
carapace trades record --position 12 --side sell --quantity 100 --price 12 \
  --level-id <计划档位 ID> --request-id "$(uuidgen)" --json
carapace trades list --position 12 --json
carapace trades list --type buy --limit 100 --json
```

还支持 `--occurred-at` 和 `--note`。`--type` 可取 `open|buy|sell|clear|adjust|plan|cost`。

## 计划

```bash
carapace plans get --position 12 --json
carapace plans update --position 12 --levels-file /tmp/levels.json \
  --if-version 3 --note "复核后调整" --json
```

`plans update` 还支持 `--description`、`--next-review`。修改已有计划必须带 `--if-version`；
不带会返回 VALIDATION。`plans get` 的顶层还会返回 `executedLevels`。

`levels.json` 可以是数组：

```json
[
  {"kind": "buy", "price": 9, "quantity": 100, "condition": "回到均线"},
  {"kind": "sell", "price": 15, "quantity": 50, "condition": "估值上沿"},
  {"kind": "stop", "price": 8, "quantity": null, "condition": "逻辑失效"}
]
```

也可以是 `{"levels": [...]}`。`kind` 只能是 `buy|sell|stop`；观察标的只允许 `buy` 档。

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
    {"kind": "buy", "price": 9, "quantity": 100, "condition": "回到均线"}
  ],
  "description": "复核后的计划",
  "nextReview": "2026-12-01"
}
```

`--base-version` 必须等于应用时的 `plans get --position 12 --json` 返回的 `data.version`，
否则应用会返回 CONFLICT。上面写命令示例按 skill 规则补 `--request-id`；
`drafts apply` 还要先加 `--dry-run` 预览，用户确认后去掉 `--dry-run`。

## 观察

```bash
carapace watch list --json
carapace watch add --code 000000 --name 示例股份 --market cn --watch-price 10 \
  --quote-key 000000 --json
carapace watch add --code 000000 --name 示例股份 --market index --quote-key 1.000001 --json
carapace watch update --id 3 --watch-price 10 --note "等财报" --json
carapace watch remove --id 3 --yes --json
carapace watch convert --id 3 --quantity 100 --cost 10 --json
carapace watch carry --id 9 --watch-price 12 --note "清仓后观察" --json
```

`watch add` 还接受 `--source`、`--unit`、`--plan-file`；`watch update` 还接受 `--name`；
`watch convert` 还接受 `--opened-at`。`cn` 和 `hk` 可建仓，`us` 和 `index` 只能观察。
先用 `search --keyword TEXT --json` 确认真实代码、市场、品种和 quoteKey。

## 交割单

```bash
carapace accounts list --json
carapace accounts add --broker 示例券商 --name 示例账户 --currency CNY --default --json
carapace import preview --file /path/statement.csv --json
carapace import commit --file /path/statement.csv --broker 示例券商 --yes --json
carapace import commit --file /path/statement.csv --yes --include-needs-review --json
carapace import preview --file /path/statement.csv --mapping-file /tmp/mapping.json --json
carapace import rollback --batch 3 --yes --json
carapace import batches --json
carapace import executions --batch 3 --json
```

`import preview/commit` 可用 `--account ID` 指定账户，否则使用默认账户；
`accounts add` 还支持 `--account-no`。`mapping.json` 是
`{"标准字段":"券商列名"}`；标准字段见 `ImportService.fields`，包括 `trade_time`、
`code`、`side`、`quantity`、`price`、`amount`、`fee_commission`、`broker_trade_id` 等。
预览最多返回前 50 行 `rows`；`needsReview` 是金额与数量×价格不一致的行，
只有用户明确确认后才用 `--include-needs-review` 提交。

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

`reviews save` 还支持 `--outcome-file`。`memories list` 可用 `--status` 和 `--limit`；
`memories context` 可用 `--code`。`memories add` 的 `--scope` 只接受
`global|instrument|position`，`--kind` 只接受
`principle|preference|pattern|lesson|fact|hypothesis`；`profile` 在模型里存在，
但 CLI 会拒绝写入。`memories add` 可用 `--scope-id`、`--evidence`；
`memories update` 可用 `--title`、`--confidence`。

## 指标

```bash
carapace metrics list --position 12 --json
carapace metrics set --position 12 --key pe --label "示例指标" --value 18 \
  --unit 倍 --json
```

`metrics set` 的 `--value` 是字符串，传 `--unit` 后会拼进显示值。

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
carapace quotes get --code 000000 --json
carapace quotes get --code 000000 --market cn --json
carapace quotes get --code 000000 --market cn --quote-key 1.000000 --json
carapace quotes tracked --refresh --json
carapace quotes indices --json
carapace search --keyword 示例 --json
```

`quotes get` 还支持 `--source eastmoney|sina|cmb|fund`。A 股默认按代码生成东方财富
secid，港股默认用 `116.<code>`，美股会探测 `105|106|107.<symbol>`；
需要覆盖时用 `--quote-key`。`search` 返回代码、市场、`instrumentMarket`、`source`、
`unit`、`quoteKey`、`canHold`、`currency`。

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

`settings set` 不走 `--dry-run`/`request-id` 幂等包装，但会直接写偏好并通知 App；
`backup`、`export-csv` 写文件；`verify` 会修正不一致的持仓状态。把它们当作写操作，
先取得用户确认。`maintenance purge-ai-keys` 是破坏性操作，必须同时有明确确认和 `--yes`。
