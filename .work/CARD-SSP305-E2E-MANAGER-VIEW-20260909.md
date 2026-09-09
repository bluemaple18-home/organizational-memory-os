---
id: SSP305-E2E-MANAGER-VIEW-20260909
status: ACCEPTED_GO_20260909
type: implementation
jira: SSP-305
lane: B
tier: T1
---

# SSP-305｜AIWR-08 端到端驗收與主管進度視圖

👉 [假設與目標確認]
- 目標：定義一份 machine-readable「端到端驗收 + 主管視圖」契約：一個真實任務從
  start → update → complete/cancel 產出完整 lifecycle trace（每步帶 evidence receipt URN）；
  主管視圖只投影目標／狀態／阻塞／驗收摘要／證據連結，不複製敏感內容；失敗／取消／人工介入
  都有明確 manager-visible 狀態；`WorkRecord` 只有經 Candidate＋Acceptance 才可成 Personal
  Memory；主管可只靠 Jira 視圖重現進度判定。新 yaml + 新薄 validator + fixtures。
- 邊界：只封「端到端 trace 完整性 + manager-view 投影邊界 + 狀態完整性 + 記憶升格閘門 +
  可重現」契約；不做實際 Jira 寫入／connector／UI／runtime；不重定義 `SSP-298`～`SSP-304`
  的已鎖契約，全部 pointer 引用。這是 Lane B（AIWR 線）的匯流點。
- 驗收：見 Acceptance；DoD 要求端到端正向 + fail-closed 驗收完成，主管可從 Jira 重現進度。

## Objective

以 `SSP-299`（`ai-task-card-record` lifecycle）、`SSP-298`（boundary
`non_acceptance_authority` / `automated_step_contract`）、`SSP-301`～`SSP-304`
（Hook／Loop／Harness／Hermes）為對象，定義端到端驗收契約：

- `e2e_trace`：`lifecycle_trace[]` 每筆 `{event, evidence_receipt_ref}`；第一個 event 為
  `start`、最後一個為終止 event（`complete` / `cancel`）；每個 event ∈
  `ai-task-card-record.lifecycle_event_to_status` 的 key；`evidence_receipt_ref` 為 URN。
- `manager_view`：欄位剛好 `[objective, status, blockers, acceptance_summary, evidence_links]`；
  多欄 → `MANAGER_VIEW_LEAKS_FIELD`；`evidence_links` 全 URN（reference-only）；
  `sensitive_content_copied: true` 或帶 raw work body → `MANAGER_VIEW_LEAKS_CONTENT`。
- `status_completeness`：`final_status ∈ [DONE, FAILED, CANCELLED, BLOCKED, HUMAN_INTERVENTION]`；
  且與 trace 終止 event 對映一致（`complete → DONE`、`cancel → CANCELLED`）；否則 `E2E_STATUS_UNMAPPED`。
- `memory_promotion_gate`：`work_records[]` 任一筆 `personal_memory: true` 但缺 `candidate_ref`
  或 `acceptance_ref`（URN）→ `E2E_WORKRECORD_PROMOTED_WITHOUT_ACCEPTANCE`。
- `reconstruction`：`reconstructable_from_jira: true`；`manager_view` 須帶非空 `status` 與
  非空 `evidence_links`；否則 `MANAGER_VIEW_NOT_RECONSTRUCTABLE`。
- `authority`：`is_projection: true`、`performs_acceptance: false`、`is_canonical: false`；
  run 帶 acceptance / canonical write 欄位或宣稱越權 → `E2E_EXCEEDS_AUTHORITY`。
- `error_behavior: FAIL_LOUD`；`runtime_independence: true`；`cross_reference` pointer binding
  至 task-card-record／boundary／harness／hook／loop／skill spec；`hard_stops`：no Jira write／
  connector／UI／runtime；pure function + data tables；no canonical writer。

## Root question

如何讓「一個真實 AI 任務的端到端 trace 完整可驗、主管視圖只投影非敏感摘要、每種終止狀態
都有明確 manager 狀態、WorkRecord 不經 acceptance 不得成 Personal Memory、主管可只靠 Jira
重現進度」變成可驗契約,且不重定義 `SSP-298`～`SSP-304`?

