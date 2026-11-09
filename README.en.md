# Carapace

[中文](README.md) · [English](README.en.md) · [日本語](README.ja.md)

A turtle in your menu bar. The shell is the position, retreating into it is risk control, and slow is duration.

A local-first portfolio decision and review app for macOS. The menu bar panel is for quick quotes and watchlist checks; the main window handles positions, plans, executions, reviews, memory and notifications. The app has no built-in model calls; when AI is needed, Claude Code drives it through the `carapace` CLI with an installable skill. Public quotes only: no broker connection, no order placement, no broker credentials stored.

Current version: **0.1.0** · macOS 13+ · Apple Silicon / Intel

A new empty database starts with no sample data.

## Install

Download the dmg from the [latest release](https://github.com/RyanShawyn/carapace/releases/latest), open it, and drag `Carapace.app` into Applications.

The app is ad-hoc signed; on first launch, right-click → Open, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Carapace.app
```

## Features

- **Menu bar panel**: holdings and watchlist sections; SSE / SZSE / ChiNext / STAR 50 index strip (can be hidden in Settings); alerts for price crossovers, watch prices and overdue reviews.
- **Main window**: Overview / Positions (holdings · watchlist · plans · ledger) / Reviews (reviews · memory · style) / Settings.
- **Symbol search**: type a code, name or pinyin and pick a result; code, name and market are filled automatically.
- **Watchlist**: track things you intend to buy but do not own. Set a watch price and buy levels, get alerts when they are reached, keep a watch item after clearing a position, and convert it to a holding automatically when a matching buy is recorded or imported.
- **Markets**: A-shares, ETFs/LOFs, OTC funds, gold / CMB accumulated gold, Hong Kong stocks, US stocks and indices.
- **Hong Kong holdings**: Stock Connect names are priced in HKD; portfolio value, P&L and weights are converted to CNY at the HKD/CNY rate. The rate is fetched from `133.HKDCNH` and can be overridden in Settings.
- **Plans and alerts**: buy / sell / stop levels, level execution and plan versions. Watchlist plans only allow buy levels.
- **External agents**: no bundled model. Claude Code reads, writes and drafts through the `carapace` CLI; the rules live in `skills/carapace`.
- **Reviews and memory**: outcome attribution, plan execution rate, style metrics; global / instrument / position memory layers.
- **Trade import**: CSV (UTF-8/GBK) with mapping, preview, deduplication and batch rollback.
- **Shortcuts**: `⌘N` new position, `⇧⌘N` add watch, `⌘R` refresh quotes, `⌘,` settings, `⌘1–4` switch sections, `⌘W` close window, `⌘Q` quit.

## Markets and data sources

| Market | Quotes | Holdings | Notes |
|---|---|---|---|
| A-shares / ETFs / LOFs | Eastmoney (Sina fallback) | Yes | CNY |
| OTC funds | Sina NAV | Yes | Updated once per trading day, around 20:00 |
| Gold / CMB accumulated gold | Sina / Shanghai gold conversion | Yes | CNY |
| Hong Kong stocks | Eastmoney `116.*` | Yes | Stock Connect; priced in HKD, totals converted to CNY |
| US stocks | Eastmoney `105/106/107.*` | Watch only | USD |
| Indices | Eastmoney `1.* / 0.*` | Watch only | Panel index strip |

Search uses Sina suggest. Quotes are requested during trading hours, when the panel opens, or on manual refresh.

## Data

```text
~/Library/Application Support/Carapace/store.sqlite3
```

Directory mode 0700, file mode 0600. The database is currently **v8**; upgrading from v7 creates `store.sqlite3.7-backup` and removes the old AI tables. Installing a new app build only replaces the app bundle and never touches this directory.

Quit the app before upgrading so an old process cannot write to tables removed by the migration.

## Upgrading

The app checks for updates at launch and every 24 hours by default, and only shows a banner. Automatic install can be enabled in Settings → Update. You can also check manually from the menu bar context menu or the app menu.

Updating replaces only the `Carapace.app` in its current folder (usually `/Applications`); the database, settings, and notifications are untouched. The package must pass SHA-256 and version checks, otherwise the old version is kept. The ad-hoc signature only verifies integrity, not the publisher; trust the SHA-256 in the release.

From a terminal:

```bash
./scripts/upgrade.sh          # download the latest release, verify, replace, relaunch
./scripts/upgrade.sh --check  # compare the installed and latest versions only
```

The script needs `gh`; the in-app updater does not.

## Skills and CLI

The app no longer calls any model. External agents work through one CLI:

```
Claude Code
  ├── reads skills/carapace/SKILL.md
  └── runs carapace CLI
        ├── reads SQLite
        ├── writes SQLite (WAL + transactions)
        └── notifies the running app to reload
```

### Install the skill

Personal install:

```bash
./scripts/install-skill.sh --personal
```

Project install:

```bash
./scripts/install-skill.sh --project
```

Any directory:

```bash
./scripts/install-skill.sh --dir /opt/carapace-skills
```

Claude Code only auto-loads `~/.claude/skills` and the project `.claude/skills`. For a custom directory, add a symlink:

```bash
./scripts/install-skill.sh --dir /opt/carapace-skills --link ~/.claude/skills
```

Also put the CLI on PATH:

```bash
./scripts/install-skill.sh --personal --bin ~/.local/bin
```

The dmg contains only the app; the skill is not bundled. To use the skill, clone the repository and run the scripts above.

### Use it in Claude Code

Try:

- "Show my positions and P&L"
- "Add Tencent to the watchlist at 380"
- "Review the plan for 600000"
- "Import this trade CSV"

The skill runs `carapace doctor --json` first. Writes use `--dry-run` and ask for confirmation; clearing, deleting, and import commits require explicit approval.

Optional permission:

```json
{
  "permissions": {
    "allow": ["Bash(carapace:*)"]
  }
}
```

### CLI directly

```bash
carapace doctor --json
carapace portfolio --json
carapace positions get --code 600000 --json
carapace trades record --position 12 --side buy --quantity 100 --price 10.2 \
  --request-id "$(uuidgen)" --dry-run --json
```

The CLI ships inside `Carapace.app/Contents/Helpers/carapace`. See `skills/carapace/references/commands.md` for the full command list.

### Draft confirmation

Claude only writes plan drafts:

```bash
carapace drafts create --kind plan --position 12 \
  --payload-file /tmp/plan.json --base-version 3 --json
```

Apply the draft in the app under Positions → Plan → Drafts.

### Test data

Always isolate tests:

```bash
export CARAPACE_DB=/tmp/carapace-test/store.sqlite3
export CARAPACE_DEFAULTS_SUITE=com.ryan.carapace.test
```

Clean up afterwards:

```bash
rm -rf /tmp/carapace-test
defaults delete com.ryan.carapace.test 2>/dev/null || true
```

## Run locally

```bash
swift run carapace
swift run carapace-cli doctor --json
```

With a throwaway database:

```bash
CARAPACE_DB=/tmp/carapace-dev/store.sqlite3 swift run carapace
```

## Tests and packaging

```bash
swift run CarapaceCoreTests
.build/debug/carapace --selftest
./scripts/package-dmg.sh
```

The script produces `dist/Carapace-<version>.dmg` as a universal binary. The app is ad-hoc signed; on first launch, right-click → Open, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Carapace.app
```

It is not signed with an Apple Developer ID and is not notarized. Updates use a public release repo with an ad-hoc signature; the SHA-256 in the release is the trust anchor.

## Known limitations

- Hong Kong, US and index instruments are not supported by trade import yet; HK positions are entered manually or converted from a watch item.
- US stocks and indices are watch-only at the moment.
- Trade import supports CSV only; save Excel files as CSV first.
- No historical price charts yet; the quote sample table is reserved for this.
- No built-in AI; use an external agent through the CLI.

## Disclaimer

For personal record-keeping only. Not investment advice. Quotes come from public endpoints and are not guaranteed to be real-time or accurate.