---
id: SSP304-HERMES-ADAPTER-20260909
status: IN_REPAIR_01
type: implementation
jira: SSP-304
lane: B
tier: T1
---

# SSP-304｜AIWR-07 Hermes 薄 Adapter

👉 [假設與目標確認]
- 目標：定義一份 machine-readable「Hermes 薄 Adapter」契約：Adapter 只把 Hermes event
  **映射**到既有 `SSP-300` Skill 的 I/O（lifecycle event / seed field），不加任何語意；
  Hermes 不取得 acceptance／permission／canonical writer authority；未安裝 Hermes 時核心流程
  仍可用；版本不相容時 fail loud 且可停用 Adapter 回退核心流程；無全員安裝要求。
  新 yaml + 新薄 validator + fixtures。
- 邊界：只封 Adapter 的「event 映射 + authority 限制 + 可選依賴 + 相容性 fail-loud + 可停用」
  契約；不做端到端 + 主管視圖（`SSP-305`）、實際 Hermes runtime／connector／event bus；
  不重定義 `SSP-298`～`SSP-303` 的已鎖契約，全部 pointer 引用。
- 驗收：見 Acceptance；DoD 要求 Hermes mapping／相容性負例／停用回退通過，且無全員安裝要求。

## Objective

以 `SSP-300`（Skill `input_contract`）、`SSP-303`（Harness）與 `SSP-298`（boundary
`automated_step_contract`）為對象，定義 Adapter 契約：

- `event_mapping`：`hermes_event_map` 每筆 `{hermes_event, mapped_to}`；`mapped_to` 必須是
  Skill I/O 的既有目標（`ai-task-card-record.lifecycle_event_to_status` 的 key ∪
  `ai-work-record-skill.input_contract.seed_field_keys`）；`adapter_adds_fields` 必須為空
  （Adapter 只翻譯,不新增語意）。
- `authority`：`grants_acceptance: false`、`grants_permission: false`、
  `grants_canonical_writer: false`；Adapter output 帶 acceptance／permission／canonical write
  欄位或宣稱越權 → 拒。
- `optional_dependency`：`hermes_required: false`、`core_flow_without_hermes: SUPPORTED`。
- `compatibility`：`supported_hermes_versions`（非空清單）；`on_incompatible: FAIL_LOUD`；
  `adapter_disable: SUPPORTED`。mapping run 的 `hermes_version` 不在支援清單時,`outcome`
  必須是 `INCOMPATIBLE_FAIL_LOUD`。
- `disable_and_rollback`：`disable_switch: true`、`fallback: CORE_FLOW_DIRECT`、
  `side_effects[]` 逐副作用列 `{name, teardown, failure_state}`（非 fixed-diff）。
- `no_org_wide_install`：`requires_all_users_install: false`。
- `mapping_run`：`{hermes_event, mapped_to, adapter_output_ref, hermes_version, outcome}`；
  `outcome ∈ {MAPPED, INCOMPATIBLE_FAIL_LOUD, DISABLED}`；`adapter_output_ref` 為 URN（reference-only）。
- `error_behavior: FAIL_LOUD`；`runtime_independence: true`；`cross_reference` pointer binding
  至 skill／harness／boundary spec；`hard_stops`：no hermes runtime／event bus／connector；
  pure function + data tables；no registry／FSM／canonical writer；不重定義上游契約。

## Root question

如何讓「Hermes 只透過薄 Adapter 呼叫同一工作紀錄契約、可替換 executor 而不改資料與治理語意、
未安裝仍可用、版本不相容 fail loud 可停用」變成可驗契約,且 Adapter 不加語意、不取得
acceptance／permission／canonical authority?

## Traces to

