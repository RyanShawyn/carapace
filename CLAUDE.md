# Carapace 项目约定

- SwiftPM / macOS 13+；三个 target：`CarapaceCore`（无 UI）、`Carapace`（AppKit + SwiftUI）、`CarapaceCLI`。
- 测试和调试必须使用临时库与临时偏好域，避免碰真实持仓：
  `export CARAPACE_DB=/tmp/carapace-test/store.sqlite3`
  `export CARAPACE_DEFAULTS_SUITE=com.ryan.carapace.test`
- 构建与验收：`swift build`、`swift run CarapaceCoreTests`、`swift run carapace --selftest`、`./scripts/test-cli.sh`、`./scripts/test-skill-contract.sh`、`./scripts/smoke-ui.sh`；改 skill 文档示例或 CLI 返回结构时须跑后三个脚本。
- 数据库 schema v8；所有写入只经 `Store`（WAL + `BEGIN IMMEDIATE`），不要手写 SQL 改真实库。
- 空库不写入示例数据；不要把个人持仓、成本、账户名写进源码、文档或测试夹具。
- 发版：只改 `Resources/Info.plist` 的 `CFBundleShortVersionString` / `CFBundleVersion`，然后 `./scripts/package-dmg.sh`、`./scripts/publish-release.sh`；App 与 CLI 都从 Info.plist 读版本。
- 更新源固定为公开仓库 `RyanShawyn/carapace`（源码与 Releases 同仓）；安装包是 ad-hoc 签名，只有 SHA-256 校验完整性。

## 隐私与公开仓库

GitHub 仓库 `carapace` 是公开仓库，历史一旦推送就永久可见。提交和发版前按「所有内容都会公开」检查。

- 样例数据必须明显虚构：代码用 `000000`、名称用「示例股份」、金额/数量用整数占位；不得复用真实持仓、成本、股数、总市值、券商、交割单、关注价或投资逻辑。
- 公开仓库只放源码与对外文档。`design/`、`docs/方案.md`、`docs/观察标的方案.md`、`docs/评审报告-*` 属于内部资料，不进公开历史；需要保留就放 GitLab 私有分支 `archive/pre-public-*`。
- commit 作者和提交者邮箱必须是 GitHub noreply（`<id>+<username>@users.noreply.github.com`），禁止真实个人邮箱；改写历史后用 `git log --all --format='%ae%n%ce' | sort -u` 复核。
- 发版前必须依次执行：`./scripts/check-privacy.sh`（工作树 + 全量历史）、README「隐私检查」的二进制 grep；任一命中立即停止发布。
- 公开仓库不收录数据库、dmg、`.env`、证书私钥；`dist/`、`build/`、`*.sqlite3` 保持忽略。
- 在公开 issue / 文档里只使用合成数据，不粘贴真实账户、交割单或数据库文件。
- 不要用 `open build/...app` 做日常调试；用 `./scripts/dev-run.sh`。
