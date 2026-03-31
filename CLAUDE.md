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

---

## Absolute Constraints

以下は絶対に破ってはならない制約である。

### Implementation Boundaries
- **It is unacceptable** for Claude to directly edit source code files. All code changes must be delegated to Codex via wrapper scripts.
- **It is unacceptable** for Claude to run tests directly. Test execution is Codex's responsibility.
- **It is unacceptable** for Claude to perform code review directly. Review is delegated to Codex adversarial review.
- **It is unacceptable** to implement application source code via Bash. Shell commands against src/ and tests/ are for read-only investigation only.
- Orchestration scripts (hooks/scripts/session-start.sh, hooks/scripts/session-end.sh, hooks/scripts/init.sh) and configuration files (.claude/, CLAUDE.md, docs/) may be executed or edited by Claude directly.

### Testing & Completion
- **It is unacceptable** to declare a task DONE without running tests and verifying they pass.
- **It is unacceptable** to mark a feature as `passes: true` in feature-list.json without E2E test confirmation.
- **It is unacceptable** to report `tests_status: PASS` without actually executing the tests.
- **It is unacceptable** for self-evaluation to serve as the sole quality gate. Independent adversarial review is mandatory for non-trivial changes.

### Session Discipline
- **It is unacceptable** to work on more than one feature per session. Focus on the highest-priority incomplete item in feature-list.json.
- **It is unacceptable** to skip reading claude-progress.txt at session start.
- **It is unacceptable** to end a session without updating claude-progress.txt via session-end.sh.
- **It is unacceptable** for Codex to run git commit. Commits are made by the orchestrator after all gates PASS.

### Feature List Integrity
- **It is unacceptable** to remove or edit existing test assertions to make tests pass. Fix the implementation instead.
- **It is unacceptable** to delete features from feature-list.json. Features may only be marked as done.
- **It is unacceptable** to modify feature-list.json acceptance criteria after implementation begins, unless explicitly approved by the user.

---

### TDD Discipline
- **It is unacceptable** to implement new features without first writing failing tests (RED phase).
- **It is unacceptable** to report test_log without evidence of the RED-GREEN-REFACTOR cycle for new features.
- Bug fixes may use test-after pattern, but new features require TDD.

### Spec-First Development
- **It is unacceptable** to begin implementation without a spec file at `specs/<feature-id>.md`.
- Spec files define machine-verifiable acceptance criteria.
- plan-lead は計画時に spec の存在を確認し、不足があれば作成を指示する。

---

## Session Protocol

### Session Start
1. Run `hooks/scripts/session-start.sh` (or manually execute equivalent steps)
2. Read `claude-progress.txt` — understand what happened last session
3. Read `feature-list.json` — identify the highest-priority incomplete feature
4. Run init.sh to verify environment health
5. Select exactly ONE feature to work on

### Session End
1. Run `hooks/scripts/session-end.sh` with: completed work, next steps, blockers, feature_id
2. Verify claude-progress.txt was updated
3. Ensure all changes are committed with descriptive messages

---

## Codex の責務
- 実装
- 修正
- テスト実行
- adversarial review
- 修正ループの実作業
- 変更をファイルに書く（staging / commit は全 gate 通過後に orchestrator が実行）

### 自動 flow（7 Layer Development Stack）

`Spec-first -> Sprint contract -> TDD inner loop -> Boundary tests -> Eval gate -> Architecture gate -> Session handoff`

1. **Spec-first**: plan-lead が `specs/<feature-id>.md` を確認し計画を作る
2. **Sprint contract**: codex-executor が `codex-sprint-contract.sh` で done_criteria / test_plan / boundary_tests_required を合意する
3. **TDD inner loop**: codex-executor が RED -> GREEN -> REFACTOR サイクルで実装・テストを実施する（commit はしない）
4. **Boundary tests**: sprint contract で指定された boundary test を実行する
5. **Eval gate**: Stop / SubagentStop で `codex-eval-gate.sh` が走る（テスト証拠の機械検証。contract 充足検証は将来拡張予定）
6. **Architecture gate**: eval gate PASS 後、`codex-architecture-gate.sh` が走る（構造・設計リスクを検証）
7. **Session handoff**: 全 gate PASS 後に orchestrator が commit し、`session-end.sh` で次セッション向け artifact を残す
8. gate fail 時は `last-adversarial-review.json` / `last-eval-gate.json` を参照して Codex に再修正させる
9. 最大 3 回失敗したら残課題をユーザーへ報告する

### Evaluator Calibration
- adversarial review は独立した skeptical な視点で行う
- 生成者の自己評価は信頼しない（Self-Evaluation Unreliability Principle）
- 評価基準は具体的な失敗パターン例で校正する

### Harness Maintenance
- ハーネスの各コンポーネントは「モデルにできないこと」の仮定に基づいている
- モデル改善に伴い、定期的にコンポーネントの要否を見直すこと
- 不要になったガードレールは削除してシンプルさを維持する

### 使用禁止
- stock の `/codex:review`, `/codex:adversarial-review`, `/codex:rescue` を自動フローの中核に使わない
- 代わりに wrapper script 経由の `codex exec` を使う