- `規格/v0.1/ai-work-record-skill.yaml`：`input_contract`（`seed_field_keys`）、`authority`。
- `規格/v0.1/ai-task-card-record.yaml`：`lifecycle_event_to_status`。
- `規格/v0.1/ai-work-record-harness.yaml`：`orchestration`（Adapter 是 Harness 之外的可選替換點）。
- `規格/v0.1/ai-work-record-boundary.yaml`：`automated_step_contract`（`FAIL_LOUD` / `fail_silent: forbidden`）。
- `.work/JIRA-PERSONAL-MEMORY-20260907/jira-tasks.json` `JIRA-DRAFT-AIWR-007` acceptance / dod。
- `~/.claude/CLAUDE.md`：`RUNTIME_NATIVE_FIRST`（native / 薄 mapping，禁第二套）;
  「activation/rollback/teardown 禁只做 fixed-diff」。
- 下游：`SSP-305`（端到端 + 主管視圖）。
- Requirement IDs：spec 未定義 `US-*`/`FR-*`/`SC-*`；本卡以穩定 slice ID `SSP304-S01` 追溯。

## Dependencies / Blockers / Current frontier

- Dependencies：`SSP-300`／`SSP-303` = ACCEPTED_GO。
- Blockers：無。
- Current frontier：`SSP304-S01`。

## Scope

- 新 `規格/v0.1/ai-work-record-hermes-adapter.yaml`：`schema`、`purpose`、`event_mapping`、
  `authority`、`optional_dependency`、`compatibility`、`disable_and_rollback`、
  `no_org_wide_install`、`mapping_run`、`error_contract`、`runtime_independence`、
  `cross_reference`、`hard_stops`、`required_negative_fixtures`。
- `scripts/validate_ai_work_record_hermes_adapter_contract.rb`（新薄 validator）：structural +
  純函式 `hermes_adapter_failure(run, allowed_map_targets)` + `hermes_rollback_failure(rollback)`；
  交叉讀 skill／task-card-record／harness／boundary yaml；沿用 `scripts/lib/omos_contract_helpers.rb`。
- 正負 fixtures。
- backlog 狀態更新。

## Constraints

- 不做 Hermes runtime／event bus／connector／端到端視圖。
- 不重定義 `SSP-298`～`SSP-303` 契約；pointer 引用並交叉驗證。
- 不改既有契約或 validator。
- validator 只做薄判斷；不新增 registry／FSM／狀態機引擎；不新增 package。推同 branch,不 merge。
- 檔案大小守 `.agentskills/docs/coding-standards.md` §2（validator `< 400`）。

## Product fit

- Measured gap：`SSP-303` 定義本地編排,但沒有把「外部 executor（Hermes）如何透過薄 mapping
  呼叫同一契約而不改治理語意」寫成可驗。`SSP-305` 端到端需要一個可驗的替換點。
- Why not less：沒有 Adapter 契約,Hermes 整合會直接接進 runtime,重演「executor 取得治理
  authority / 全員強制安裝 / 版本不相容靜默」風險。
- Why not more：Hermes 實際 event schema、runtime、connector、主管視圖都不是本卡。
- Do not absorb：Hermes 本身、其 event bus／provider registry、任何 runtime-native adapter framework。
- Rollback：新 yaml + fixtures + 薄 validator,不連 runtime,可單獨 revert。

## Acceptance

1. `event_mapping.hermes_event_map` 每筆 `mapped_to ∈ allowed_map_targets`
   （`lifecycle_event_to_status` key ∪ skill `seed_field_keys`）；否則 `HERMES_MAP_TARGET_UNKNOWN`。
2. `event_mapping.adapter_adds_fields` 必須為空清單；非空 → `HERMES_ADAPTER_ADDS_SEMANTICS`。
3. `authority`：`grants_acceptance` / `grants_permission` / `grants_canonical_writer` 皆 `false`；
   run 帶 `personal_acceptance_ref` / `permission_decision_ref` / `canonical_write_receipt_ref`
   欄位或宣稱越權 → `HERMES_EXCEEDS_AUTHORITY`。
4. `optional_dependency`：`hermes_required: false`、`core_flow_without_hermes: SUPPORTED`；
   run 宣稱 `hermes_required: true` 或 `core_flow_blocked_without_hermes: true` → `HERMES_MANDATORY`。
