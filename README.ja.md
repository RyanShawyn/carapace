# Carapace

[中文](README.md) · [English](README.en.md) · [日本語](README.ja.md)

メニューバーにいる一匹の亀。甲羅はポジション、甲羅に引っ込むのがリスク管理、遅さはデュレーション。

macOS 向けのローカルファーストな保有判断・振り返りアプリです。メニューバーパネルでは相場とウォッチリストを素早く確認し、メインウィンドウでは建玉、プラン、約定、レビュー、記憶、通知を扱います。アプリ本体はモデルを呼び出しません。AI が必要な場合は、Claude Code がインストール可能な skill と `carapace` CLI を通じて操作します。公開相場のみを取得し、証券会社への接続、発注、証券情報の保存は行いません。

現在のバージョン：**0.1.0** · macOS 13 以上 · Apple Silicon / Intel

空のデータベースにはサンプルデータを書き込みません。

## インストール

[最新リリース](https://github.com/RyanShawyn/carapace/releases/latest) から dmg をダウンロードし、`Carapace.app` を Applications にドラッグします。

アドホック署名のため、初回起動時は右クリック → 開く、または次を実行してください：

```bash
xattr -dr com.apple.quarantine /Applications/Carapace.app
```

## 機能

- **メニューバーパネル**：保有とウォッチの 2 セクション。上海総合 / 深証成指 / 創業板 / 科創50 の指数バー（設定で非表示可）。価格到達、ウォッチ価格、レビュー期限の通知。
- **メインウィンドウ**：概要 / 保有（保有・ウォッチ・プラン・履歴）/ レビュー（レビュー・記憶・スタイル）/ 設定。
- **銘柄検索**：コード、銘柄名、ピンインで検索し、選択するとコード・名称・市場が自動入力されます。
- **ウォッチリスト**：買いたいが未保有の銘柄を別管理。ウォッチ価格と買い水準を設定し、到達時に通知。売却時にウォッチとして残すことも、買い約定や取り込みで自動的に保有へ変換することもできます。
- **対応市場**：A株、ETF/LOF、店頭ファンド、金 / 招行積立金、香港株、米国株、指数。
- **香港株の保有**：港股通（ストックコネクト）銘柄は HKD 建てで価格を表示し、ポートフォリオの評価額・損益・比率は HKD/CNY レートで人民元に換算します。レートは `133.HKDCNH` から自動取得し、設定で手動変更もできます。
- **プランと通知**：買い / 売り / 停止の水準、水準の実行とプランバージョン。ウォッチ中のプランは買い水準のみ許可。
- **外部エージェント**：モデルは内蔵しません。Claude Code が `carapace` CLI 経由で保有、プラン、レビュー、記憶、下書きを読み書きします。ルールは `skills/carapace` にあります。
- **レビューと記憶**：結果の要因分解、プラン実行率、スタイル指標。全体 / 銘柄 / ポジションの 3 層記憶。
- **約定明細の取り込み**：CSV（UTF-8/GBK）。自動マッピング、プレビュー、重複排除、バッチ単位のロールバック。
- **ショートカット**：`⌘N` 新規保有、`⇧⌘N` ウォッチ追加、`⌘R` 相場更新、`⌘,` 設定、`⌘1–4` 画面切替、`⌘W` ウィンドウを閉じる、`⌘Q` 終了。

## 市場とデータソース

| 市場 | 相場 | 保有 | 備考 |
|---|---|---|---|
| A株 / ETF / LOF | 東方財富（新浪フォールバック） | 可 | CNY |
| 店頭ファンド | 新浪の基準価額 | 可 | 取引日の約 20:00 に更新 |
| 金 / 招行積立金 | 新浪 / 上海金の換算 | 可 | CNY |
| 香港株 | 東方財富 `116.*` | 可 | 港股通。HKD 建て、合計は CNY 換算 |
| 米国株 | 東方財富 `105/106/107.*` | ウォッチのみ | USD |
| 指数 | 東方財富 `1.* / 0.*` | ウォッチのみ | パネルの指数バー |

検索は新浪 suggest を使用。相場の取得は取引時間中または手動更新時のみです。

## データ

```text
~/Library/Application Support/Carapace/store.sqlite3
```

ディレクトリは 0700、ファイルは 0600。データベースは現在 **v8** で、v7 からアップグレードすると `store.sqlite3.7-backup` を自動作成し、旧 AI テーブルを削除します。アプリの再インストールはアプリ本体だけを置き換え、このディレクトリには触れません。

アップグレード前にアプリを終了してください。古いプロセスが削除済みテーブルへ書き込むのを防ぎます。

## アップグレード

既定では起動時と 24 時間ごとに更新を確認し、新バージョンがあればバナーを表示するだけです。自動インストールは「設定 → 更新」で有効にできます。メニューバーの右クリックやアプリメニューから手動確認もできます。

更新で置き換わるのは現在のフォルダ内の `Carapace.app`（通常は `/Applications`）だけで、データベース・設定・通知には触れません。SHA-256 とバージョンの検証に失敗した場合は旧バージョンを保持します。ad-hoc 署名は完全性のみを検証し、発行者を証明しません。Release の SHA-256 を信頼の基準にしてください。

ターミナルからも実行できます：

```bash
./scripts/upgrade.sh          # 最新 Release を取得・検証・置換して再起動
./scripts/upgrade.sh --check  # インストール済みと最新のバージョン比較のみ
```

スクリプトには `gh` が必要です。アプリ内更新には不要です。

## Skills と CLI

アプリ本体はモデルを呼び出しません。外部エージェントは 1 つの CLI を使います：

```
Claude Code
  ├── skills/carapace/SKILL.md を読む
  └── carapace CLI を実行
        ├── SQLite を読む
        ├── SQLite に書く（WAL + トランザクション）
        └── 実行中のアプリに再読み込みを通知
```

### skill のインストール

個人用：

```bash
./scripts/install-skill.sh --personal
```

プロジェクト用：

```bash
./scripts/install-skill.sh --project
```

任意のディレクトリ：

```bash
./scripts/install-skill.sh --dir /opt/carapace-skills
```

Claude Code が自動読み込みするのは `~/.claude/skills` とプロジェクトの `.claude/skills` だけです。任意ディレクトリに置く場合はシンボリックリンクを追加します：

```bash
./scripts/install-skill.sh --dir /opt/carapace-skills --link ~/.claude/skills
```

CLI を PATH に追加：

```bash
./scripts/install-skill.sh --personal --bin ~/.local/bin
```

dmg には App 本体のみが含まれ、skill は同梱されません。skill を使う場合はリポジトリをクローンし、上記のスクリプトを実行してください。

### Claude Code での使い方

例：

- 「保有と損益を見せて」
- 「テンセントをウォッチに追加、ウォッチ価格 380」
- 「600000 のプランをレビューして」
- 「この約定 CSV を取り込んで」

skill は最初に `carapace doctor --json` を実行します。書き込みは `--dry-run` で確認し、削除・決済・取り込み確定は明示的な承認を求めます。

任意の権限設定：

```json
{
  "permissions": {
    "allow": ["Bash(carapace:*)"]
  }
}
```

### CLI を直接使う

```bash
carapace doctor --json
carapace portfolio --json
carapace positions get --code 600000 --json
carapace trades record --position 12 --side buy --quantity 100 --price 10.2 \
  --request-id "$(uuidgen)" --dry-run --json
```

CLI は `Carapace.app/Contents/Helpers/carapace` に同梱されます。全コマンドは `skills/carapace/references/commands.md` を参照してください。

### 下書きの確認

Claude はプランの下書きだけを作成します：

```bash
carapace drafts create --kind plan --position 12 \
  --payload-file /tmp/plan.json --base-version 3 --json
```

アプリの「保有 → プラン → 下書き…」で適用します。

### テストデータ

テストは必ず分離します：

```bash
export CARAPACE_DB=/tmp/carapace-test/store.sqlite3
export CARAPACE_DEFAULTS_SUITE=com.ryan.carapace.test
```

終了後に削除：

```bash
rm -rf /tmp/carapace-test
defaults delete com.ryan.carapace.test 2>/dev/null || true
```

## ローカル実行

```bash
swift run carapace
swift run carapace-cli doctor --json
```

一時データベースで実行：

```bash
CARAPACE_DB=/tmp/carapace-dev/store.sqlite3 swift run carapace
```

## テストとパッケージ

```bash
swift run CarapaceCoreTests
.build/debug/carapace --selftest
./scripts/package-dmg.sh
```

`dist/Carapace-<バージョン>.dmg`（ユニバーサルバイナリ）を生成します。アドホック署名のため、初回起動時は右クリック → 開く、または：

```bash
xattr -dr com.apple.quarantine /Applications/Carapace.app
```

Apple Developer ID 署名と公証は行っていません。更新は公開リポジトリ + ad-hoc 署名で、信頼の基準は Release の SHA-256 です。

## 既知の制限

- 香港株・米国株・指数は約定明細の取り込みに未対応です。香港株の建玉は手入力またはウォッチからの変換で登録します。
- 米国株と指数は現在ウォッチのみです。
- 約定明細の取り込みは CSV のみ対応です。Excel は CSV で保存してください。
- 価格の履歴チャートは未実装です。サンプル用テーブルは用意済みです。
- AI は内蔵していません。必要な場合は外部エージェントが CLI 経由で操作します。

## 免責

個人の記録用です。投資助言ではありません。相場は公開インターフェースから取得しており、リアルタイム性や正確性を保証しません。