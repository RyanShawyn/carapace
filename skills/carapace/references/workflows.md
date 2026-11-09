# 常用工作流

## 看组合

1. `carapace doctor --json`
2. `carapace portfolio --json`
3. 用 `meta.as_of` 说明数据时间；行情缺失时明确说“未估值”，不要把成本当现价。

## 看单只

1. `carapace positions get --code 600000 --json`
2. 需要实时价时：`carapace quotes get --code 600000 --json`
3. 需要计划时：`carapace plans get --position <id> --json`

## 加观察

1. `carapace search --keyword 腾讯 --json` 确认代码、市场、quoteKey。
2. `carapace watch add --code 00700 --name 腾讯控股 --market hk --watch-price 380 --json`
3. 返回里确认 `kind == "watch"`、`currency == "HKD"`。

## 买入 / 加仓

1. `carapace positions get --id 12 --json` 或 `--code`。
2. `carapace plans get --position 12 --json` 找到对应档位 ID。
3. dry-run：

```bash
carapace trades record --position 12 --side buy --quantity 100 --price 10.2 \
  --fee 1 --level-id <档位 ID> --request-id "$(uuidgen)" --dry-run --json
```

4. 向用户复述：买入数量、价格、费用、成交后数量/成本。
5. 用户确认后执行，带同一个 `--request-id`。

## 卖出 / 清仓

- 部分卖出用 `trades record --side sell`。
- 全部清仓用 `positions clear --id 12 --price 12 --yes`。
- 清仓后想保留观察：`watch carry --id 12 --watch-price 12`。

## 计划复核

1. 读取：

```bash
carapace positions get --id 12 --json
carapace plans get --position 12 --json
carapace memories context --position 12 --json
```

2. 结合计划、持仓和记忆生成候选档位。
3. 只生成草稿，不直接改计划：

```bash
carapace drafts create --kind plan --position 12 \
  --payload-file /tmp/plan.json --base-version <当前版本> --json
```

4. 告诉用户：打开 App → 持仓 → 计划 → 草稿… → 应用。
5. 如果用户坚持在 CLI 应用，必须明确确认，然后 `drafts apply --id N --yes`；否则不要执行。

## 复盘

1. `carapace reviews list --include-done --json`
2. `carapace reviews get --id 7 --json` 读取 `facts` 和已有 `notes`。
3. 生成复盘草稿，写到临时文件。
4. `carapace reviews save --id 7 --notes-file /tmp/notes.md --json`
5. 需要完成时加 `--complete`。

## 导入交割单

1. `carapace accounts list --json`，没有账户先 `accounts add --default`。
2. `carapace import preview --file statement.csv --json`
3. 检查 `summary.duplicate`、`summary.errors`、`mapping`。
4. 用户确认后 `carapace import commit --file statement.csv --yes --json`。
5. 需要撤销：`carapace import rollback --batch <id> --yes --json`。

## 周报 / 风格

1. `carapace portfolio --json`
2. `carapace style compute --json`
3. `carapace trades list --limit 200 --json`
4. 生成周报文本，直接在对话里回答；需要留档时：
   - `carapace memories add --scope global --kind pattern ...`
   - 或 `carapace style save --narrative-file /tmp/style.md --json`

## 记录原则 / 教训

```bash
carapace memories add --scope global --kind principle --title "不追高" \
  --content "只在计划档位买入" --confidence 0.8 --json
```

引用历史记忆时使用返回的 `[M1]` 编号，不要把记忆当作事实结论。