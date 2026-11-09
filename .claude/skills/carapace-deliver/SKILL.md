---
name: carapace-deliver
description: 编译、本机调试运行、验收和发布 Carapace macOS 应用：swift build、dev-run、CLI/UI 测试、构建 .app、打包 dmg、隐私检查、更新版本号、发布 GitHub Release。用户提到本机启动、本地跑、重新部署、打包、dmg、安装包、发版或 build app 时使用；查询或修改个人持仓、计划、复盘、交割单使用面向用户的 carapace skill，而不是本 skill。
---

# Carapace 本机启动与打包

## 本机启动（开发用，不安装）

```bash
./scripts/dev-run.sh
```

- 编译 debug 并前台运行，默认自动打开面板；Ctrl-C 退出。
- `./scripts/dev-run.sh --release` 用 release 构建。
- 其余参数原样透传；当前 App 支持 `--selftest`、`--search KEYWORD`、`--once`。
- 脚本会先 `pkill` 旧的 `.build/.../carapace`，否则单实例锁会让新进程静默退出。
- 数据库默认在 `~/Library/Application Support/Carapace/store.sqlite3`；
  调试和测试必须用临时库与临时偏好域，避免碰真实持仓：

```bash
export CARAPACE_DB=/tmp/carapace-test/store.sqlite3
export CARAPACE_DEFAULTS_SUITE=com.ryan.carapace.test
```

- `CARAPACE_LOCK` 可指定独立单实例锁，供 UI 冒烟脚本使用。
- 空库启动不会写入任何示例数据；源码和公开文档里的样例只用
  `000000` / 「示例股份」/ 整数金额。
- 调试开关：`CARAPACE_SHOW_PANEL=1` 启动即开面板，`CARAPACE_PIN_PANEL=1` 让面板不自动关闭。

## 打包安装包

```bash
./scripts/package-dmg.sh
```

- 先调 `scripts/build-app.sh` 构建 `build/Carapace.app`，再生成
  `dist/Carapace-<版本>.dmg`（含 Applications 快捷方式），并打印 SHA-256。
- 版本号取自 `Resources/Info.plist` 的 `CFBundleShortVersionString`。
- 只有 ad-hoc 签名；首次打开需右键 → 打开，或
  `xattr -dr com.apple.quarantine <dmg>`。
- 只想构建 .app：`./scripts/build-app.sh`。
- 发布到应用内更新源：`./scripts/publish-release.sh`。它按 `Info.plist` 版本构建，
  发到公开仓库 `RyanShawyn/carapace`，附带 dmg 与 `.sha256`；
  应用内更新只认这个仓库，普通发版也必须走它。
- 发布前把 `Resources/Info.plist` 的 `CFBundleShortVersionString` 和
  `CFBundleVersion` 一起更新；README 三语版本号同步更新。

## 发版前隐私检查（必做）

公开仓库的历史不可撤回，发布前按顺序跑完，任一命中就停止：

```bash
./scripts/check-privacy.sh
./scripts/package-dmg.sh >/dev/null
for s in 示例持仓 seeded_samples; do
  if grep -aq "$s" build/Carapace.app/Contents/MacOS/carapace; then
    echo "PRIVACY HIT: $s"; exit 1
  fi
done
```

- `check-privacy.sh` 覆盖：令牌/私钥、真实用户目录、内网地址、券商账户名、大额金额、
  内部文档路径、非 noreply 提交邮箱，以及全量 git 历史。
- 二进制检查针对 App 主程序 `build/Carapace.app/Contents/MacOS/carapace`；
  `publish-release.sh` 会跑 `check-privacy.sh`，但不会自动跑这段二进制 grep。
- 样例数据必须虚构（`000000` / 「示例股份」/ 整数金额），不得复用真实持仓、成本、
  股数、总市值、券商、交割单或关注价。
- `design/`、`docs/方案.md`、`docs/观察标的方案.md`、`docs/评审报告-*` 只留在私有分支，
  不进公开仓库。
- commit 邮箱统一 GitHub noreply；发布前用
  `git log --all --format='%ae%n%ce' | sort -u` 复核。
- 公开仓库不收录数据库、dmg、`.env`、证书私钥。

## 交付前验证

全部命令使用临时库和临时偏好域；不要对真实库跑 `--once` 或 UI 启动。

```bash
swift build
swift run CarapaceCoreTests
swift run carapace --selftest
./scripts/test-cli.sh
./scripts/test-skill-contract.sh
./scripts/smoke-ui.sh
```

构建打包产物后，再检查打包进去的 CLI：

```bash
swift run carapace-cli version --json
swift run carapace-cli doctor --json --db /tmp/carapace-test/store.sqlite3
```

`swift run carapace-cli --help` 可核对分组和通用参数；CLI 命令契约在
`./scripts/test-cli.sh`，skill 文档里的 envelope、dry-run、幂等和草稿版本契约在
`./scripts/test-skill-contract.sh`。改 skill 的示例或 CLI 返回结构时两个测试都要跑。
不要使用不存在的 `--seed-demo` 参数；空库本来就不写示例数据。

## 注意

- CLI 产物随 app 打包在 `Carapace.app/Contents/Helpers/carapace`，不要单独发 CLI 安装包。
- 行情源有东方财富、新浪、招行积存金（`cmb`）和场外基金（`fund`）；
  东方财富和新浪可互为回退，后两类不做跨源回退。
- 不要用 `open build/...app` 做日常调试，那是打包产物，容易跑到旧二进制。
- App 与 CLI 都从 Info.plist 读取 `CFBundleShortVersionString`；
  `CFBundleVersion` 是构建号，`CarapaceBuild.apiVersion` 是独立的 CLI 契约版本。