## Traces to

- `規格/v0.1/ai-task-card-record.yaml`：`lifecycle_event_to_status`、`status_enum`。
- `規格/v0.1/ai-work-record-boundary.yaml`：`non_acceptance_authority`、`automated_step_contract`。
- `規格/v0.1/ai-work-record-{hook,loop,harness,hermes-adapter}.yaml`：被端到端串接的四個能力。
- `.work/JIRA-PERSONAL-MEMORY-20260907/jira-tasks.json` `JIRA-DRAFT-AIWR-008` acceptance / dod。
- `~/.claude/CLAUDE.md`：`PROJECTION_ONLY`（主管視圖不得取得 canonical authority）；
  「WorkRecord 只有經 Candidate／Acceptance 才可成為 Personal Memory」。
- Requirement IDs：spec 未定義 `US-*`/`FR-*`/`SC-*`；本卡以穩定 slice ID `SSP305-S01` 追溯。

## Dependencies / Blockers / Current frontier

- Dependencies：`SSP-299`／`SSP-300`／`SSP-301`／`SSP-302`／`SSP-303`／`SSP-304` = ACCEPTED_GO。
- Blockers：無。
- Current frontier：`SSP305-S01`。這是 Lane B（AIWR 線）最後一張。

## Scope

- 新 `規格/v0.1/ai-work-record-e2e-acceptance.yaml`：`schema`、`purpose`、`e2e_trace`、
  `manager_view`、`status_completeness`、`memory_promotion_gate`、`reconstruction`、`authority`、
  `error_contract`、`runtime_independence`、`cross_reference`、`hard_stops`、`required_negative_fixtures`。
- `scripts/validate_ai_work_record_e2e_acceptance_contract.rb`（新薄 validator）：structural +
  純函式 `e2e_acceptance_failure(run, lifecycle_events, manager_view_fields, manager_statuses)`；
  交叉讀 task-card-record／boundary／harness yaml；沿用 `scripts/lib/omos_contract_helpers.rb`。
- 正負 fixtures。
- backlog 狀態更新（Lane B DoD 判定）。

## Constraints

- 不做 Jira write／connector／UI／runtime。
- 不重定義 `SSP-298`～`SSP-304` 契約；pointer 引用並交叉驗證。
- 不改既有契約或 validator。
- validator 只做薄判斷；不新增 registry／FSM／狀態機引擎；不新增 package。推同 branch,不 merge。
- 檔案大小守 `.agentskills/docs/coding-standards.md` §2（validator `< 400`）。

## Product fit

- Measured gap：`SSP-298`～`SSP-304` 各層可驗,但沒有把「整條鏈跑完一個真實任務、主管能不看
  敏感內容就掌握進度、且不繞過 memory acceptance」寫成可驗端到端契約。這是 MVP 驗收判定所需。
- Why not less：沒有端到端契約,各層綠不代表整鏈綠;主管視圖的敏感內容邊界與 memory 升格閘門
  無處統一落地。
- Why not more：實際 Jira 欄位映射、connector、UI、runtime 都不是本卡。
- Do not absorb：Jira platform、任何 UI framework、runtime-native workflow orchestration。
- Rollback：新 yaml + fixtures + 薄 validator,不連 runtime,可單獨 revert。

## Acceptance

1. `e2e_trace.lifecycle_trace`：非空、第一個 event `start`、最後一個 ∈ `{complete, cancel}`、
   每個 event ∈ `lifecycle_event_to_status` key、每筆 `evidence_receipt_ref` 為 URN；
   缺 / 順序錯 → `E2E_TRACE_INCOMPLETE`；`evidence_receipt_ref` 非 URN → `E2E_RECEIPT_NOT_REF`。
2. `manager_view`：欄位集合剛好 `[objective, status, blockers, acceptance_summary,
   evidence_links]`；多欄 → `MANAGER_VIEW_LEAKS_FIELD`；`evidence_links` 全 URN、`blockers` /
   `acceptance_summary` 為文字摘要（非 URN 內容不限），`sensitive_content_copied: true` 或帶
   `raw_work_body` → `MANAGER_VIEW_LEAKS_CONTENT`；`evidence_links` 含非 URN → `MANAGER_VIEW_INLINE_CONTENT`。
