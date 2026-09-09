---
id: SSP303-HARNESS-20260909
status: ACCEPTED_GO_20260909
type: implementation
jira: SSP-303
lane: B
tier: T1
---

# SSP-303｜AIWR-06 輕量 Harness 編排

👉 [假設與目標確認]
- 目標：定義一份 machine-readable「輕量 Harness」契約：Harness 只**編排既有能力**
  （`SSP-301` Hook → `SSP-300` Skill → `SSP-302` Loop），不建 registry／FSM／DB／第二套
  runtime；每一步 input／output／timeout／error／receipt 可追溯；預設單 agent 順序執行，
  只有帶 measured-gap 佐證才 fan-out；可移除並回退為直接呼叫 Skill；不依賴常駐服務。
  新 yaml + 新薄 validator + fixtures。
- 邊界：只封 Harness 的「編排 + 可追溯 + 可移除」契約；不做 Hermes（`SSP-304`）、
  端到端主管視圖（`SSP-305`）、runtime／connector／DB／排程器；不重定義 `SSP-298`～`SSP-302`
  的已鎖契約，全部 pointer 引用。
- 驗收：見 Acceptance；DoD 要求最小 happy path／單步失敗／rollback 驗證通過，且無常駐服務依賴。

## Objective

以 `SSP-300`（Skill）、`SSP-301`（Hook）、`SSP-302`（Loop）三份已鎖契約為編排對象，定義
Harness 契約：

- `orchestration`：`allowed_capabilities`（鎖定 `HOOK` / `SKILL` / `LOOP` 三者，不得新增）；
  `steps[]` 每步 `capability ∈ allowed_capabilities`；`execution_mode` 預設
  `SEQUENTIAL_SINGLE_AGENT`；`fan_out` 只在該步帶 `measured_gap_ref`（URN）時允許。
- `no_second_runtime`：`builds_registry` / `builds_fsm` / `builds_database` /
  `builds_canonical_writer` 全 `false`。
- `step_record`：每個 executed step `{step, capability, input_ref, output_ref, timeout_seconds,
  error, receipt_ref}` 全欄；`input_ref` / `output_ref` / `receipt_ref` 為 URN（reference-only）；
  `timeout_seconds` 正整數。
- `step_failure`：單步失敗 → `outcome: STEP_FAILED` + `failed_step`；步驟有 `error` 但 run
  `outcome: COMPLETED` → fail-silent 拒。
- `disable_and_rollback`：`removable: true`、`fallback: DIRECT_SKILL_INVOCATION`、
  `rollback_contract.side_effects[]` 逐副作用列 `{name, teardown, failure_state}`（非 fixed-diff）。
- `authority`：`performs_memory_acceptance: false`、`writes_company_knowledge: false`、
  `makes_permission_decisions: false`、`error_behavior: FAIL_LOUD`。
- `no_always_on`：`requires_always_on_service: false`。
- `runtime_independence: true`；`cross_reference` pointer binding 至 hook／skill／loop／boundary spec；
  `hard_stops`：no hermes／runtime／DB；pure function + data tables；no registry／FSM／canonical writer。

## Root question

如何讓「輕量 Harness 串接 Hook／Skill／Loop、每步可追溯、預設順序單 agent、只有量測缺口才
fan-out、可移除回退直接呼叫 Skill、不依賴常駐服務」變成可驗契約，且不建立第二套 runtime、
不重定義 `SSP-298`～`SSP-302`？

## Traces to

- `規格/v0.1/ai-work-record-hook.yaml`（AIWR-04）、`ai-work-record-skill.yaml`（AIWR-03）、
  `ai-work-record-loop.yaml`（AIWR-05）：被編排的三個能力契約。
- `規格/v0.1/ai-work-record-boundary.yaml`：`automated_step_contract`（`FAIL_LOUD` /
  `fail_silent: forbidden` / `required_per_step`）。
