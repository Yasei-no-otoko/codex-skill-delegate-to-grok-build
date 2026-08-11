# Delegate to Grok Build

English | [日本語](#japanese)

A Codex skill for delegating narrowly scoped software-development tasks to the [xAI Grok Build CLI](https://github.com/xai-org/grok-build) installed on the same PC.

Codex remains responsible for task scoping, safety controls, diff inspection, testing, and the final answer. Grok's output is treated as evidence rather than accepted automatically.

## Features

- `Review` mode for read-only investigation and code review
- `Edit` mode for narrowly scoped file changes
- Disables Grok memory, nested subagents, plan mode, and auto-update
- Explicitly denies shell commands, MCP tools, and unrequested web access
- Restricts access to credentials, private keys, `.env` files, and Git metadata
- Validates Grok's JSON response and `stopReason`
- Terminates the Grok process tree when a run times out
- Sends inline prompts through a short-lived file instead of exposing them in the process list

## Requirements

- Windows
- PowerShell 7 or later
- Codex
- Grok Build CLI 1.0.0 (verified version)
- An xAI account or API authentication that works with Grok Build

Check the environment:

```powershell
pwsh --version
grok --version
grok models
```

If `grok models` reports that you are not authenticated, sign in with one of the following commands:

```powershell
grok login
# For environments where a browser cannot be opened
grok login --device-auth
```

## Installation

Clone the repository into your personal Codex skills directory:

```powershell
$skillPath = Join-Path $env:USERPROFILE '.codex\skills\delegate-to-grok-build'
git clone https://github.com/Yasei-no-otoko/codex-skill-delegate-to-grok-build.git $skillPath
```

To update an existing installation:

```powershell
$skillPath = Join-Path $env:USERPROFILE '.codex\skills\delegate-to-grok-build'
git -C $skillPath pull --ff-only
```

The skill is available as `$delegate-to-grok-build` in subsequent Codex tasks.

## Use from Codex

### Read-only review

```text
Use $delegate-to-grok-build to have Grok review the authentication flow in this repository.
Require file and line references, and do not allow any edits.
```

Codex selects `Review` mode, which permits Grok to list, read, and search files only.

### Narrowly scoped edit

```text
Use $delegate-to-grok-build to have Grok fix only the null handling in src/parser.ts.
Preserve existing changes, then have Codex inspect the diff and run the tests.
```

Codex selects `Edit` mode. Grok may edit the target files, but it cannot run shell commands, commit, push, create tags, or modify external services. Codex performs testing and final verification.

### Independent second opinion

```text
Use $delegate-to-grok-build to obtain Grok's independent diagnosis of the current failure.
Do not disclose our current hypothesis; provide only the logs and relevant code as evidence.
```

For an independent review, avoid disclosing the expected conclusion or suspected location in advance.

## Run the wrapper directly

Normally, Codex invokes the skill for you. You can run the PowerShell wrapper directly for diagnostics or testing.

### Review mode

```powershell
$skillPath = Join-Path $env:USERPROFILE '.codex\skills\delegate-to-grok-build'

& "$skillPath\scripts\invoke-grok-build.ps1" `
  -WorkingDirectory 'C:\path\to\repo' `
  -Mode Review `
  -MaxTurns 10 `
  -TimeoutSeconds 300 `
  -Prompt 'Review the authentication flow for concrete defects and cite files and line numbers.'
```

### Edit mode

```powershell
$skillPath = Join-Path $env:USERPROFILE '.codex\skills\delegate-to-grok-build'

& "$skillPath\scripts\invoke-grok-build.ps1" `
  -WorkingDirectory 'C:\path\to\repo' `
  -Mode Edit `
  -Prompt 'Fix only the null handling in src/parser.ts and report changed files and unverified items.'
```

### Inspect arguments without running Grok

```powershell
& "$skillPath\scripts\invoke-grok-build.ps1" `
  -WorkingDirectory 'C:\path\to\repo' `
  -Mode Review `
  -Prompt 'Review this repository.' `
  -DryRun
```

`DryRun` does not contact Grok. It prints the generated CLI arguments as JSON without exposing the prompt text.

### Use a prompt file

```powershell
& "$skillPath\scripts\invoke-grok-build.ps1" `
  -WorkingDirectory 'C:\path\to\repo' `
  -Mode Review `
  -PromptFile 'C:\path\to\delegation-task.txt'
```

## Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `Prompt` | Required | A single task to send to Grok. Cannot be used with `PromptFile` |
| `PromptFile` | Required | An existing file containing the task. Cannot be used with `Prompt` |
| `WorkingDirectory` | Current directory | Directory Grok may inspect or edit |
| `Mode` | `Review` | `Review` or `Edit` |
| `Model` | Grok CLI default | Model ID to use |
| `ReasoningEffort` | Model default | `low`, `medium`, `high`, or `xhigh` |
| `MaxTurns` | `12` | Maximum Grok turns, from 1 to 100 |
| `TimeoutSeconds` | `300` | Runtime limit, from 5 to 3600 seconds |
| `DenyRule` | None | Additional Grok permission deny rules; may be specified more than once |
| `EnableWebSearch` | Disabled | Explicitly permits web search and web fetch |
| `GrokExecutable` | PATH or `%USERPROFILE%\.grok\bin\grok.exe` | Explicit Grok executable path |
| `DryRun` | Disabled | Displays CLI arguments without starting Grok |

Add repository-specific protected paths with an additional deny rule:

```powershell
-DenyRule 'Read(**/private/**)', 'Edit(**/private/**)'
```

## Safety boundaries

This skill does not run Grok in a completely isolated environment.

- On Windows, do not treat Grok's sandbox profile as the primary security boundary.
- Both `Review` and `Edit` deny shell and MCP tools.
- Web access is permitted only when `EnableWebSearch` is specified.
- The wrapper adds deny rules for `.grok`, `.ssh`, `.aws`, `.azure`, `.kube`, `.env`, private keys, and Git metadata.
- Never include API keys, passwords, or tokens in the task prompt.
- Codex must independently verify Grok's reports and edits.
- Do not delegate commits, pushes, releases, or production changes to Grok.

## Exit codes and failure handling

The wrapper reports success only when Grok returns valid JSON with an `end_turn` stop reason.

| Exit code | Meaning |
| --- | --- |
| `0` | Valid JSON with `stopReason` set to `end_turn` |
| `2` | Grok did not complete normally |
| `65` | Grok returned malformed JSON |
| `124` | Timeout; the Grok process tree was terminated |
| Other | Exit code returned by the Grok CLI |

## Troubleshooting

### Grok is not found

```powershell
Get-Command grok
Test-Path "$env:USERPROFILE\.grok\bin\grok.exe"
```

Use `-GrokExecutable` if Grok is installed in a nonstandard location.

### Authentication errors

```powershell
grok models
grok login
```

Do not store an API key in the prompt or repository.

### Runs time out

Reduce the task scope or increase `-TimeoutSeconds` only when necessary. Splitting work into investigation, one focused edit, and independent review is more reliable than delegating an entire repository-wide implementation at once.

### Grok cannot run shell commands

This is intentional. Grok reads and edits code; Codex runs builds, tests, and Git operations.

## Repository layout

```text
delegate-to-grok-build/
├── SKILL.md
├── README.md
├── agents/
│   └── openai.yaml
└── scripts/
    └── invoke-grok-build.ps1
```

## Validation

Validate the skill structure with the validator bundled with Codex:

```powershell
python "$env:USERPROFILE\.codex\skills\.system\skill-creator\scripts\quick_validate.py" `
  "$env:USERPROFILE\.codex\skills\delegate-to-grok-build"
```

---

<a id="japanese"></a>

# Delegate to Grok Build（日本語）

[English](#delegate-to-grok-build) | 日本語

Codexから、PCにインストール済みの[xAI Grok Build CLI](https://github.com/xai-org/grok-build)へ、範囲を限定したソフトウェア開発タスクを委譲するためのスキルです。

Grokの出力をそのまま採用するのではなく、Codexがタスクの切り出し、安全制御、差分確認、テスト、最終回答を担当します。

## 主な機能

- 読み取り専用の調査・レビューを委譲する`Review`モード
- 許可された範囲のファイル編集を委譲する`Edit`モード
- Grokのmemory、nested subagents、plan、auto-updateを無効化
- shell、MCP、未許可のWeb検索を明示的に拒否
- 認証情報、秘密鍵、`.env`、Gitメタデータなどの読み書きを制限
- GrokのJSON応答と`stopReason`を検証
- タイムアウト時にGrokのプロセスツリーを終了
- インラインプロンプトを短命ファイル経由で渡し、プロセス一覧への露出を回避

## 必要なもの

- Windows
- PowerShell 7以降
- Codex
- Grok Build CLI 1.0.0（動作確認済み）
- Grok Buildで利用できるxAIアカウントまたはAPI認証

確認コマンド:

```powershell
pwsh --version
grok --version
grok models
```

`grok models`で未認証と表示された場合は、次のいずれかでログインしてください。

```powershell
grok login
# ブラウザを開けない環境
grok login --device-auth
```

## インストール

Codexの個人スキルディレクトリへcloneします。

```powershell
$skillPath = Join-Path $env:USERPROFILE '.codex\skills\delegate-to-grok-build'
git clone https://github.com/Yasei-no-otoko/codex-skill-delegate-to-grok-build.git $skillPath
```

すでにインストール済みの場合:

```powershell
$skillPath = Join-Path $env:USERPROFILE '.codex\skills\delegate-to-grok-build'
git -C $skillPath pull --ff-only
```

次のCodexタスクから`$delegate-to-grok-build`として利用できます。

## Codexから使う

### 読み取り専用レビュー

```text
$delegate-to-grok-build を使って、このリポジトリの認証処理をGrokにレビューさせてください。
ファイルと行番号を根拠として示し、変更は行わないでください。
```

Codexは`Review`モードを選び、Grokにはファイル一覧、読み取り、検索だけを許可します。

### 範囲を限定した修正

```text
$delegate-to-grok-build を使って、src/parser.ts のnull処理だけをGrokに修正させてください。
既存の変更は保持し、Grokの変更後にCodex側で差分確認とテストを実行してください。
```

Codexは`Edit`モードを選びます。Grokは対象ファイルを編集できますが、shellコマンド、commit、push、tag、外部サービス操作は実行しません。テストと最終検証はCodex側で行います。

### 独立したセカンドオピニオン

```text
$delegate-to-grok-build を使って、現在の不具合原因についてGrokの独立見解を取得してください。
こちらの仮説は伝えず、ログとコードだけを根拠に調査させてください。
```

独立レビューでは、期待する結論や疑っている箇所を先に教えないほうが有効です。

## ラッパーを直接実行する

通常はCodexにスキルを呼び出させます。動作確認やデバッグではPowerShellラッパーを直接実行できます。

### Reviewモード

```powershell
$skillPath = Join-Path $env:USERPROFILE '.codex\skills\delegate-to-grok-build'

& "$skillPath\scripts\invoke-grok-build.ps1" `
  -WorkingDirectory 'C:\path\to\repo' `
  -Mode Review `
  -MaxTurns 10 `
  -TimeoutSeconds 300 `
  -Prompt '認証フローをレビューし、具体的な欠陥をファイル名と行番号付きで報告してください。'
```

### Editモード

```powershell
$skillPath = Join-Path $env:USERPROFILE '.codex\skills\delegate-to-grok-build'

& "$skillPath\scripts\invoke-grok-build.ps1" `
  -WorkingDirectory 'C:\path\to\repo' `
  -Mode Edit `
  -Prompt 'src/parser.tsのnull処理だけを修正し、変更ファイルと未検証事項を報告してください。'
```

### 実行せず引数を確認する

```powershell
& "$skillPath\scripts\invoke-grok-build.ps1" `
  -WorkingDirectory 'C:\path\to\repo' `
  -Mode Review `
  -Prompt 'レビューしてください。' `
  -DryRun
```

`DryRun`ではGrokへ接続せず、生成されるCLI引数をJSONで表示します。プロンプト本文は表示されません。

### プロンプトファイルを使う

```powershell
& "$skillPath\scripts\invoke-grok-build.ps1" `
  -WorkingDirectory 'C:\path\to\repo' `
  -Mode Review `
  -PromptFile 'C:\path\to\delegation-task.txt'
```

## パラメーター

| パラメーター | 既定値 | 説明 |
| --- | --- | --- |
| `Prompt` | 必須 | Grokへ渡す単一タスク。`PromptFile`とは同時指定不可 |
| `PromptFile` | 必須 | タスクを書いた既存ファイル。`Prompt`とは同時指定不可 |
| `WorkingDirectory` | 現在のディレクトリ | Grokが調査・編集する対象ディレクトリ |
| `Mode` | `Review` | `Review`または`Edit` |
| `Model` | Grok CLIの既定モデル | 使用するモデルID |
| `ReasoningEffort` | モデルの既定値 | `low`、`medium`、`high`、`xhigh` |
| `MaxTurns` | `12` | Grokの最大ターン数。1～100 |
| `TimeoutSeconds` | `300` | 実行時間の上限。5～3600秒 |
| `DenyRule` | なし | 追加するGrok permission deny rule。複数指定可 |
| `EnableWebSearch` | 無効 | Web検索とWeb取得を明示的に許可 |
| `GrokExecutable` | PATHまたは`%USERPROFILE%\.grok\bin\grok.exe` | Grok実行ファイルを明示指定 |
| `DryRun` | 無効 | Grokを起動せずCLI引数を確認 |

プロジェクト固有の機密パスを追加で拒否する例:

```powershell
-DenyRule 'Read(**/private/**)', 'Edit(**/private/**)'
```

## 安全上の制限

このスキルはGrokを完全に隔離された環境で実行するものではありません。

- WindowsではGrokのsandbox profileを主要なセキュリティ境界として扱いません。
- `Review`と`Edit`のどちらでもshellとMCPを拒否します。
- Web検索は`EnableWebSearch`指定時だけ許可します。
- `.grok`、`.ssh`、`.aws`、`.azure`、`.kube`、`.env`、秘密鍵、Gitメタデータなどにdeny ruleを追加します。
- プロンプトへAPIキー、パスワード、トークンなどを含めないでください。
- Grokの報告や編集は必ずCodex側で再確認してください。
- commit、push、release、production変更などはGrokへ委譲しないでください。

## 終了コードと失敗判定

ラッパーはGrokのJSON応答が正常に完了した場合だけ成功として扱います。

| 終了コード | 意味 |
| --- | --- |
| `0` | JSONが有効で`stopReason`が`end_turn` |
| `2` | Grokが通常完了しなかった |
| `65` | GrokのJSON出力が不正 |
| `124` | タイムアウト。Grokのプロセスツリーを終了 |
| その他 | Grok CLIが返した終了コード |

## トラブルシューティング

### Grokが見つからない

```powershell
Get-Command grok
Test-Path "$env:USERPROFILE\.grok\bin\grok.exe"
```

標準以外の場所へインストールした場合は`-GrokExecutable`を指定してください。

### 認証エラー

```powershell
grok models
grok login
```

APIキーをプロンプトやリポジトリへ書き込まないでください。

### タイムアウトする

タスク範囲を小さくするか、必要な場合だけ`-TimeoutSeconds`を増やしてください。最初からリポジトリ全体の実装を委譲するより、調査、単一修正、独立レビューに分割するほうが安定します。

### Grokがshellコマンドを実行できない

仕様です。Grokはコードの読み取りと編集を担当し、build、test、Git操作はCodex側で実行します。

## 構成

```text
delegate-to-grok-build/
├── SKILL.md
├── README.md
├── agents/
│   └── openai.yaml
└── scripts/
    └── invoke-grok-build.ps1
```

## 検証

スキル構造はCodex付属のvalidatorで確認できます。

```powershell
python "$env:USERPROFILE\.codex\skills\.system\skill-creator\scripts\quick_validate.py" `
  "$env:USERPROFILE\.codex\skills\delegate-to-grok-build"
```
