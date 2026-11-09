---
name: carapace
description: 操作本机 Carapace 持仓应用。用于查询持仓、盈亏、行情、计划、复盘、记忆和草稿，添加或修改观察标的，记录买卖与清仓，导入交割单，以及生成计划草稿。触发词：持仓、仓位、盈亏、自选、观察、计划、复盘、记忆、交割单、导入、加仓、减仓、清仓、行情、组合。
---

# Carapace

## 启动检查

1. 运行 `carapace doctor --json`。
2. `data.healthy` 必须为 true，`meta.api_version` 必须等于 1；否则停止并向用户报告原因，不要猜测。
3. 找不到 `carapace` 时，按顺序尝试：
   - `$CARAPACE_BIN`
   - `/Applications/Carapace.app/Contents/Helpers/carapace`
   - `~/Applications/Carapace.app/Contents/Helpers/carapace`
   - `./build/Carapace.app/Contents/Helpers/carapace`
   - `./.build/debug/carapace-cli`

## 硬规则

- 只通过 CLI 读写；不要直接打开 SQLite，不读 Keychain，不读原始数据库文件。
- 所有命令加 `--json`；只引用返回值，不编造价格、数量、日期。
- 回答第一行给结论，并带上 `meta.as_of` 和数据来源。
- 写操作先加 `--dry-run`，用中文复述将发生的变更；用户确认后再执行。
- 清仓、删除观察、导入提交、回滚、修改计划必须等用户明确说“确认”。
- 写操作带 `--request-id "$(uuidgen)"`；失败不要自动重试，先运行 `carapace doctor --json` 并报告错误码。
- 草稿默认由用户在 App 的「草稿中心」确认；只有用户明确要求在 CLI 应用时，才执行 `drafts apply --id N --yes`。
- 不把持仓数据发送到任何外部服务，只在本地 CLI 和当前对话中使用。

## 常用流程

### 看组合

```bash
carapace portfolio --json
```

### 看单只

```bash
carapace positions get --code 600000 --json
```

### 加观察

```bash
carapace watch add --code 00700 --name 腾讯控股 --market hk --watch-price 380 --json
```

### 记一笔

先预览：

```bash
carapace trades record --position 12 --side buy --quantity 100 --price 10.2 --fee 1 \
  --request-id "$(uuidgen)" --dry-run --json
```

用户确认后去掉 `--dry-run`，带上同一个 `--request-id`。

### 复核计划

1. `carapace positions get --id 12 --json`
2. `carapace plans get --position 12 --json`
3. `carapace memories context --position 12 --json`
4. 结合持仓、计划与记忆，生成 levels JSON
5. 写入草稿：

```bash
carapace drafts create --kind plan --position 12 \
  --payload-file /tmp/plan.json --base-version 3 --json
```

6. 告诉用户：到 App 的「持仓 → 计划 → 草稿…」确认应用。

### 复盘

```bash
carapace reviews list --json
carapace reviews get --id 7 --json
carapace reviews save --id 7 --notes-file /tmp/notes.md --json
```

### 导入交割单

```bash
carapace import preview --file /path/to/statement.csv --json
carapace import commit --file /path/to/statement.csv --yes --json
```

## 参考

- `references/commands.md`：完整命令与参数
- `references/json-schemas.md`：返回结构与退出码
- `references/workflows.md`：组合、交易、计划、复盘、导入
- `references/troubleshooting.md`：找不到 CLI、数据库占用、版本不匹配