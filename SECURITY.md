# 安全说明

Carapace 是本机优先的个人工具：数据库在 `~/Library/Application Support/Carapace/`，目录 0700、文件 0600；只请求东方财富、新浪的公开行情接口和 GitHub 的更新接口；没有遥测、账号或云端同步。

## 更新信任模型

- 更新源是公开仓库 `RyanShawyn/carapace`。
- App 会校验 SHA-256、bundle 版本和 `codesign --verify`。
- 安装包是 **ad-hoc 签名**：`codesign --verify` 只能证明包内文件一致，**不能证明发布者身份**。如果 GitHub Release 或账号被控制，攻击者可以发布一个能通过校验的包。
- 在补齐 Developer ID 签名 + 公证之前，请以 Release 页面公布的 SHA-256 为信任锚；对来源有疑问时不要更新。

## 仓库与发布卫生

- 公开仓库只包含源码和对外文档。`design/`、内部方案与评审报告不进入公开历史；样例数据一律虚构，不使用真实持仓、成本、股数、总市值、券商、交割单或关注价。
- 提交邮箱统一使用 GitHub noreply；公开仓库不收录数据库、dmg、`.env` 和证书私钥。
- 发版前执行 `./scripts/check-privacy.sh` 与 README「隐私检查」的二进制 grep，任一命中即停止发布。

## 报告问题

请不要在公开 issue 中粘贴真实持仓、账户信息或数据库文件。报告安全问题时只提供复现步骤和最小化的合成数据。
