---
id: SSP302-LOOP-CLOSEOUT-20260909
status: IMPLEMENTED_AWAITING_BIG_REVIEW
type: implementation
jira: SSP-302
lane: B
tier: T1
---

# SSP-302｜AIWR-05 Loop 收口與缺口補登

👉 [假設與目標確認]
- 目標：定義一份 machine-readable「收口 Loop」契約：任務結束時檢查工作紀錄草稿缺哪些
  必要欄位／未完成項，逐輪只補「必要 evidence／status」，有明確終止條件（最大次數 +
  timeout + 終止狀態）、不擴張 scope、缺人類決策就停並標 blocker、無法修復就 fail loud
  且保留原始證據。新 yaml + 新薄 validator + fixtures。
- 邊界：只封 Loop 的「缺口盤點 → 有界補登 → 終止」契約；不做 Hook（`SSP-301`）、
  Harness（`SSP-303`）、Hermes（`SSP-304`）、runtime／connector／DB；不重定義 `SSP-298`
  邊界、`SSP-299` 卡片格式或 `SSP-300` Skill I/O，全部 pointer 引用。
- 驗收：見 Acceptance；DoD 要求正常收口／缺欄位／需要人類決策／超限四類案例通過。

## Objective

以 `SSP-299`（`ai-task-card-record.yaml` 的 `fields` / `fail_closed_rules` / `status_enum`）
與 `SSP-300`（`ai-work-record-skill.yaml` 的 `output_contract.draft_card`）為基礎，定義收口
Loop 契約：

- `termination`：`max_iterations`（int > 0）、`timeout_seconds`（int > 0）、`terminal_conditions`
  （鎖定集合 `ALL_REQUIRED_PRESENT` / `MAX_ITERATIONS_REACHED` / `TIMEOUT` / `BLOCKER_MARKED`
  / `UNFIXABLE`）；缺 `max_iterations` 或 `timeout_seconds` → `LOOP_UNBOUNDED`。
- `scope_lock`：`fillable_fields`（只允許 `evidence_refs` / `status` / 缺的 required field）；
  Loop 不得改 `objective` / `scope` / `constraints` / `acceptance` 或新增欄位 → `LOOP_SCOPE_EXPANSION`。
- `human_decision_gate`：`gap.requires_human_decision == true` 的缺口，Loop 必須停在
  `outcome: BLOCKED` + `blocker_ref`；仍繼續補 → `LOOP_SKIPPED_HUMAN_DECISION`。
- `unfixable`：非人類決策但無法自動補的缺口 → `outcome: FAILED_LOUD` 且
  `original_evidence_preserved: true`；靜默丟棄或宣稱成功 → `LOOP_UNFIXABLE_NOT_LOUD` / `FAIL_SILENT`。
- `run_record`：`iterations[]` 每輪 `{iteration, filled_fields, remaining_gaps}`；
  `outcome ∈ {CLOSED, BLOCKED, FAILED_LOUD}` 且與觸發的 terminal condition 一致；
  `iterations.length <= max_iterations`。
- `authority`：`performs_memory_acceptance: false`、`writes_company_knowledge: false`、
  `error_behavior: FAIL_LOUD`（沿用 AIWR 家族 authority floor）。
- `runtime_independence: true`；`cross_reference` pointer binding 至 task-card-record 與 skill spec。
- `hard_stops`：no hook／harness／hermes／runtime；pure function + data tables；
  no registry／FSM／DB／canonical writer；不重定義上游三份契約。

## Root question

如何讓「收口 Loop 在有界（次數 + timeout + 終止狀態）內只補必要欄位、不擴張 scope、
缺人類決策即停標 blocker、無法修復即 fail loud 保留原證據」變成可驗契約，且沿用
（不重定義）`SSP-298`／`SSP-299`／`SSP-300`？

## Traces to

- `規格/v0.1/ai-task-card-record.yaml`：`fields`、`fail_closed_rules`、`status_enum`、`lifecycle_event_to_status`。
- `規格/v0.1/ai-work-record-skill.yaml`：`output_contract.draft_card`、`authority`。
- `規格/v0.1/ai-work-record-boundary.yaml`：`automated_step_contract`（`FAIL_LOUD` / `fail_silent: forbidden`）。
- `.work/JIRA-PERSONAL-MEMORY-20260907/jira-tasks.json` `JIRA-DRAFT-AIWR-005` acceptance / dod。
- 下游：`SSP-303`（Harness）、`SSP-305`（主管視圖）。
- `~/.claude/CLAUDE.md`：「Loop 有明確終止條件、最大次數與 timeout；缺人類決策時停止並標記 blocker；無法修復時 fail loud，保留原始證據」。
- Requirement IDs：spec 未定義 `US-*`/`FR-*`/`SC-*`；本卡以穩定 slice ID `SSP302-S01` 追溯。

## Dependencies / Blockers / Current frontier

- Dependencies：`SSP-299`／`SSP-300` = ACCEPTED_GO（`SSP-301` 亦已 merge，但本卡只依賴 AIWR-03）。
- Blockers：無。
- Current frontier：`SSP302-S01`。

## Scope

- 新 `規格/v0.1/ai-work-record-loop.yaml`：`schema`、`purpose`、`termination`、`scope_lock`、
  `human_decision_gate`、`unfixable`、`run_record`、`authority`、`error_contract`、
  `runtime_independence`、`cross_reference`、`hard_stops`、`required_negative_fixtures`。
- `scripts/validate_ai_work_record_loop_contract.rb`（新薄 validator）：structural + 純函式
  `loop_closeout_failure(config, run)` evaluator；交叉讀 task-card-record／skill／boundary 三份 yaml；
  沿用 `scripts/lib/omos_contract_helpers.rb`。
- 正負 fixtures。
- backlog 狀態更新。