5. `compatibility`：`supported_hermes_versions` 非空；mapping run 的 `hermes_version` 不在
   支援清單但 `outcome != "INCOMPATIBLE_FAIL_LOUD"` → `HERMES_INCOMPAT_NOT_LOUD`。
6. `mapping_run`：`outcome ∉ {MAPPED, INCOMPATIBLE_FAIL_LOUD, DISABLED}` → `HERMES_INVALID_OUTCOME`；
   `outcome == MAPPED` 但 `mapped_to ∉ allowed_map_targets` → `HERMES_MAP_TARGET_UNKNOWN`；
   `adapter_output_ref` 非 URN → `HERMES_OUTPUT_NOT_REF`。
7. `no_org_wide_install`：`requires_all_users_install: true` → `HERMES_ORG_WIDE_INSTALL`。
8. `disable_and_rollback`：`disable_switch: true`、`fallback: CORE_FLOW_DIRECT`、
   `side_effects[]` 每筆 `name` / `teardown` / `failure_state` 齊；缺 →
   `HERMES_ROLLBACK_MISSING_FIELD` / `HERMES_ROLLBACK_SIDE_EFFECT_UNSPECIFIED`；
   `outcome == DISABLED` 但 run 仍有非空 `adapter_output_ref` → `HERMES_DISABLED_STILL_MAPPING`。
9. `error_behavior: FAIL_LOUD`（與 boundary `error_behavior_enum` 交叉鎖）；run 有 `error` 但
   `ok != false` → `FAIL_SILENT`。
10. 最小 happy path（`hermes_event_map` 全 valid、`outcome: MAPPED`、`hermes_version` 在支援清單、
    `adapter_output_ref` 為 URN）→ allow。
11. `cross_reference`：pointer binding 至 skill／task-card-record／harness／boundary spec；
    validator 鎖 pointer 字串 exact 且引用目標存在。
12. `runtime_independence: true`：fixture 不含 runtime-specific 欄位仍可通過。
13. 負例至少：map 目標未知、Adapter 新增欄位、帶 permission 欄位、宣稱 hermes 必裝、
    版本不相容未 fail-loud、非法 outcome、output 非 URN、全員安裝、停用仍映射、
    rollback side effect 缺欄位、fail-silent。
14. 每個負例單一 mutation + exact failure code；移除對應 enforcement → gate 轉紅。
15. `ruby scripts/validate_ai_work_record_hermes_adapter_contract.rb`、
    `validate_ai_work_record_harness_contract.rb`（regression）、
    `validate_ai_work_record_loop_contract.rb`（regression）、
    `validate_ai_work_record_hook_contract.rb`（regression）、
    `validate_ai_work_record_skill_contract.rb`（regression）、
    `validate_ai_task_card_record_contract.rb`（regression）、
    `validate_ai_work_record_boundary_contract.rb`（regression）、
    `validate_personal_memory_contract.rb`（aggregator regression）、STD schema engine、
    STD-00~03、cross-layer、JSON/YAML parse、`git diff --check` 全 PASS。

## Stop conditions

- 若要表達 Adapter 契約必須改 `SSP-298`～`SSP-303` 的已鎖契約 → 停,回 Owner。
- 若 event 映射無法用純函式 + 資料表表達、需要狀態機引擎或 runtime → 停,回 Owner。
- 只有 P0/P1 阻塞 Lane B 後續（`SSP-305`）。

## Likely files

- `規格/v0.1/ai-work-record-hermes-adapter.yaml`（新）
- `規格/v0.1/fixtures/ai-work-record-hermes-adapter-positive-fixtures.json`（新）
- `規格/v0.1/fixtures/ai-work-record-hermes-adapter-negative-fixtures.json`（新）
- `scripts/validate_ai_work_record_hermes_adapter_contract.rb`（新）
- `文件/待辦重整.md`（Lane B 進度）
- `.work/evidence/SSP304-HERMES-ADAPTER-20260909.md`

## Evidence

`.work/evidence/SSP304-HERMES-ADAPTER-20260909.md`
