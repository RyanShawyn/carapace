# 排错

## 找不到 carapace

运行随 skill 分发的脚本，它会输出第一个可执行路径：

```bash
./scripts/find-carapace.sh
```

脚本依次检查 `$CARAPACE_BIN`、PATH、`/Applications/Carapace.app`、
`~/Applications/Carapace.app`、`./build/Carapace.app/Contents/Helpers/carapace`、
`./.build/debug/carapace-cli`。找不到时退出 1。

需要安装 CLI 软链：

```bash
./scripts/install-skill.sh --personal --bin ~/.local/bin
```

或临时指定：

```bash
export CARAPACE_BIN=/Applications/Carapace.app/Contents/Helpers/carapace
```

## doctor 返回 healthy=false

先看 `data.healthy` 和 `data.checks`；`meta` 里没有 `healthy`：

- `database.ok=false`：数据库文件路径不可访问。检查 `data.db` 指向的目录权限；
  `Store` 会自动创建目录和 v8 空库，但目录本身必须可写。
- `schema.ok=false`：数据库版本不是 8。`Store` 在迁移前会生成
  `<db>.<旧版本>-backup`；确认备份存在后再启动新版 App 完成迁移。
- `permissions.ok=false`：权限不是 0600，执行 `chmod 600 <data.db>`。
- `ai_keys.ok=false`：`healthy` 不受遗留 AI Key 影响，但应清理；执行
  `carapace maintenance purge-ai-keys --yes --json`，先取得用户明确确认。
- `app_running.ok=true`：这条检查是提示，不是失败；首次升级前退出 App。

成功响应的版本字段在 `data.api_version`、`data.app_version`、
`data.schema_version`，也在 `meta.api_version`、`meta.app_version`、
`meta.schema_version`；不要读 `meta.healthy`。

## 数据库被占用 / database is locked

- CLI 使用 WAL + 3 秒忙等；短时间重试一次。
- 不要同时运行多个写命令。
- 长时间失败时退出 App，确认没有其他 `carapace` 进程，再重试。

## 版本冲突 CONFLICT

计划或草稿的版本已经变化：

1. `carapace plans get --position N --json` 重新读取 `data.version`。
2. 重新生成或调整 levels。
3. 用新的 `--if-version` 提交计划；草稿用新的 `--base-version` 重新创建。
4. 不要直接用 `drafts apply` 强行覆盖，先让用户重新确认。

## 写操作重复

所有经过 `performWrite` 的写命令都应带 `--request-id`。重试时使用同一个 ID，
CLI 会返回第一次的结果，不会重复记账。预览与正式执行也用同一个 ID。
`settings set`、`backup`、`export-csv`、`verify` 不经过这个包装，不要假设它们幂等。

## 行情 QUOTE 错误

- 检查网络和代理。
- 用 `search --keyword TEXT --json` 确认 `instrumentMarket`、`source`、`unit` 和 `quoteKey`。
- 港股需要 `--market hk`；`quotes get` 默认用 `116.<code>`，必要时显式给 `--quote-key`。
- 美股会探测 `105|106|107.<symbol>`；指数、基金和黄金按各自来源使用对应的 key。
- 招行积存金（`cmb`）和场外基金（`fund`）不做跨源回退；基金净值盘中不变属正常。
- 非交易时间可能只有收盘价，回答时说明 `meta.as_of`。

## App 没有刷新

- 经 `performWrite` 的写命令成功后会发 Darwin 通知；`settings set` 也会通知 App。
- 如果没刷新，切到别的页面再回来，或重启 App。
- `--no-notify` 会关闭自动刷新。

## 自定义目录安装后 Claude 看不到 skill

Claude Code 只自动加载：

- `~/.claude/skills`
- 项目 `.claude/skills`

用 `--dir` 装到其它位置后，需要软链：

```bash
./scripts/install-skill.sh --dir /opt/carapace-skills --link ~/.claude/skills
```

## 权限被拒绝

Claude Code 第一次运行 `carapace` 会请求 Bash 权限。允许：

```json
{
  "permissions": {
    "allow": ["Bash(carapace:*)"]
  }
}
```

## 测试数据污染真实数据

测试时始终使用临时库和临时偏好域：

```bash
export CARAPACE_DB=/tmp/carapace-test/store.sqlite3
export CARAPACE_DEFAULTS_SUITE=com.ryan.carapace.test
```

测试结束后删除：

```bash
rm -rf /tmp/carapace-test
defaults delete com.ryan.carapace.test 2>/dev/null || true
```

不要把 `/tmp` 库的数据复制到真实库；清理测试数据前先确认 `data.db` 指向临时库。
