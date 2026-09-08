---
id: SSP300-WORK-RECORD-SKILL-20260909
status: DRAFT_OWNER_REVIEW
type: implementation
jira: SSP-300
lane: B
tier: T1
---

# SSP-300｜AIWR-03 工作紀錄 Skill

👉 [假設與目標確認]
- 目標：定義一份 machine-readable「工作紀錄 Skill」契約：Skill 只負責「lifecycle event 輸入 → 工作紀錄草稿輸出」的轉換；輸入／輸出 schema、dry-run、錯誤訊息明確；Skill 不接受 Memory、不寫 Company Knowledge；無 runtime 特定狀態時仍可獨立測試。新 yaml + 新薄 validator + fixtures。
- 邊界：只封 Skill 的 I/O 契約與其 authority 限制；不做 Hook（`SSP-301`）、Loop（`SSP-302`）、Harness（`SSP-303`）；不重定義 `SSP-298` 邊界或 `SSP-299` 卡片格式。
- 驗收：見 Acceptance；DoD 要求正向 / 缺欄位 / 越權負例通過,且可由至少一個 runtime 呼叫。

## Objective

以 `SSP-298`（`ai-work-record-boundary.yaml`）的 `automated_step_contract` 與 `SSP-299`（`ai-task-card-record.yaml`）的 task card record 格式為基礎，定義「工作紀錄 Skill」的轉換契約：`input`（lifecycle events + seed fields，符合 AIWR-01 允許的 event 集合）、`output`（一份符合 `ai-task-card-record` 的草稿 + `evidence_refs`（reference-only）+ `dry_run` 旗標）、`error_contract`（缺欄位 / 未知 event / 越權 各自明確訊息）、`authority`（`accepts_memory: false`、`writes_company_knowledge: false`、`fail_loud`、`human_acceptance_gate_position` 沿用 AIWR-01 允許集合）。純轉換、無 runtime 依賴。

## Root question

如何讓「單一 Skill 把任務事件轉成合規工作紀錄草稿、I/O 可驗、dry-run 可測、且 Skill 不取得 memory acceptance / canonical writer authority」變成可驗契約,而且沿用（不重定義）`SSP-298` 的 automated_step 契約與 `SSP-299` 的卡片格式？

## Traces to

- `規格/v0.1/ai-work-record-boundary.yaml`：`automated_step_contract`（`required_per_step`、`error_behavior_enum: [FAIL_LOUD]`、`fail_silent: forbidden`、`allowed_gate_positions`）、`authority_boundary.task_card`、`non_acceptance_authority`。
- `規格/v0.1/ai-task-card-record.yaml`：`fields`、`lifecycle_event_to_status`、`allowed_status_transitions`、`reconstruction`。
- `jira-tasks.json` 的 `JIRA-DRAFT-AIWR-003` acceptance / dod。
- 下游：`SSP-301`（Hook）、`SSP-302`（Loop）、`SSP-303`（Harness）、`SSP-305`（主管視圖）。
- Requirement IDs：spec 未定義 `US-*`/`FR-*`/`SC-*`；本卡以穩定 slice ID `SSP300-S01` 追溯。

## Dependencies / Blockers / Current frontier

- Dependencies：`SSP-298`（AIWR-01）= ACCEPTED_GO；`SSP-299`（AIWR-02）= ACCEPTED_GO。
- Blockers：無。
- Current frontier：`SSP300-S01`。

## Scope

- 新 `規格/v0.1/ai-work-record-skill.yaml`：`skill_id`、`purpose`、`input_contract`（`lifecycle_events` + `seed_fields`；events 必須是 AIWR-01 允許集合）、`output_contract`（`draft_card`（符合 `ai-task-card-record` fields）、`evidence_refs`（URN、reference-only）、`dry_run`（bool）、`replayed_status`（= lifecycle final））、`error_contract`（`MISSING_INPUT_FIELD` / `UNKNOWN_LIFECYCLE_EVENT` / `SKILL_EXCEEDS_AUTHORITY` 各自 message key）、`authority`（`accepts_memory: false`、`writes_company_knowledge: false`、`error_behavior: FAIL_LOUD`、`human_acceptance_gate_position ∈ allowed_gate_positions`）、`runtime_independence: true`、`cross_reference`（pointer binding 至 boundary 與 task-card-record spec）、`hard_stops`。
- `scripts/validate_ai_work_record_skill_contract.rb`（新薄 validator）：structural + `skill_transform_failure(input, output)` evaluator（純函式），交叉讀三份 yaml。
- 正負 fixtures。
- backlog 狀態更新。