## Constraints

- 不做 Hook／Harness／Hermes／runtime／connector／DB。
- 不重定義 `SSP-298`／`SSP-299`／`SSP-300` 契約；pointer 引用並交叉驗證。
- 不改既有契約或 validator。
- validator 只做薄判斷；不新增 registry／FSM／狀態機引擎；不新增 package。推同 branch，不 merge。
- 檔案大小守 `.agentskills/docs/coding-standards.md` §2（validator `< 400`）。

## Product fit

- Measured gap：`SSP-300` 產出草稿，但沒有把「交接前如何有界地補完草稿、何時該停、何時該
  fail loud」寫成可驗。`SSP-303`（Harness）需要一個可驗的收口單位；沒有它，Harness 會
  自訂重試迴圈，重演「無限重試 / scope 膨脹」風險。
- Why not less：沒有 Loop 契約，收口邏輯會散在 Hook 與 Harness，終止條件與 scope lock 無處落地。
- Why not more：Hook 事件擷取、Harness 編排、Hermes adapter、實際 runtime 排程都不是本卡。
- Do not absorb：AI Core 的 loop／retry framework、job scheduler、任何 runtime-native 收口。
- Rollback：新 yaml + fixtures + 薄 validator，不連 runtime，可單獨 revert。

## Acceptance

1. `termination`：`max_iterations` 為正整數、`timeout_seconds` 為正整數、`terminal_conditions`
   剛好為鎖定 5 值；缺 `max_iterations` 或 `timeout_seconds`、或非正 → `LOOP_UNBOUNDED`。
2. `run_record`：`iterations.length > max_iterations` → `LOOP_OVER_MAX_ITERATIONS`；
   `outcome` ∉ `{CLOSED, BLOCKED, FAILED_LOUD}` → `LOOP_INVALID_OUTCOME`；
   `outcome` 與 `terminal_condition` 不一致（如 `CLOSED` 卻不是 `ALL_REQUIRED_PRESENT` / `MAX_ITERATIONS_REACHED`）→ `LOOP_OUTCOME_CONDITION_MISMATCH`。
3. `scope_lock`：某輪 `filled_fields` 含 `fillable_fields` 以外的欄位（`objective` / `scope` /
   `constraints` / `acceptance` / 未知欄位）→ `LOOP_SCOPE_EXPANSION`。
4. `human_decision_gate`：`remaining_gaps` 含 `requires_human_decision: true` 的缺口，但
   `outcome != BLOCKED` 或缺 `blocker_ref` → `LOOP_SKIPPED_HUMAN_DECISION`。
5. `unfixable`：`remaining_gaps` 含 `auto_fixable: false` 且非人類決策的缺口，但
   `outcome != FAILED_LOUD` → `LOOP_UNFIXABLE_NOT_LOUD`；`outcome == FAILED_LOUD` 但
   `original_evidence_preserved != true` → `LOOP_EVIDENCE_NOT_PRESERVED`。
6. `authority`：`performs_memory_acceptance: false`、`writes_company_knowledge: false`；
   run 帶 memory acceptance / canonical write 欄位或宣稱越權 → `LOOP_EXCEEDS_AUTHORITY`。
7. `error_behavior: FAIL_LOUD`；run 有 `error` 但 `ok != false` → `FAIL_SILENT`。
8. 正常收口（所有 required 欄位補齊、`outcome: CLOSED`、`terminal_condition: ALL_REQUIRED_PRESENT`、
   `iterations.length <= max_iterations`）→ allow。
9. `cross_reference`：pointer binding 至 `ai-task-card-record.yaml` 的 `fields` / `status_enum`
   與 `ai-work-record-skill.yaml` 的 `output_contract.draft_card`；validator 鎖 pointer 字串
   exact 且引用目標存在。
10. `runtime_independence: true`：fixture 不含 runtime-specific 欄位仍可通過。
11. 負例至少：unbounded（缺 max / 缺 timeout）、超過 max iterations、非法 outcome、
    outcome 與 condition 不符、scope expansion、跳過人類決策、unfixable 不 loud、
    fail-loud 但沒保留原證據、帶 memory acceptance 欄位、fail-silent。
12. 每個負例單一 mutation + exact failure code；移除對應 enforcement → gate 轉紅。
13. `ruby scripts/validate_ai_work_record_loop_contract.rb`、`validate_ai_work_record_skill_contract.rb`
    （regression）、`validate_ai_task_card_record_contract.rb`（regression）、
    `validate_ai_work_record_boundary_contract.rb`（regression）、
    `validate_ai_work_record_hook_contract.rb`（regression）、
    `validate_personal_memory_contract.rb`（aggregator regression）、STD schema engine、
    STD-00~03、cross-layer、JSON/YAML parse、`git diff --check` 全 PASS。

## Stop conditions

- 若要表達 Loop 契約必須改 `SSP-298`／`SSP-299`／`SSP-300` 的已鎖契約 → 停，回 Owner。
- 若收口迴圈無法用純函式 + 資料表表達、需要狀態機引擎或 runtime → 停，回 Owner。
- 只有 P0/P1 阻塞 Lane B 後續（`SSP-303` 起）。

## Likely files

- `規格/v0.1/ai-work-record-loop.yaml`（新）
- `規格/v0.1/fixtures/ai-work-record-loop-positive-fixtures.json`（新）
- `規格/v0.1/fixtures/ai-work-record-loop-negative-fixtures.json`（新）
- `scripts/validate_ai_work_record_loop_contract.rb`（新）
- `文件/待辦重整.md`（Lane B 進度）
- `.work/evidence/SSP302-LOOP-CLOSEOUT-20260909.md`

## Evidence

`.work/evidence/SSP302-LOOP-CLOSEOUT-20260909.md`