- `.work/JIRA-PERSONAL-MEMORY-20260907/jira-tasks.json` `JIRA-DRAFT-AIWR-006` acceptance / dod。
- `~/.claude/CLAUDE.md`：`FORBIDDEN_BY_DEFAULT: new ledger/registry/FSM/DB/writer/runtime`；
  `RUNTIME_NATIVE_FIRST`；「預設單 agent／順序執行，只有量測缺口才 fan-out」；
  「activation/rollback/teardown 禁只做 fixed-diff」。
- 下游：`SSP-304`（Hermes adapter）、`SSP-305`（端到端 + 主管視圖）。
- Requirement IDs：spec 未定義 `US-*`/`FR-*`/`SC-*`；本卡以穩定 slice ID `SSP303-S01` 追溯。

## Dependencies / Blockers / Current frontier

- Dependencies：`SSP-300`／`SSP-301`／`SSP-302` = ACCEPTED_GO。
- Blockers：無。
- Current frontier：`SSP303-S01`。

## Scope

- 新 `規格/v0.1/ai-work-record-harness.yaml`：`schema`、`purpose`、`orchestration`、
  `no_second_runtime`、`step_record`、`step_failure`、`disable_and_rollback`、`authority`、
  `no_always_on`、`error_contract`、`runtime_independence`、`cross_reference`、`hard_stops`、
  `required_negative_fixtures`。
- `scripts/validate_ai_work_record_harness_contract.rb`（新薄 validator）：structural + 純函式
  `harness_run_failure(run, allowed_capabilities)` + `harness_rollback_failure(rollback)`；
  交叉讀 hook／skill／loop／boundary 四份 yaml；沿用 `scripts/lib/omos_contract_helpers.rb`。
- 正負 fixtures。
- backlog 狀態更新。

## Constraints

- 不做 Hermes／runtime／connector／DB／排程器。
- 不重定義 `SSP-298`～`SSP-302` 契約；pointer 引用並交叉驗證。
- 不改既有契約或 validator。
- validator 只做薄判斷；**不新增 registry／FSM／狀態機引擎**（本卡契約本身就禁這些）；不新增 package。
  推同 branch，不 merge。
- 檔案大小守 `.agentskills/docs/coding-standards.md` §2（validator `< 400`）。

## Product fit

- Measured gap：`SSP-300`～`SSP-302` 各自可驗，但沒有把「三者如何被串起來執行且不長成第二套
  runtime」寫成可驗。`SSP-304`（Hermes）與 `SSP-305`（端到端）需要一個可驗的編排單位作為替換點。
- Why not less：沒有 Harness 契約，串接邏輯會散進 runtime 或每個 connector 各寫一份，
  重演「第二套 runtime / 無界 fan-out / 不可移除」風險。
- Why not more：Hermes event 映射、實際 executor、常駐服務、主管視圖都不是本卡。
- Do not absorb：AI Core 的 orchestration framework、job scheduler、provider registry、
  ExecutionRequest/Receipt platform、任何 runtime-native workflow engine。
- Rollback：新 yaml + fixtures + 薄 validator，不連 runtime，可單獨 revert。

## Acceptance

1. `orchestration.allowed_capabilities` 剛好為 `[HOOK, SKILL, LOOP]`；`steps[]` 某步
   `capability ∉ allowed_capabilities` → `HARNESS_UNKNOWN_CAPABILITY`。
2. `execution_mode` 必須是 `SEQUENTIAL_SINGLE_AGENT`；某步 `fan_out: true` 但缺
   `measured_gap_ref`（URN）→ `HARNESS_UNJUSTIFIED_FANOUT`。
3. `no_second_runtime`：`builds_registry` / `builds_fsm` / `builds_database` /
   `builds_canonical_writer` 任一為 `true` → `HARNESS_SECOND_RUNTIME`。
