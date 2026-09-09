---
id: SSP301-AIWR-HOOK-20260909
status: DRAFT_OWNER_REVIEW
type: implementation
jira: SSP-301
lane: B
tier: T1
---

# SSP-301｜AIWR-04 Hook 事件擷取

👉 [假設與目標確認]
- 目標：定義一份 machine-readable「工作紀錄 Hook」契約：Hook 在任務 lifecycle 事件
  （start / update / complete …）發生時自動擷取事件，整理成一批可交給 `SSP-300`
  工作紀錄 Skill 的輸入；只擷取允許的 lifecycle events、重複事件冪等、擷取失敗不阻斷
  宿主任務、不讀未授權內容、不執行 memory acceptance、可停用並回退為手動 Skill 呼叫。
  新 yaml + 新薄 validator + fixtures。
- 邊界：只封 Hook 的「事件擷取 → Skill 輸入批次」契約與其 authority／隔離／停用回退限制；
  不做 Loop（`SSP-302`）、Harness（`SSP-303`）、Hermes（`SSP-304`）、runtime／connector／DB；
  不重定義 `SSP-298` 邊界、`SSP-299` 卡片格式或 `SSP-300` Skill I/O，全部 pointer 引用。
- 驗收：見 Acceptance；DoD 要求 Hook 正常／重複／缺權限／停用四類案例通過，且 rollback 有證據。

## Objective

以 `SSP-298`（`ai-work-record-boundary.yaml` 的 `automated_step_contract`、`non_acceptance_authority`）、
`SSP-299`（`ai-task-card-record.yaml` 的 `lifecycle_event_to_status`）與 `SSP-300`
（`ai-work-record-skill.yaml` 的 `input_contract`）為基礎，定義 Hook 契約：

- `capture_contract`：`allowed_events`（必須是 `ai-task-card-record.lifecycle_event_to_status`
  的 key 子集）、`event_envelope_fields`（`task_ref`、`event`、`occurred_at`、`event_key`、
  `evidence_refs`；全 reference-only）、`idempotency`（以 `event_key` 去重；重複事件不得產生
  第二筆）、`ordering`（batch 內 replay 後第一個事件為 `start`）。
- `failure_isolation`：`on_error: ISOLATE_FROM_HOST_TASK`；禁 `PROPAGATE`／`RAISE_INTO_HOST`；
  Hook 例外只記錄／丟棄／排隊，宿主任務不受影響。
- `authority`：`reads_task_content: false`、`performs_memory_acceptance: false`、
  `writes_company_knowledge: false`、`error_behavior: FAIL_LOUD`（對 Hook 自身可觀測性，
  非對宿主任務）。output 批次帶 acceptance／canonical write 欄位 → 拒。
- `output_contract`：Hook 產出的 `lifecycle_events` 批次必須是 contract-valid 的
  `ai-work-record-skill` `input_contract.lifecycle_events`（pointer binding）；`seed_fields`
  由 Hook 帶 reference 或留給 Skill 呼叫端；Hook 不自行組 `draft_card`。
- `disable_and_rollback`：`disable_switch: true`；`disabled_behavior: EMIT_NOTHING`；
  `fallback: MANUAL_SKILL_INVOCATION`；`rollback_contract.side_effects[]` —— 逐副作用列
  `{name, teardown, failure_state}`（event queue、已註冊 handler、部分批次），不得只給 fixed diff。
- `runtime_independence: true`：fixture 不含 runtime-specific 欄位仍可驗（純函式 + 資料表）。
- `cross_reference`：pointer binding 至 boundary／task-card-record／skill 三份 spec；
  validator 鎖 pointer 字串 exact 且引用目標存在。
- `hard_stops`：no loop／harness／hermes／runtime；pure function + data tables；
  no registry／FSM／DB／canonical writer；不重定義上游三份契約。

## Root question

如何讓「Hook 自動把任務 lifecycle 事件轉成一批合規 Skill 輸入、重複冪等、失敗不炸宿主任務、
不取得 read／acceptance／canonical authority、可停用回退為手動 Skill」變成可驗契約，且沿用
（不重定義）`SSP-298`／`SSP-299`／`SSP-300`？

