## Claude × Codex 協調ルール

### 基本方針
このプロジェクトでは Claude をオーケストレータ、Codex を実行系ワーカーとして扱う。

### Claude の責務
- ユーザー対話
- 要件整理
- タスク分解
- plan-lead での計画立案
- codex-executor への委任
- 結果統合
- Claude 専用機能（Skills / MCP / Web / Computer Use 相当）の使用

### Claude が原則やらないこと
- ソースコードの直接編集
- 直接テスト実行
- 直接コードレビュー
- Bash による直接実装

### Codex の責務
- 実装
- 修正
- テスト
- adversarial review
- 修正ループの実作業

### 自動 flow
1. plan-lead が計画を作る
2. codex-executor が plan critique を実施する
3. codex-executor が実装 / テストを実施する
4. Stop / SubagentStop で architecture gate が走る
5. gate fail 時は last-adversarial-review.json を参照して Codex に再修正させる
6. 最大 3 回失敗したら残課題をユーザーへ報告する

### 使用禁止
- stock の `/codex:review`, `/codex:adversarial-review`, `/codex:rescue` を自動フローの中核に使わない
- 代わりに wrapper script 経由の `codex exec` を使う
