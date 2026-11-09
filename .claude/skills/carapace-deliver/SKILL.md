---
name: carapace-deliver
description: 为 Carapace（菜单栏持仓应用）做本机启动、调试运行或打包 macOS 安装包时使用。触发词：本机启动、本地跑、重新部署、打包、dmg、安装包、发版、build app。
---

# Carapace 本机启动与打包

## 本机启动（开发用，不安装）

```bash
./scripts/dev-run.sh
```

- 编译 debug 并前台运行，默认自动打开面板；Ctrl-C 退出。
- `./scripts/dev-run.sh --release` 用 release 构建。
- 其余参数原样透传，例如 `--seed-demo`、`--once`、`--selftest`。
- 脚本会先 `pkill` 旧的 `.build/.../carapace`，否则单实例锁会让新进程静默退出。
- 数据库默认在 `~/Library/Application Support/Carapace/store.sqlite3`；
  用 `CARAPACE_DB=/tmp/xxx.sqlite3` 可切到临时库，避免弄脏真实数据。
  同时设置 `CARAPACE_DEFAULTS_SUITE=com.ryan.carapace.test`，隔离偏好域。
- 空库启动不会写入任何示例数据。
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
- 发布到应用内更新源：`./scripts/publish-release.sh`。它按 `Info.plist` 版本构建，发到公开仓库 `RyanShawyn/carapace`，附带 dmg 与 `.sha256`；应用内更新只认这个仓库，普通发版也必须走它。
- 发版前只改 `Resources/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion`；README 三语版本号同步更新。

## 发版前隐私检查（必做）

公开仓库的历史不可撤回，发布前按顺序跑完，任一命中就停止：

```bash
./scripts/check-privacy.sh
for s in 示例持仓 seeded_samples; do
  if grep -aq "$s" build/Carapace.app/Contents/MacOS/carapace; then
    echo "PRIVACY HIT: $s"; exit 1
  fi
done
```

- `check-privacy.sh` 覆盖：令牌/私钥、真实用户目录、内网地址、券商账户名、大额金额、内部文档路径、非 noreply 提交邮箱，以及全量 git 历史。
- 样例数据必须虚构（`000000` / 「示例股份」/ 整数金额），不得复用真实持仓、成本、股数、总市值、券商、交割单或关注价。
- `design/`、`docs/方案.md`、`docs/观察标的方案.md`、`docs/评审报告-*` 只留在私有分支，不进公开仓库。
- commit 邮箱统一 GitHub noreply；发布前用 `git log --all --format='%ae%n%ce' | sort -u` 复核。
- 公开仓库不收录数据库、dmg、`.env`、证书私钥。

## 交付前验证

```bash
swift build
swift run carapace --selftest
swift run carapace-cli version --json
swift run carapace-cli doctor --json
./scripts/smoke-ui.sh
```

需要验证行情解析时，用临时库跑：

```bash
CARAPACE_DB=/tmp/carapace-check/store.sqlite3 swift run carapace --seed-demo
CARAPACE_DB=/tmp/carapace-check/store.sqlite3 swift run carapace --once
```

## 注意

- CLI 产物随 app 打包在 `Carapace.app/Contents/Helpers/carapace`，不要单独发 CLI 安装包。
- 行情源只有东方财富和新浪：两个都会轮询，东方财富为主，拉不到或失败时自动用新浪。
- 不要用 `open build/...app` 做日常调试，那是打包产物，容易跑到旧二进制。
- 发版前只需改 `Resources/Info.plist` 的 `CFBundleShortVersionString`；App 和 CLI 都从 Info.plist 读取版本。