## Traces to

- `規格/v0.1/ai-work-record-boundary.yaml`：`automated_step_contract`（`error_behavior_enum: [FAIL_LOUD]`、
  `fail_silent: forbidden`、`allowed_gate_positions`）、`non_acceptance_authority.signals`。
- `規格/v0.1/ai-task-card-record.yaml`：`lifecycle_event_to_status`、`allowed_status_transitions`。
- `規格/v0.1/ai-work-record-skill.yaml`：`input_contract`（`lifecycle_events_rule`、`seed_field_keys`）。
- `.work/JIRA-PERSONAL-MEMORY-20260907/jira-tasks.json` `JIRA-DRAFT-AIWR-004` acceptance / dod。
- 下游：`SSP-302`（Loop）、`SSP-303`（Harness）、`SSP-305`（主管視圖）。
- `~/.claude/CLAUDE.md`：「activation/rollback/teardown 禁只做 fixed-diff；從 trap/handler 逐副作用列 failure state」。
- Requirement IDs：spec 未定義 `US-*`/`FR-*`/`SC-*`；本卡以穩定 slice ID `SSP301-S01` 追溯。

## Dependencies / Blockers / Current frontier

- Dependencies：`SSP-298`／`SSP-299`／`SSP-300` = ACCEPTED_GO。
- Blockers：無（Lane B 零外部依賴）。
- Current frontier：`SSP301-S01`。

## Scope

- 新 `規格/v0.1/ai-work-record-hook.yaml`：`schema`、`purpose`、`capture_contract`、
  `failure_isolation`、`authority`、`output_contract`、`disable_and_rollback`、`error_contract`、
  `runtime_independence`、`cross_reference`、`hard_stops`、`required_negative_fixtures`。
- `scripts/validate_ai_work_record_hook_contract.rb`（新薄 validator）：structural + 純函式
  `hook_capture_failure(config, event_batch)` evaluator + idempotency／ordering 檢查，
  交叉讀 boundary／task-card-record／skill 三份 yaml；沿用 `scripts/lib/omos_contract_helpers.rb`。
- 正負 fixtures。
- backlog 狀態更新。

## Constraints

- 不做 Loop／Harness／Hermes／runtime／connector／DB。
- 不重定義 `SSP-298`／`SSP-299`／`SSP-300` 契約；pointer 引用並交叉驗證。
- 不改既有 STD／EMEM／boundary／task-card-record／skill 契約。
- validator 只做薄判斷；不新增 registry／FSM／狀態機引擎；不新增 package。推同 branch，不 merge。
- 檔案大小守 `.agentskills/docs/coding-standards.md` §2（validator `< 400`）。

## Product fit

- Measured gap：`SSP-300` 定義 Skill 的事件→草稿轉換，但沒有把「事件如何被自動擷取、
  去重、失敗隔離、停用回退」寫成可驗。`SSP-302`（Loop）與 `SSP-305`（主管視圖）需要一個
  可驗的 Hook 契約作為觸發來源。
- Why not less：沒有 Hook 契約，Loop 與 runtime 會各自定義事件擷取與去重，重演分裂，
  且「失敗不阻斷宿主任務」「停用回退」這兩條安全性質無處落地。
- Why not more：Loop 收口、Harness 編排、Hermes adapter、實際 runtime handler 都不是本卡。
- Do not absorb：AI Core 的 hook／event bus、ExecutionRequest/Receipt platform、
  provider registry、任何 runtime-native event normalization。
- Rollback：新 yaml + fixtures + 薄 validator，不連 runtime，可單獨 revert。

## Acceptance

1. `capture_contract.allowed_events` ⊆ `ai-task-card-record.lifecycle_event_to_status` 的 key；
   batch 含不在 allowed 集合的 event → `HOOK_EVENT_NOT_ALLOWED`。
2. `event_envelope_fields` 齊備且全 reference-only；envelope 內嵌內容（非 URN 的 evidence、
   task body）→ `HOOK_EVENT_INLINE_CONTENT`。
3. idempotency：同一 `event_key` 出現兩次，evaluator 必須把批次收斂成一筆；宣稱處理但仍留
   兩筆 → `HOOK_DUPLICATE_NOT_IDEMPOTENT`。
