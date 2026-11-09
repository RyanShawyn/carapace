# Carapace

[中文](README.md) · [English](README.en.md) · [日本語](README.ja.md)

菜单栏里的一只乌龟。壳是仓位，缩回壳里是风控，慢是久期。

本机优先的持仓决策与复盘应用。菜单栏快速查看行情与观察标的，主应用负责建仓、计划、成交、复盘、记忆和通知。App 不内置任何模型调用；需要 AI 能力时，由 Claude Code 通过 `carapace` CLI 操作，规则写在可安装的 skill 里。只读公开行情，不接券商、不下单、不存券商凭证。

当前版本：**0.1.0** · 最低 macOS 13 · Apple Silicon / Intel

空库首次启动不会写入任何示例数据。

## 安装

从 [最新 Release](https://github.com/RyanShawyn/carapace/releases/latest) 下载 dmg，打开后把 `Carapace.app` 拖进 Applications。

ad-hoc 签名，首次打开需右键 → 打开，或执行：

```bash
xattr -dr com.apple.quarantine /Applications/Carapace.app
```

## 功能

- **菜单栏面板**：持仓与观察两段；上证 / 深证 / 创业板 / 科创50 指数条（可在设置关闭）；价格穿越、关注价、复盘到期提醒。
- **主窗口**：总览 / 持仓（持仓·观察·计划·流水）/ 复盘（复盘·记忆·风格）/ 设置。
- **标的搜索**：输入代码、名称或拼音，选择后自动填代码、名称和市场。
- **观察标的**：想买但还没买的标的单独管理；设关注价和买入档，跌破时提醒；清仓时可保留观察；买入或导入同代码成交后自动转为持仓。
- **市场覆盖**：A股、ETF/LOF、场外基金、黄金 / 招行积存金、港股、美股、指数。
- **港股建仓**：港股通标的按 HKD 记价，组合市值、盈亏和仓位按港币汇率折算成 CNY；汇率自动取 `133.HKDCNH`，可在设置里手改。
- **计划与提醒**：买入/卖出/停止买入档，档位执行与计划版本；观察阶段只允许买入档。
- **外部 Agent**：不内置模型。Claude Code 通过 `carapace` CLI 读写持仓、计划、复盘、记忆和草稿；规则与流程见 `skills/carapace`。
- **复盘与记忆**：结果归因、计划执行率、风格指标；全局/标的/持仓三层记忆。
- **通知**：价格/观察/复盘/仓位/草稿提醒进入铃铛抽屉；支持系统通知、按类别开关与 22:30–07:30 免打扰。
- **交割单导入**：CSV（UTF-8/GBK），自动/手动字段映射、预览、去重、批次回滚。
- **快捷键**：`⌘N` 新建持仓、`⇧⌘N` 添加观察、`⌘R` 刷新行情、`⌘,` 设置、`⌘1–4` 切换总览/持仓/复盘/设置、`⌘W` 关闭窗口、`⌘Q` 退出。

## 市场与数据源

| 市场 | 行情 | 建仓 | 说明 |
|---|---|---|---|
| A股 / ETF / LOF | 东方财富（新浪兜底） | 支持 | CNY |
| 场外基金 | 新浪净值 | 支持 | 交易日约 20:00 更新 |
| 黄金 / 招行积存金 | 新浪 / 沪金折算 | 支持 | CNY |
| 港股 | 东方财富 `116.*` | 支持 | 港股通；HKD 计价，合计折算 CNY |
| 美股 | 东方财富 `105/106/107.*` | 暂不支持 | 仅观察，USD |
| 指数 | 东方财富 `1.* / 0.*` | 暂不支持 | 仅观察，面板指数条 |

搜索用新浪 suggest。行情只在交易时段、打开面板或手动刷新时请求。

## 数据

```text
~/Library/Application Support/Carapace/store.sqlite3
```

目录 0700，文件 0600。数据库当前为 **v8**；从 v7 升级时会自动生成 `store.sqlite3.7-backup`，并删除旧的 AI 会话表。安装包只替换 app，不会改动这个目录。

升级前请先退出 App，避免旧进程在迁移后继续写已删除的表。

## 升级

默认自动检查：启动时和每 24 小时检查一次，发现新版本只显示横幅，由你确认。可在「设置 → 更新」里开启自动安装，或在菜单栏右键、App 菜单里手动检查。

更新只替换当前 App 所在目录中的 `Carapace.app`（通常是 `/Applications`），数据库、设置和通知都不动。安装包必须通过 SHA-256 和版本校验，失败会保留旧版本。ad-hoc 签名只校验包完整性，不证明发布者身份，请以 Release 里的 SHA-256 为准。

命令行也可以：

```bash
./scripts/upgrade.sh          # 下载最新 Release、校验、替换并重启
./scripts/upgrade.sh --check  # 只比较本机与最新版本
```

脚本需要 `gh`；应用内更新不需要。

## Skills 与 CLI

App 本体不再调用任何模型。AI 相关的工作交给外部 Agent：

```
Claude Code
  ├── 读取 skills/carapace/SKILL.md
  └── 执行 carapace CLI
        ├── 读 SQLite
        ├── 写 SQLite（WAL + 事务）
        └── 通知运行中的 App 刷新
```

### 安装 skill

从仓库安装到个人级（推荐给日常使用）：

```bash
./scripts/install-skill.sh --personal
```

安装到当前项目：

```bash
./scripts/install-skill.sh --project
```

安装到任意目录：

```bash
./scripts/install-skill.sh --dir /opt/carapace-skills
```

Claude Code 只自动加载 `~/.claude/skills` 和项目 `.claude/skills`。装到其它目录时，再加一个软链：

```bash
./scripts/install-skill.sh --dir /opt/carapace-skills --link ~/.claude/skills
```

同时把 CLI 软链到 PATH：

```bash
./scripts/install-skill.sh --personal --bin ~/.local/bin
```

安装包（dmg）里只有 App 本体，不含 skill。需要用 skill 时请克隆仓库，再运行上面的脚本。

覆盖已有安装：

```bash
./scripts/install-skill.sh --personal --force
```

### 在 Claude Code 里使用

装好后直接说：

- “看看我的持仓和盈亏”
- “把腾讯加自选，关注价 380”
- “帮我复核 600000 的计划”
- “把这个交割单 CSV 导入”
- “整理这条复盘”

Skill 会先运行 `carapace doctor --json`，再按流程调用 CLI。所有写操作先 `--dry-run` 展示变更，清仓、删除、导入提交等需要你明确确认。

可选：允许 Claude Code 直接运行 CLI，免去每次授权：

```json
{
  "permissions": {
    "allow": ["Bash(carapace:*)"]
  }
}
```

### 手动使用 CLI

```bash
carapace doctor --json
carapace portfolio --json
carapace positions get --code 600000 --json
carapace trades record --position 12 --side buy --quantity 100 --price 10.2 \
  --request-id "$(uuidgen)" --dry-run --json
```

CLI 随 App 打包在 `Carapace.app/Contents/Helpers/carapace`。完整命令见 `skills/carapace/references/commands.md`。

### 草稿确认

Claude 生成计划时只写草稿，不直接改计划：

```bash
carapace drafts create --kind plan --position 12 \
  --payload-file /tmp/plan.json --base-version 3 --json
```

然后到 App 的「持仓 → 计划 → 草稿…」确认应用。草稿应用后才写入计划流水。

### 测试数据

测试时始终使用临时库和临时偏好域，避免污染真实持仓：

```bash
export CARAPACE_DB=/tmp/carapace-test/store.sqlite3
export CARAPACE_DEFAULTS_SUITE=com.ryan.carapace.test
```

测试结束删除：

```bash
rm -rf /tmp/carapace-test
defaults delete com.ryan.carapace.test 2>/dev/null || true
```

如果已经在真实库里创建了测试数据，用 `positions clear --yes` 或 `watch remove --yes` 删除；也可以从 `store.sqlite3.7-backup` 恢复。

## 本机运行

```bash
swift run carapace
swift run carapace-cli doctor --json
```

用临时库运行：

```bash
CARAPACE_DB=/tmp/carapace-dev/store.sqlite3 swift run carapace
```

## 测试与打包

```bash
swift run CarapaceCoreTests
.build/debug/carapace --selftest
./scripts/package-dmg.sh
```

公开发布前做一次隐私检查（仓库内容、全量历史与二进制）：

```bash
./scripts/check-privacy.sh
for s in 示例持仓 seeded_samples; do
  if grep -aq "$s" build/Carapace.app/Contents/MacOS/carapace; then
    echo "PRIVACY HIT: $s"; exit 1
  fi
done
```

规则：样例数据必须明显虚构（`000000` / 「示例股份」/ 整数金额）；不得使用真实持仓、成本、股数、总市值、券商、交割单或关注价。`design/` 和内部方案/评审文档不进入公开仓库；提交邮箱统一 GitHub noreply。详见 [CLAUDE.md](CLAUDE.md)。

生成 `dist/Carapace-<版本>.dmg`，通用二进制。安装包为 ad-hoc 签名，首次打开需右键 → 打开，或：

```bash
xattr -dr com.apple.quarantine /Applications/Carapace.app
```

未做 Apple Developer ID 签名和公证；自动更新使用公开仓库 + ad-hoc 签名，信任锚是 Release 的 SHA-256。

## 已知限制

- 港股、美股和指数目前不参与导入交割单；港股建仓按手工录入或观察转持仓。
- 美股和指数只支持观察，暂不支持建仓。
- 交割单只支持 CSV；Excel 需先另存为 CSV。
- 行情历史图表尚未实现；采样表已保留。
- 不内置 AI；需要 AI 时由外部 Agent 通过 CLI 完成。

## 免责

仅用于个人记录，不构成投资建议。行情来自公开接口，不保证实时性和准确性。安全与更新信任模型见 [SECURITY.md](SECURITY.md)。