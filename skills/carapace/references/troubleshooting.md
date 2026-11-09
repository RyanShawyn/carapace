# 排错

## 找不到 carapace

按顺序检查：

```bash
echo "$CARAPACE_BIN"
command -v carapace
ls -l /Applications/Carapace.app/Contents/Helpers/carapace
ls -l ~/Applications/Carapace.app/Contents/Helpers/carapace
ls -l ./build/Carapace.app/Contents/Helpers/carapace
ls -l ./.build/debug/carapace-cli
```

安装 CLI 软链：

```bash
./scripts/install-skill.sh --personal --bin ~/.local/bin
```

或临时指定：

```bash
export CARAPACE_BIN=/Applications/Carapace.app/Contents/Helpers/carapace
```

## doctor 返回 healthy=false

看 `data.checks`：

- `database.ok=false`：数据库路径不存在或没有权限。确认 `~/Library/Application Support/Carapace/store.sqlite3` 存在，目录 0700、文件 0600。
- `schema.ok=false`：数据库版本不是 8。先启动新版 App 完成迁移；迁移前会自动生成 `store.sqlite3.7-backup`。
- `permissions.ok=false`：文件权限不对，执行 `chmod 600 <db>`。
- `ai_keys.ok=false`：还有旧 AI Key，执行 `carapace maintenance purge-ai-keys --yes`。

## 数据库被占用 / database is locked

- CLI 使用 WAL + 3 秒忙等；短时间重试一次。
- 不要同时运行多个写命令。
- 长时间失败时退出 App，确认没有其他 `carapace` 进程，再重试。

## 版本冲突 CONFLICT

计划版本已经变化：

1. `carapace plans get --position N --json` 重新读取 `version`。
2. 重新生成或调整 levels。
3. 用新的 `--if-version` 再提交。

## 写操作重复

所有写命令都应带 `--request-id`。重试时使用同一个 ID，CLI 会返回第一次的结果，不会重复记账。

## 行情 QUOTE 错误

- 检查网络和代理。
- 港股需要 `--market hk`，必要时显式给 `--quote-key 116.00700`。
- 场外基金用 `--source fund`。
- 非交易时间可能只有收盘价，回答时说明 `meta.as_of`。

## App 没有刷新

- CLI 写成功会自动发 Darwin 通知；App 打开时会在 1 秒内刷新。
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

不要在临时库里操作真实持仓；如果已经在真实库创建了测试数据，用 `positions clear` / `watch remove` 删除，或从迁移前备份恢复。