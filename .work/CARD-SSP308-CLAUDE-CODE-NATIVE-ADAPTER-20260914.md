---
id: SSP308-CLAUDE-CODE-NATIVE-ADAPTER-20260914
status: NO_GO_REPAIRED_01_AWAITING_TARGETED_REREVIEW
type: implementation
jira: SSP-308（AIWR-10 Claude Code Native Adapter／Runtime Probe）
lane: B
tier: T1
sibling_of: SSP-307（AIWR-09 Codex Native Adapter，ACCEPTED_GO @ 32b3f82）
---

# AIWR-10 Claude Code Native Adapter（SSP-308）

👉 [假設與目標確認]
- 目標：把 Claude Code 公開文件記載的 hook 事件名稱，分類成「對應既有
  Hook 契約的一個 lifecycle_events 項目」或「明確的非生命週期事件」。
- 邊界：**本輪範圍縮減**（Owner 2026-09-14 選定）——不做即時 runtime probe，
  完整性對照公開文件的封閉 hook 事件集合驗證，不對照真實 session 語料。
  不做 connector、不做 hook 實際註冊、不取得 AIWR `complete`／Personal
  Memory acceptance／canonical writer authority。
- 驗收：見 Acceptance。

## Root question

Claude Code 自己公開文件記載的 hook 事件，與既有 AIWR seam 要的事件語彙
對不上；這個落差要怎麼變成可證偽的契約，同時不需要真的觸發一次 hook？

## 範圍縮減的理由（不是偷工）

SSP-307（Codex 手足卡）之所以需要全量掃描真實 session，是因為 Codex 原生
事件集合沒有公開規格，只能實測發現。Claude Code 的 9 個 hook 事件名稱
（`SessionStart`／`SessionEnd`／`UserPromptSubmit`／`PreToolUse`／
`PostToolUse`／`Notification`／`Stop`／`SubagentStop`／`PreCompact`）
是**公開文件裡的封閉集合**，完整性可以直接對文件驗證。這是不同的驗證方式，
不是比較弱的方式——因為要分類的是事件「名稱」，那是文件化且穩定的。

Owner 透過 `AskUserQuestion` 明確選定：先寫靜態分類契約，真實 payload
形狀（例如 `SessionEnd.reason` 的實際值分布）留給後續 runtime probe 卡
（`.work/CARD-SSP308-RUNTIME-PROBE-BACKLOG-20260914.md`）。

## 設計決策（承接 SSP-307 三個 finding 的教訓，一開始就避開）

- `SessionStart → start`：乾淨對應，語意上就是 session 開始。
- `Stop → submit_review`（**不是** `complete`）：SSP307-F-01 已證明
  `OPEN → DONE` 不是合法邊。`Stop`（agent 完成回應）是證據，不是 AIWR
  治理層的完成裁定，所以映射到 `OPEN → IN_REVIEW` 合法的 `submit_review`。
- `SessionEnd` **刻意留在 non-lifecycle**，不映射到 `cancel`：SSP307-F-02
  已證明把可能可恢復的事件映射到終態會永久關死 Work Record。`SessionEnd`
  有多種觸發原因（clear／logout／exit／other），可恢復性不明，靜態契約
  無法區分，所以不猜。
- `block`／`unblock` 在 Claude Code 原生完全沒有對應，刻意留空。
- `error_contract` 從一開始就用 SSP-302／SSP-307 已建立的共用 AST 模組
  （`scripts/lib/loop_return_contract.rb`）綁定，不手寫清單。

## Traces to

- `文件/待辦重整.md` §十「AIWR 平台落地 Lane」
- `規格/v0.1/codex-native-adapter.yaml`（手足卡，ACCEPTED_GO @ 32b3f82）
- Requirement ID：`AIWR10-S01`

## Dependencies / Blockers / Current frontier

- Dependencies：`SSP-301`（Hook）已完成；`SSP-307`（手足卡）已 ACCEPTED_GO。
- Blockers：無。
- Current frontier：`AIWR10-S01`。

## Scope

- 新 `規格/v0.1/claude-code-native-adapter.yaml`：分類契約，與
  `codex-native-adapter.yaml` 同一套治理形狀。
- 新 `scripts/validate_claude_code_native_adapter_contract.rb`：兩個純函式
  evaluator（mapping run、rollback），error_contract 綁定沿用共用 AST 模組。
- 新正負例 fixtures。
- 新 `.work/CARD-SSP308-RUNTIME-PROBE-BACKLOG-20260914.md`：後續 runtime
  probe 的延後卡。

## Constraints

- 不新增 connector／hook 實際註冊／registry／FSM／DB。
- 不取得 acceptance／permission／canonical writer 權威。
- 不重定義 `ai-task-card-record.yaml` 或 `ai-work-record-hook.yaml`。
- validator `< 400` 行。
- 不做 runtime probe（本輪範圍縮減，Owner 已選定）。

## Product fit

- Measured gap：Claude Code 原生 hook 事件與既有 Hook 契約要的
  lifecycle_events 語彙對不上，且過去沒有機制驗證過。
- Why not less：沒有這張契約，Claude Code 原生事件無法安全餵進既有 AIWR
  seam。
- Why not more：不做 hook 實際註冊、不取得任何超出「lifecycle evidence」
  的權威——`SSP-309`（跨平台一致性）才會真正接上 runtime。
- Do not absorb：Claude Code 本身、任何 hook 實作 SDK。
- Rollback：新 yaml + validator + fixtures，不連任何 runtime，可單獨 revert。

## Acceptance

1. `lifecycle_event_map` 與 `non_lifecycle_event_types` 合起來剛好等於
   `documented_native_vocabulary.hook_events`；兩者不重疊。
2. 兩個 evaluator（mapping／rollback）皆為純函式，guard-level enforcement
   parity 全紅。
3. `error_contract` 與兩個 evaluator 實際可回傳集合機器綁定，沿用共用
   AST 模組。
4. 每個 lifecycle_event_map 條目、每個 non_lifecycle_event_types 條目
   至少一個正例。
5. 全部既有 validator + schema engine + cross-layer + `git diff --check`
   全 PASS。

## Stop conditions

- 若需要實際觸發 hook 才能完成驗收，停，回 Owner——那是延後卡的範疇。
- 若上游 `lifecycle_event_to_status` 需要新增 key，停，回 Owner。

## Likely files

- `規格/v0.1/claude-code-native-adapter.yaml`（新）
- `scripts/validate_claude_code_native_adapter_contract.rb`（新）
- `規格/v0.1/fixtures/claude-code-native-adapter-{positive,negative}-fixtures.json`（新）
- `.work/CARD-SSP308-RUNTIME-PROBE-BACKLOG-20260914.md`（新）
- `文件/待辦重整.md`
- `.work/evidence/SSP308-CLAUDE-CODE-NATIVE-ADAPTER-20260914.md`

## Evidence

`.work/evidence/SSP308-CLAUDE-CODE-NATIVE-ADAPTER-20260914.md`