4. `step_record`：每個 executed step 缺 `{step, capability, input_ref, output_ref,
   timeout_seconds, error, receipt_ref}` 任一 key → `HARNESS_STEP_NOT_TRACEABLE`；
   `input_ref` / `output_ref` / `receipt_ref` 非 URN → `HARNESS_STEP_REF_NOT_URN`；
   `timeout_seconds` 非正整數 → `HARNESS_STEP_NOT_TRACEABLE`。
5. `step_failure`：某步 `error` 非空但 run `outcome == "COMPLETED"` → `HARNESS_SILENT_STEP_FAILURE`；
   run `outcome == "STEP_FAILED"` 但缺 `failed_step` 或 `failed_step` 不在 steps → `HARNESS_STEP_FAILURE_UNMARKED`。
6. `authority`：`performs_memory_acceptance` / `writes_company_knowledge` /
   `makes_permission_decisions` 皆 `false`；run 帶 memory acceptance / canonical write /
   permission decision 欄位或宣稱越權 → `HARNESS_EXCEEDS_AUTHORITY`。
7. `no_always_on`：`requires_always_on_service: true` 或 run 宣稱依賴常駐服務 →
   `HARNESS_REQUIRES_ALWAYS_ON`。
8. `disable_and_rollback`：`removable: true`、`fallback: DIRECT_SKILL_INVOCATION`、
   `rollback_contract.side_effects[]` 每筆 `name` / `teardown` / `failure_state` 齊；
   缺 → `HARNESS_ROLLBACK_MISSING_FIELD` / `HARNESS_ROLLBACK_SIDE_EFFECT_UNSPECIFIED`。
9. `error_behavior: FAIL_LOUD`（與 boundary `error_behavior_enum` 交叉鎖）；run 有 `error` 但
   `ok != false` → `FAIL_SILENT`。
10. 最小 happy path（steps = HOOK → SKILL → LOOP，全 traceable，`outcome: COMPLETED`）→ allow。
11. `cross_reference`：pointer binding 至 hook／skill／loop／boundary spec；validator 鎖 pointer
    字串 exact 且引用目標存在。
12. `runtime_independence: true`：fixture 不含 runtime-specific 欄位仍可通過。
13. 負例至少：未知 capability、fan-out 無 measured gap、建 registry/FSM/DB/writer、step 缺欄位、
    step ref 非 URN、silent step failure、STEP_FAILED 未標 failed_step、帶 permission decision 欄位、
    要求常駐服務、rollback side effect 缺欄位、fail-silent。
14. 每個負例單一 mutation + exact failure code；移除對應 enforcement → gate 轉紅。
15. `ruby scripts/validate_ai_work_record_harness_contract.rb`、`validate_ai_work_record_loop_contract.rb`
    （regression）、`validate_ai_work_record_hook_contract.rb`（regression）、
    `validate_ai_work_record_skill_contract.rb`（regression）、
    `validate_ai_task_card_record_contract.rb`（regression）、
    `validate_ai_work_record_boundary_contract.rb`（regression）、
    `validate_personal_memory_contract.rb`（aggregator regression）、STD schema engine、
    STD-00~03、cross-layer、JSON/YAML parse、`git diff --check` 全 PASS。

## Stop conditions

- 若要表達 Harness 契約必須改 `SSP-298`～`SSP-302` 的已鎖契約 → 停，回 Owner。
- 若編排無法用純函式 + 資料表表達、需要狀態機引擎或 runtime → 停，回 Owner（那正是本卡禁止的）。
- 只有 P0/P1 阻塞 Lane B 後續（`SSP-304` 起）。

## Likely files

- `規格/v0.1/ai-work-record-harness.yaml`（新）
- `規格/v0.1/fixtures/ai-work-record-harness-positive-fixtures.json`（新）
- `規格/v0.1/fixtures/ai-work-record-harness-negative-fixtures.json`（新）
- `scripts/validate_ai_work_record_harness_contract.rb`（新）
- `文件/待辦重整.md`（Lane B 進度）
- `.work/evidence/SSP303-HARNESS-20260909.md`

## Evidence

`.work/evidence/SSP303-HARNESS-20260909.md`
