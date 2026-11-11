---
name: carapace
description: 通过 carapace CLI 操作本机 Carapace 持仓应用：查询持仓、盈亏、行情、计划、复盘、记忆、通知与草稿，添加或修改观察标的，记录买卖与清仓，导入交割单，以及生成计划草稿。用户提到持仓、仓位、盈亏、自选、观察、计划、复盘、记忆、交割单、导入、加仓、减仓、清仓、行情或组合时使用；Carapace 项目本身的编译、调试运行、打包和发版不使用本 skill。
---

# Carapace

## 启动检查

1. 先找 CLI：优先使用 PATH 里的 `carapace`；找不到时运行随本 skill 分发的 `scripts/find-carapace.sh`。
   脚本依次检查 `$CARAPACE_BIN`、PATH、两个 `/Applications` 位置、`./build/Carapace.app/Contents/Helpers/carapace` 和
   `./.build/debug/carapace-cli`，输出第一个可执行路径。检查失败时报告原因，不要猜测。
2. 用找到的路径运行 `doctor --json`。响应中 `ok` 必须为 true、`data.healthy` 必须为 true、
   `data.api_version` 必须等于 1、`data.schema_version` 必须等于 8；否则停止并报告 `data.checks` 中的失败项。
   成功响应的 `meta` 另外带 `api_version`、`app_version`、`as_of`、`db`、`schema_version`。
3. `--json` 是默认输出格式；命令一律显式加 `--json`，并保留 `--format text` 给人类阅读用。

## 硬规则

- 只通过 CLI 读写；不要直接打开 SQLite，不读 Keychain，不读原始数据库文件。
- 结论只引用 JSON 返回值，不编造价格、数量、日期；回答第一行给结论，并带上 `meta.as_of` 和数据来源。
- 写操作先加 `--dry-run`，再用中文复述将发生的变更；用户确认后才执行。
- 清仓、删除观察、移除计划、导入提交、回滚、修改计划、应用草稿必须等用户明确说「确认」。
- CLI 自身还要求破坏性操作带 `--yes`：`positions clear`、`watch remove`、`plans remove`、`import commit`、
  `import rollback`、`drafts apply`、`maintenance purge-ai-keys`。这些命令即使 `--dry-run`
  预览也必须带 `--yes`；`--dry-run` 保证不写入。用户确认针对的是去掉 `--dry-run` 的正式执行，
  不要把预览命令里的 `--yes` 当作用户已确认。
- 写操作带 `--request-id "$(uuidgen)"`；预览和正式执行使用同一个 ID。失败不要自动重试，
  先用同一个 `request-id` 排查幂等结果、运行 `doctor --json` 并报告错误码。
- 草稿默认由用户在 App 的「草稿中心」确认；只有用户明确要求在 CLI 应用时，才执行 `drafts apply --id N --yes`。
  草稿的 `--base-version` 必须取当前计划版本，否则应用时返回 CONFLICT。
- 不把持仓数据发送到任何外部服务，只在本地 CLI 和当前对话中使用。
- 示例只用合成代码 `000000`、名称「示例股份」和整数占位值；不要照抄示例里的真实标的或价格。
  用 `search --keyword TEXT --json` 得到真实代码、市场、品种和 `quoteKey` 后再操作用户数据。

## 常用流程

### 看组合

```bash
carapace doctor --json
carapace portfolio --json
```

### 看单只

```bash
carapace positions get --code 000000 --json
```

### 加观察

```bash
carapace search --keyword 示例股份 --json
carapace watch add --code 000000 --name 示例股份 --market cn --watch-price 10 --json \
  --dry-run --request-id "$(uuidgen)"
```

用户确认后去掉 `--dry-run`，保留同一个 `--request-id`。

### 记一笔

先预览：

```bash
carapace trades record --position 12 --side buy --quantity 100 --price 10 --fee 1 \
  --request-id "$(uuidgen)" --dry-run --json
```

用户确认后去掉 `--dry-run`，带上同一个 `--request-id`。

### 复核计划

1. `carapace positions get --id 12 --json`
2. `carapace plans get --position 12 --json`
3. `carapace memories context --position 12 --json`
4. 结合持仓、计划与记忆，生成 levels JSON
5. 从 `data.version` 取当前版本，写入草稿：

```bash
carapace drafts create --kind plan --position 12 \
  --payload-file /tmp/plan.json --base-version 3 \
  --request-id "$(uuidgen)" --dry-run --json
```

用户确认后去掉 `--dry-run`，带同一个 `--request-id` 执行；告诉用户到 App 的
「持仓 → 计划 → 草稿…」确认应用。

### 复盘

```bash
carapace reviews list --json
carapace reviews get --id 7 --json
carapace reviews save --id 7 --notes-file /tmp/notes.md \
  --request-id "$(uuidgen)" --dry-run --json
```

用户确认后去掉 `--dry-run`，带同一个 `--request-id` 执行。

### 导入交割单

1. `accounts list --json` 确认默认账户；没有则先 `accounts add --default` 的 dry-run 和确认流程。
2. `import preview --file statement.csv --json` 检查 `summary`、`mapping` 和 `rows`。
3. `import commit --file statement.csv --yes --request-id "$(uuidgen)" --dry-run --json` 预览。
4. 用中文复述将导入的行数、跳过项和账户；得到用户明确「确认」后，
   去掉 `--dry-run`，保留 `--yes` 和同一个 `--request-id` 执行。

## 参考

- `references/commands.md`：完整命令与参数
- `references/json-schemas.md`：返回结构与退出码
- `references/workflows.md`：组合、交易、计划、复盘、导入
- `references/troubleshooting.md`：找不到 CLI、数据库占用、版本不匹配
