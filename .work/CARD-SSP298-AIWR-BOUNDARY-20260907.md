---
id: SSP298-AIWR-BOUNDARY-20260907
status: IMPLEMENTED_AWAITING_BIG_REVIEW
type: implementation
jira: SSP-298
lane: B
tier: T1
---

# SSP-298｜AIWR-01 鎖定 AI 工作紀錄與 Personal Memory 邊界

👉 [假設與目標確認]
- 目標：定義 Task Card、WorkRecord、Evidence、PersonalMemoryCandidate 四者的邊界契約，證明 runtime 狀態不會被自動升為長期個人記憶，且不新增第二套 workflow authority。
- 邊界：只封邊界契約本身；不做 Task Card 完整 frontmatter schema（`SSP-299`）、Skill（`SSP-300`）、Hook（`SSP-301`）、Loop（`SSP-302`）、Harness（`SSP-303`）、Hermes（`SSP-304`）。
- 驗收：見下方 Acceptance；DoD 要求邊界契約與負例獲 Owner 接受。

## Objective

作為 Lane B（`SSP-287` AI 工作紀錄自動化執行層）的第一張卡，把 `runtime_policy` 與 `not_long_lived_memory_by_default` 這兩組原則，落成一份針對 AIWR 專有物件（Task Card、WorkRecord）與既有 Evidence / Candidate 關係的可驗契約，並固定「自動步驟的 input / output / error / human-gate」語意。後續 `SSP-299`～`SSP-305` 全部引用本契約，不各自定義升格語意。

## Root question

AI 任務過程產生的 Task Card、WorkRecord、Evidence、Memory Candidate，彼此邊界在哪？如何證明 branch / worktree / runtime done / model confidence 不具 acceptance authority、runtime 狀態不會被自動升為長期記憶，又不新增第二套 workflow authority？

## Traces to

- `規格/v0.1/personal-harness-integration.yaml`：`runtime_policy`（`executor_authority_over_memory: false`）、`not_long_lived_memory_by_default`、`core_invariants`（`WORK_RECORD_NE_PERSONAL_MEMORY`、`CAPTURED_NE_REMEMBERED`、`MODEL_CONFIDENCE_NE_VERIFICATION`、`CANDIDATE_NE_ACCEPTED_PERSONAL_MEMORY`）、`work_record`、`core_pipeline`。
- `文件/待辦補充-個人知識庫Harness-20260830.md` 第 12 節（Reclassified previous work：Task Card frontmatter schema、ExecutionRequest / Receipt platform、provider registry 等已明確移出員工記憶主線）、第 13 節 Hard stops。
- `文件/個人證據與工作紀錄.md`：「Work Record 不是 Knowledge」、Closeout。
- `jira-tasks.json` 的 `JIRA-DRAFT-AIWR-001` acceptance / dod。
- Requirement IDs：原 spec 未定義 `US-*` / `FR-*` / `SC-*`；本卡以穩定 slice ID `SSP298-S01` 追溯上述節點。

## Dependencies / Blockers / Current frontier

- Dependencies：無（`jira-tasks.json` 的 `depends_on: []`）。可與 Lane A 並行。
- Blockers：無。
- Current frontier：`SSP298-S01`。

## Scope

- 新增 `規格/v0.1/ai-work-record-boundary.yaml`（邊界契約），重用既有 contract registry，不新增 Evidence / Permission / Knowledge 資源族。
- `TaskCard` 契約：定位為 work control / report artifact，`is_personal_memory: false`，必填 `objective` / `scope` / `constraints` / `acceptance` / `status` / `evidence_refs`；禁帶 memory acceptance 欄位；敏感內容只存 reference。
- `WorkRecord` 契約：沿用既有 `work_record`（`REBUILDABLE_PROJECTION`、answers what happened、`may_generate_candidates: 0..N`），不得攜帶 acceptance / canonical authority。
- 升格路徑：`TaskCard | WorkRecord → RawEvidenceEnvelope → PersonalMemoryCandidate → verification + personal acceptance → PersonalMemoryRecord`。
- `non_acceptance_authority` 清單：`branch`、`worktree`、`runtime_completion`、`model_confidence`。
- `automated_step_contract`：每個自動步驟的 input schema、output schema、error 行為（fail loud）、human acceptance gate 位置、dry-run 能力。
- 正負 fixtures 與 `scripts/validate_ai_work_record_boundary_contract.rb`。
- backlog 狀態更新。

## Constraints

- 不新增 workflow engine、registry、FSM、DB、canonical writer、第二套 runtime。validator 只做薄判斷。
- 不定義 Task Card 完整 frontmatter schema（`SSP-299`）；本卡只定義「Task Card 不是 Personal Memory、必含哪些控制欄位」。
- 不做 Hook / Loop / Harness / Hermes / connector。
- 不改 EMEM-00 / EMEM-01 已鎖契約、`core_invariants` 文字、六條 Truth Boundary。
- 不吸收 AI Core 的 task card frontmatter schema、ExecutionRequest / ExecutionReceipt platform、runtime-native event normalization、provider registry。
- 不新增 package dependency。不 merge / push。

