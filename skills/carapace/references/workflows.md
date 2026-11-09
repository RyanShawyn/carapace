# 常用工作流

所有流程先按 `SKILL.md` 找到 CLI 并通过 `doctor --json`；示例均为合成数据。
写操作使用 `--request-id "$(uuidgen)"`，先 `--dry-run`，用户确认后去掉 `--dry-run`
并保留同一个 ID。清仓、删除、导入、回滚、草稿应用还要按 CLI 要求带 `--yes`；
这些命令的预览也必须带 `--yes`，`--dry-run` 保证预览不写入。

## 看组合

1. `carapace doctor --json`
2. `carapace portfolio --json`
3. 用 `meta.as_of` 说明数据时间；行情缺失时明确说「未估值」，不要把成本当现价。

## 看单只

1. `carapace positions get --code 000000 --json`
2. 需要实时价时：`carapace quotes get --code 000000 --json`
3. 需要计划时：`carapace plans get --position <id> --json`

## 加观察

1. `carapace search --keyword 示例股份 --json` 确认返回的 `code`、`instrumentMarket`、
   `source`、`unit`、`quoteKey`、`canHold` 和 `currency`。
2. 预览写操作：

```bash
carapace watch add --code 000000 --name 示例股份 --market cn --watch-price 10 \
  --quote-key <search 返回的 quoteKey> \
  --request-id "$(uuidgen)" --dry-run --json
```

3. 用户确认后去掉 `--dry-run`，带同一个 `--request-id` 执行；返回里确认
   `kind == "watch"`、`currency` 与 `search` 一致。

## 买入 / 加仓

1. `carapace positions get --id 12 --json` 或 `--code`。
2. `carapace plans get --position 12 --json` 找到对应档位 ID。
3. dry-run：

```bash
carapace trades record --position 12 --side buy --quantity 100 --price 10 \
  --fee 1 --level-id <档位 ID> --request-id "$(uuidgen)" --dry-run --json
```

4. 向用户复述：买入数量、价格、费用、成交后数量/成本。
5. 用户确认后执行，带同一个 `--request-id`。

## 卖出 / 清仓

- 部分卖出用 `trades record --side sell`，同样先 `--dry-run`。
- 全部清仓用 `positions clear`；预览和正式执行都带 `--yes`，预览另加 `--dry-run`，
  用户明确说「确认」后才去掉 `--dry-run`。
- 清仓后想保留观察：`watch carry --id 12 --watch-price 12`；先 `--dry-run` 再执行。

## 计划复核

1. 读取：

```bash
carapace positions get --id 12 --json
carapace plans get --position 12 --json
carapace memories context --position 12 --json
```

2. 结合计划、持仓和记忆生成候选档位；观察标的只生成 `buy` 档。
3. 从 `plans get` 的 `data.version` 取当前版本，只生成草稿，不直接改计划：

```bash
carapace drafts create --kind plan --position 12 \
  --payload-file /tmp/plan.json --base-version <当前版本> \
  --request-id "$(uuidgen)" --dry-run --json
```

4. 用户确认后去掉 `--dry-run`，带同一个 `--request-id` 创建；告诉用户打开
   App → 持仓 → 计划 → 草稿… → 应用。
5. 如果用户坚持在 CLI 应用，先 `drafts apply --id N --yes --request-id "$(uuidgen)" --dry-run --json`
   预览，明确确认后去掉 `--dry-run`、保留 `--yes` 执行；否则不要执行。
   正式执行带同一个 `--request-id`。应用前重新读取计划版本，
   版本已变化就让用户重新确认草稿。

## 复盘

1. `carapace reviews list --include-done --json`
2. `carapace reviews get --id 7 --json` 读取 `facts` 和已有 `notes`。
3. 生成复盘草稿，写到临时文件。
4. `carapace reviews save --id 7 --notes-file /tmp/notes.md --request-id "$(uuidgen)" --dry-run --json`
5. 用户确认后去掉 `--dry-run` 执行；需要完成时加 `--complete`。

## 导入交割单

1. `carapace accounts list --json`，没有默认账户先走 `accounts add --default` 的
   `--dry-run` + 确认流程。
2. `carapace import preview --file statement.csv --json`。
3. 检查 `summary.duplicate`、`summary.needsReview`、`summary.errors`、`mapping` 和 `rows`；
   有 `needsReview` 时向用户说明金额差异，不擅自加 `--include-needs-review`。
4. `carapace import commit --file statement.csv --yes --request-id "$(uuidgen)" --dry-run --json`
   预览，再用中文复述将导入的账户、行数和跳过项。
5. 得到用户明确「确认」后，去掉 `--dry-run`，保留 `--yes` 和同一个
   `--request-id` 执行。
6. 需要撤销：先用 `carapace import rollback --batch <id> --yes --request-id "$(uuidgen)" --dry-run --json`
   预览并取得明确确认，再去掉 `--dry-run`、保留 `--yes` 和同一个 `--request-id` 执行。

## 周报 / 风格

1. `carapace portfolio --json`
2. `carapace style compute --json`
3. `carapace trades list --limit 200 --json`
4. 生成周报文本，直接在对话里回答；需要留档时：
   - `carapace memories add --scope global --kind pattern ...`
   - 或 `carapace style save --narrative-file /tmp/style.md --json`

留档是写操作，先 `--dry-run`，确认后再执行。

## 记录原则 / 教训

```bash
carapace memories add --scope global --kind principle --title "不追高" \
  --content "只在计划档位买入" --confidence 0.8 \
  --request-id "$(uuidgen)" --dry-run --json
```

用户确认后去掉 `--dry-run` 执行。引用 `memories context` 的 `data.text` 时使用里面的
`[M1]` 编号，不要把记忆当作事实结论。