## Constraints

- 不做 Hook / Loop / Harness / Hermes / runtime / connector / DB。
- 不重定義 `SSP-298` automated_step 契約或 `SSP-299` 卡片格式；引用並交叉驗證（pointer binding）。
- 不改既有 STD / EMEM / boundary / task-card-record 契約。
- validator 只做薄判斷；不新增 registry / FSM / 狀態機引擎。不新增 package dependency。推同 branch,不 merge。

## Product fit

- Measured gap：`SSP-298` 定義 automated step 的通用契約、`SSP-299` 定義卡片格式；沒有把「工作紀錄 Skill」這個單一轉換單位的 I/O、dry-run、error message、authority 限制寫成可驗。`SSP-301`（Hook）與 `SSP-305`（主管視圖）需要一個能被驗的 Skill 契約作為呼叫對象。
- Why not less：沒有 Skill 契約,Hook 與 Loop 會各自定義事件→草稿的轉換,重演格式分裂。
- Why not more：Hook 事件擷取、Loop 收口、Harness 編排、Hermes adapter 都不是本卡。
- Do not absorb：AI Core 的 skill 檔案結構、`ExecutionRequest`/`ExecutionReceipt` platform、provider registry、任何 runtime-native event normalization。
- Rollback：新 yaml + fixtures + 薄 validator,不連 runtime,可單獨 revert。

## Acceptance

1. `input_contract`：`lifecycle_events`（非空、每個 ∈ AIWR-01 允許 event 集合、第一個為 `start`）+ `seed_fields`（提供 `objective`/`scope`/`constraints`/`acceptance`）；缺任一 → `MISSING_INPUT_FIELD`；未知 event → `UNKNOWN_LIFECYCLE_EVENT`。
2. `output_contract`：`draft_card` 必須是 contract-valid 的 `ai-task-card-record`（重用 `SSP-299` evaluator 或等效檢查）；`evidence_refs` 全為 URN string 且 reference-only（不得內嵌內容）；`replayed_status` 必須等於 `lifecycle_events` 的 replay final。
3. `authority`：`accepts_memory: false`、`writes_company_knowledge: false`；output 帶 memory acceptance 欄位 / canonical write 欄位 / `writes_company_knowledge: true` → `SKILL_EXCEEDS_AUTHORITY`。
4. `error_behavior: FAIL_LOUD`；`fail_silent` 情境（error 但 output 仍宣稱成功）→ 拒。
5. `runtime_independence: true`：fixture 不含任何 runtime-specific 欄位仍可通過（純函式可測）。
6. `cross_reference`：pointer binding 至 `ai-work-record-boundary.yaml` 的 `automated_step_contract` / `non_acceptance_authority` 與 `ai-task-card-record.yaml` 的 `fields` / `lifecycle_event_to_status`；validator 鎖 pointer 字串 exact 且引用目標存在。
7. 負例至少：缺 seed field、未知 lifecycle event、`draft_card` 不合規、`evidence_refs` 內嵌內容、output 帶 memory acceptance 欄位、`replayed_status` 與 events 不符、fail-silent。
8. 每個負例單一 mutation + exact failure code；移除對應 enforcement → gate 轉紅。
9. `ruby scripts/validate_ai_work_record_skill_contract.rb`、`ruby scripts/validate_ai_task_card_record_contract.rb`（regression）、`ruby scripts/validate_ai_work_record_boundary_contract.rb`（regression）、personal-memory、STD schema engine、STD-00~03、cross-layer、JSON/YAML parse、`git diff --check` 全 PASS。

## Stop conditions

- 若要表達 Skill 契約必須改 `SSP-298` 或 `SSP-299` 的已鎖契約 → 停,回 Owner（可能先回對應 review line）。
- 若 Skill 轉換無法用純函式 + 資料表表達、需要狀態機引擎或 runtime → 停,回 Owner。
- 只有 P0/P1 阻塞 Lane B 後續（`SSP-301` 起）。

## Likely files

- `規格/v0.1/ai-work-record-skill.yaml`（新）
- `規格/v0.1/fixtures/ai-work-record-skill-positive-fixtures.json`（新）
- `規格/v0.1/fixtures/ai-work-record-skill-negative-fixtures.json`（新）
- `scripts/validate_ai_work_record_skill_contract.rb`（新）
- `文件/待辦補充-個人知識庫Harness-20260830.md` 或 AIWR backlog 段
- `.work/evidence/SSP300-WORK-RECORD-SKILL-20260909.md`

## Evidence

`.work/evidence/SSP300-WORK-RECORD-SKILL-20260909.md`