3. `status_completeness`：`final_status ∈ [DONE, FAILED, CANCELLED, BLOCKED, HUMAN_INTERVENTION]`；
   trace 終止 event 為 `complete` 時 `final_status` 必須是 `DONE`、`cancel` 時必須是
   `CANCELLED`；不符 → `E2E_STATUS_UNMAPPED`。
4. `memory_promotion_gate`：`work_records[]` 某筆 `personal_memory: true` 但缺 `candidate_ref`
   或 `acceptance_ref`（URN）→ `E2E_WORKRECORD_PROMOTED_WITHOUT_ACCEPTANCE`。
5. `reconstruction`：`reconstructable_from_jira != true`、或 `manager_view` 缺非空 `status` /
   非空 `evidence_links` → `MANAGER_VIEW_NOT_RECONSTRUCTABLE`。
6. `authority`：`is_projection: true`、`performs_acceptance: false`、`is_canonical: false`；
   run 帶 `personal_acceptance_ref` / `canonical_write_receipt_ref` 等 forbidden 欄位或宣稱
   越權 → `E2E_EXCEEDS_AUTHORITY`。
7. `error_behavior: FAIL_LOUD`（與 boundary `error_behavior_enum` 交叉鎖）；run 有 `error` 但
   `ok != false` → `FAIL_SILENT`。
8. 最小 happy path（`start → submit_review → complete` trace，全帶 receipt URN、
   `manager_view` 五欄齊、`final_status: DONE`、`reconstructable_from_jira: true`、
   `work_records` 皆非 personal_memory 或帶完整 candidate＋acceptance）→ allow。
9. `cross_reference`：pointer binding 至 task-card-record／boundary／harness spec；validator 鎖
   pointer 字串 exact 且引用目標存在。
10. `runtime_independence: true`：fixture 不含 runtime-specific 欄位仍可通過。
11. 負例至少：trace 不以 start 起／trace 未收在終止 event／receipt 非 URN／manager_view 多欄／
    manager_view 帶敏感內容／evidence_links 非 URN／final_status 未對映 / 非法／WorkRecord 未經
    acceptance 卻宣稱 personal memory／不可重現／帶 canonical write 欄位／fail-silent。
12. 每個負例單一 mutation + exact failure code；移除對應 enforcement → gate 轉紅。
13. `ruby scripts/validate_ai_work_record_e2e_acceptance_contract.rb` +
    `validate_ai_work_record_{hermes_adapter,harness,loop,hook,skill}_contract.rb`（regression）+
    `validate_ai_task_card_record_contract.rb`（regression）+
    `validate_ai_work_record_boundary_contract.rb`（regression）+
    `validate_personal_memory_contract.rb`（aggregator regression）+ STD schema engine +
    STD-00~03 + cross-layer + JSON/YAML parse + `git diff --check` 全 PASS。

## Stop conditions

- 若要表達端到端契約必須改 `SSP-298`～`SSP-304` 的已鎖契約 → 停,回 Owner。
- 若端到端驗收無法用純函式 + 資料表表達、需要狀態機引擎或 runtime → 停,回 Owner。
- 本卡完成即 Lane B（AIWR 線）DoD 判定;有 P0/P1 阻塞 DoD。

## Likely files

- `規格/v0.1/ai-work-record-e2e-acceptance.yaml`（新）
- `規格/v0.1/fixtures/ai-work-record-e2e-acceptance-positive-fixtures.json`（新）
- `規格/v0.1/fixtures/ai-work-record-e2e-acceptance-negative-fixtures.json`（新）
- `scripts/validate_ai_work_record_e2e_acceptance_contract.rb`（新）
- `文件/待辦重整.md`（Lane B 進度 + DoD 判定）
- `.work/evidence/SSP305-E2E-MANAGER-VIEW-20260909.md`

## Evidence

`.work/evidence/SSP305-E2E-MANAGER-VIEW-20260909.md`
