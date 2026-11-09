#!/bin/bash
# 公开仓库隐私检查：工作树 + 全部 git 历史。
#
# 用法：
#   ./scripts/check-privacy.sh               # 工作树 + 历史（发版 / 公开前）
#   ./scripts/check-privacy.sh --no-history  # 只查工作树（日常提交前）
#
# 规则来源：CLAUDE.md「隐私与公开仓库」。任一命中即返回 1。
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

NO_HISTORY=0
[ "${1:-}" = "--no-history" ] && NO_HISTORY=1

FAIL=0
hit() { printf 'PRIVACY HIT: %s\n' "$*" >&2; FAIL=1; }

# 只允许这两个文件之外的内容参与扫描（脚本自身包含检测规则）。
EXCLUDES=(':(exclude)scripts/check-privacy.sh')

tree_scan() {
  local label="$1" pattern="$2" out
  out=$(git -c core.quotepath=false grep -nE "$pattern" -- . "${EXCLUDES[@]}" 2>/dev/null | head -20)
  [ -n "$out" ] && { hit "$label"; printf '%s\n' "$out" >&2; }
}

# ---- 工作树 ----

# 1. 令牌 / 私钥 / 凭证文件
tree_scan "令牌或私钥" '(ghp_|gho_|ghs_|github_pat_|sk-ant-|sk-proj-|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY)'
out=$(git -c core.quotepath=false ls-files | grep -E '(^|/)(\.env|.*\.(sqlite3|sqlite3-wal|sqlite3-shm|dmg|p12|pem|key|mobileprovision))$' || true)
[ -n "$out" ] && { hit "凭证或数据库/安装包被纳入版本库"; printf '%s\n' "$out" >&2; }

# 2. 真实用户目录（/Users/me 是文档占位，放行）
out=$(git -c core.quotepath=false grep -nE '/Users/[A-Za-z0-9._-]+' -- . "${EXCLUDES[@]}" 2>/dev/null | grep -v '/Users/me' | head -20 || true)
[ -n "$out" ] && { hit "真实用户目录"; printf '%s\n' "$out" >&2; }

# 3. 内网地址
tree_scan "内网地址" '(^|[^0-9])(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}([^0-9]|$)'

# 4. 券商 / 账户名
tree_scan "券商或账户名" '(华泰|中信|招商|国泰君安|海通|广发|银河|国信|东方财富)证券'

# 5. 大额金额（真实持仓汇总、交割单）
tree_scan "大额金额" '(总市值|总成本|总盈亏|净回款|买入金额|资金余额)[^0-9]{0,8}[0-9]{1,3}(,[0-9]{3}){2,}'

# 6. 公开仓库不收录内部设计与评审文档
out=$(git -c core.quotepath=false ls-files | grep -E '^(design/|docs/(方案\.md|观察标的方案\.md|评审报告))' || true)
[ -n "$out" ] && { hit "内部设计/评审文档"; printf '%s\n' "$out" >&2; }

# ---- 历史 ----

if [ "$NO_HISTORY" -eq 0 ]; then
  # 7. 作者 / 提交者邮箱必须是 GitHub noreply
  out=$(git -c core.quotepath=false log --all --format='%ae%n%ce' | sort -u | grep -vE '^[0-9]+\+[A-Za-z0-9._-]+@users\.noreply\.github\.com$' | grep -v '^$' || true)
  [ -n "$out" ] && { hit "非 noreply 的提交邮箱"; printf '%s\n' "$out" >&2; }

  # 8. 历史里仍存在的内部文档路径
  out=$(git -c core.quotepath=false log --all --format= --name-only | grep -E '^(design/|docs/(方案\.md|观察标的方案\.md|评审报告))' | sort -u || true)
  [ -n "$out" ] && { hit "历史中的内部文档"; printf '%s\n' "$out" >&2; }

  # 9. 历史内容里的令牌 / 用户目录 / 内网地址
  out=$(git -c core.quotepath=false log -p --all --format= -- . "${EXCLUDES[@]}" 2>/dev/null \
    | grep -nE '(ghp_|gho_|ghs_|github_pat_|sk-ant-|sk-proj-|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY|/Users/[A-Za-z0-9._-]+|(^|[^0-9])(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3})' \
    | grep -v '/Users/me' | head -20 || true)
  [ -n "$out" ] && { hit "历史中的敏感内容"; printf '%s\n' "$out" >&2; }
fi

if [ "$FAIL" -eq 0 ]; then
  echo "隐私检查通过"
else
  echo "隐私检查未通过：按 CLAUDE.md 的规则清理后重试" >&2
fi
exit "$FAIL"