## Product fit

- Measured gap：AIWR 線（`SSP-299`～`SSP-305`）全部依賴一個明確邊界契約。目前 `not_long_lived_memory_by_default` 與 `runtime_policy` 是原則清單，沒有把 TaskCard / WorkRecord 這兩個 AIWR 專有物件與 Evidence / Candidate 的關係、以及自動步驟的 I/O / error / human-gate 契約寫成可驗。
- Why not less：沒有邊界契約，`SSP-299` 的任務卡格式與 `SSP-300` 的 Skill 會各自定義升格語意，重演 WorkRecord 與 memory 混用。
- Why not more：Hook（`SSP-301`）、Loop（`SSP-302`）、Harness（`SSP-303`）、Hermes（`SSP-304`）、Task Card 完整 schema（`SSP-299`）都不是本卡；不建 registry / FSM / DB。
- Do not absorb：AI Core task card frontmatter schema、ExecutionRequest / Receipt platform、runtime-native event normalization、global hook、provider registry / interface、Hermes / DeepSeek Harness adapter（`文件/待辦補充-個人知識庫Harness-20260830.md` 第 12 節已列為移出項）。
- Rollback：新 yaml＋fixtures＋validator，不連 runtime，可單獨 revert。

## Acceptance

1. `TaskCard` 契約：定義為 work control / report artifact，`is_personal_memory: false`，必填 `objective` / `scope` / `constraints` / `acceptance` / `status` / `evidence_refs`；禁帶任何 memory acceptance 欄位；敏感內容只存 reference 不複製。
2. `WorkRecord` 契約沿用既有 `work_record`：`REBUILDABLE_PROJECTION`、answers what happened、`may_generate_candidates: 0..N`；不得攜帶 acceptance / canonical authority。
3. 升格路徑固定為 `TaskCard | WorkRecord → RawEvidenceEnvelope → PersonalMemoryCandidate → verification + personal acceptance`；跳過 Evidence、或由 TaskCard 直接建 `PersonalMemoryRecord` 被拒。
4. `non_acceptance_authority` 清單（`branch`、`worktree`、`runtime_completion`、`model_confidence`）明確不具 verification / acceptance authority；對應負例被拒。
5. `automated_step_contract`：每個自動步驟具 input schema、output schema、fail-loud error 行為、human acceptance gate 位置、dry-run 能力；缺 human gate 或 fail-silent 被拒。
6. 負例至少覆蓋：`CURRENT_TASK_STATUS` 升為 long-lived memory、`TEMPORARY_BRANCH_OR_WORKTREE_STATE` 升為 memory、`RUNTIME_COMPLETION_MESSAGE` 當 accepted、`model_confidence` auto-accept candidate、TaskCard 直接建 Record 跳過 Evidence、自動步驟繞過 human gate、TaskCard 帶 memory acceptance 欄位。
7. 契約不新增 workflow engine / registry / FSM；`scripts/validate_ai_work_record_boundary_contract.rb` 只做薄判斷。
8. `ruby scripts/validate_ai_work_record_boundary_contract.rb`、`ruby scripts/validate_personal_memory_contract.rb`、`uv run --script scripts/validate_std_schema_engine.py`、JSON / YAML parse、`git diff --check` 全數 PASS。
9. backlog 狀態只在證據完整後改 `READY_FOR_REVIEW`；DoD 的「邊界契約與負例獲 Owner 接受」在獨立 review `GO` 後由 Owner 明示。

## TDD / checkpoint

- RED：先加一個「TaskCard 直接建 Record」負例，證明尚無 validator 認得此邊界。
- GREEN：最少 yaml＋validator 使升格路徑正例與該負例通過。
- Checkpoint A：`TaskCard` / `WorkRecord` 契約與升格路徑正負例通過。
- Checkpoint B：`non_acceptance_authority`、`automated_step_contract` 負例與 personal-memory regression 通過。

## Stop conditions

- 若實作發現必須修改一條已鎖 `core_invariants` 或六條 Truth Boundary → 停在 `SSP298-S01`，回 Owner（升 T3）。
- 若邊界契約無法在不新增 workflow engine / registry 的前提下表達 → 停，回 Owner。
- 只有 P0 / P1 阻塞 Lane B 後續；P2 / P3 留 backlog。

## Likely files

- `規格/v0.1/ai-work-record-boundary.yaml`（新）
- `規格/v0.1/fixtures/ai-work-record-boundary-positive-fixtures.json`（新）
- `規格/v0.1/fixtures/ai-work-record-boundary-negative-fixtures.json`（新）
- `scripts/validate_ai_work_record_boundary_contract.rb`（新）
- `文件/待辦補充-個人知識庫Harness-20260830.md` 或新 AIWR backlog 段
- `文件/待辦重整.md`
- `.work/evidence/SSP298-AIWR-BOUNDARY-20260907.md`

## Evidence

`.work/evidence/SSP298-AIWR-BOUNDARY-20260907.md`（實作開始後建立）