4. ordering：batch replay（去重後）第一個事件不是 `start` → `HOOK_BATCH_MUST_START`；
   event 序列不符 `allowed_status_transitions` → `HOOK_ILLEGAL_TRANSITION`。
5. `failure_isolation.on_error` 必須是 `ISOLATE_FROM_HOST_TASK`；契約值為 `PROPAGATE`／
   `RAISE_INTO_HOST`／缺 → `HOOK_FAILURE_BLOCKS_HOST_TASK`。
6. `authority`：`reads_task_content: false`、`performs_memory_acceptance: false`、
   `writes_company_knowledge: false`；output batch 帶 `personal_acceptance_ref`／
   `verification_receipt_ref`／`accepted_for_record`／`canonical_write_receipt_ref` → `HOOK_EXCEEDS_AUTHORITY`。
7. `output_contract`：Hook 產出的 `lifecycle_events` 批次餵進 `ai-work-record-skill`
   `input_contract` 檢查（重用 `SSP-300` 規則或等效）必須 valid；不符 → `HOOK_OUTPUT_NOT_SKILL_INPUT`。
8. `disable_and_rollback`：`disable_switch: true`、`disabled_behavior: EMIT_NOTHING`、
   `fallback: MANUAL_SKILL_INVOCATION`；`rollback_contract.side_effects[]` 每筆有
   `name`／`teardown`／`failure_state` 三欄，缺任一 → `HOOK_ROLLBACK_SIDE_EFFECT_UNSPECIFIED`；
   停用狀態下 evaluator 對任何 event batch 必須回 `EMIT_NOTHING`（空批次），非空 → `HOOK_DISABLED_STILL_EMITTING`。
9. `error_behavior: FAIL_LOUD`；Hook 自身 error 但 output 仍宣稱成功（fail-silent）→ 拒。
10. `cross_reference`：pointer binding 至 `ai-work-record-boundary.yaml`／`ai-task-card-record.yaml`／
    `ai-work-record-skill.yaml`；validator 鎖 pointer 字串 exact 且引用目標存在。
11. `runtime_independence: true`：fixture 不含 runtime-specific 欄位仍可通過。
12. 負例至少：不允許的 event、envelope 內嵌內容、重複非冪等、batch 不以 start 起、
    非法 transition、failure 傳進宿主任務、output 帶 acceptance 欄位、output 非 Skill valid input、
    rollback side effect 缺欄位、停用仍發事件、fail-silent。
13. 每個負例單一 mutation + exact failure code；移除對應 enforcement → gate 轉紅。
14. `ruby scripts/validate_ai_work_record_hook_contract.rb`、`ruby scripts/validate_ai_work_record_skill_contract.rb`
    （regression）、`validate_ai_task_card_record_contract.rb`（regression）、
    `validate_ai_work_record_boundary_contract.rb`（regression）、
    `ruby scripts/validate_personal_memory_contract.rb`（aggregator regression）、STD schema engine、
    STD-00~03、cross-layer、JSON/YAML parse、`git diff --check` 全 PASS。

## Stop conditions

- 若要表達 Hook 契約必須改 `SSP-298`／`SSP-299`／`SSP-300` 的已鎖契約 → 停，回 Owner
  （可能先回對應 review line）。
- 若 Hook 的事件擷取／去重／隔離無法用純函式 + 資料表表達、需要狀態機引擎或 runtime → 停，回 Owner。
- 只有 P0/P1 阻塞 Lane B 後續（`SSP-302` 起）。

## Likely files

- `規格/v0.1/ai-work-record-hook.yaml`（新）
- `規格/v0.1/fixtures/ai-work-record-hook-positive-fixtures.json`（新）
- `規格/v0.1/fixtures/ai-work-record-hook-negative-fixtures.json`（新）
- `scripts/validate_ai_work_record_hook_contract.rb`（新）
- `文件/待辦重整.md`（Lane B 進度）
- `.work/evidence/SSP301-AIWR-HOOK-20260909.md`

## Evidence

`.work/evidence/SSP301-AIWR-HOOK-20260909.md`
