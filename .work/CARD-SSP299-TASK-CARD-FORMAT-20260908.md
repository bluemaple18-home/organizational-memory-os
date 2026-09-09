---
id: SSP299-TASK-CARD-FORMAT-20260908
status: ACCEPTED_GO_20260909
type: implementation
jira: SSP-299
lane: B
tier: T1
---

# SSP-299｜AIWR-02 AI 任務卡自動紀錄格式

👉 [假設與目標確認]
- 目標：把 `SSP-298` 的 `authority_boundary.task_card`（只定義「不是 Personal Memory + 必含哪些控制欄位」）擴成完整、可驗的 Task Card 記錄格式：欄位級 schema、lifecycle 事件 → status 的確定性映射、缺必要欄位 fail closed、敏感內容只存 reference、可由一個真實任務重建同一張卡。
- 邊界：只封 Task Card 格式與事件映射；不做 Skill（`SSP-300`）、Hook（`SSP-301`）、Loop（`SSP-302`）、Harness（`SSP-303`）；不改升格路徑語意（那是 `SSP-298` 已封）。
- 驗收：見 Acceptance；DoD 要求正負 fixtures + validator 通過且真實任務可重建。

## Objective

以 `SSP-298` 的 `ai-work-record-boundary.yaml` `task_card` 邊界為基礎，定義一份 machine-readable 的 Task Card record 格式契約：`card_id` / `objective` / `scope` / `constraints` / `acceptance` / `status` / `evidence_refs` 的欄位型別與必填規則、`status` enum 與 `OPEN→BLOCKED→IN_REVIEW→DONE / CANCELLED` 的合法轉移、`start / block / complete / cancel` 事件到 status 的確定性映射、缺欄位或缺 evidence 時 fail closed（不得產生假 DONE）、敏感內容只存 reference。供 `SSP-300`（工作紀錄 Skill）與 `SSP-305`（主管視圖）引用。

## Root question

如何讓「每次 AI 任務都能重建出格式一致的卡片、事件到 status 映射確定、缺欄位不產生假完成、敏感內容不進卡片」變成可驗契約，而且沿用（不重定義）`SSP-298` 的 task_card 邊界與升格路徑？

## Traces to

- `規格/v0.1/ai-work-record-boundary.yaml`：`authority_boundary.task_card`（`SSP-298` 已封的 role / is_personal_memory / required_fields / status_enum / forbidden_fields / forbidden_authority / sensitive_content_rule）。
- `文件/待辦重整.md` 第五節（實作 card 必填欄位，作為 Task Card record 欄位對照）。
- `jira-tasks.json` 的 `JIRA-DRAFT-AIWR-002` acceptance / dod。
- 下游：`SSP-300`（AIWR-03 Skill）、`SSP-305`（AIWR-08 主管進度視圖）。
- Requirement IDs：spec 未定義 `US-*`/`FR-*`/`SC-*`；本卡以穩定 slice ID `SSP299-S01` 追溯。

## Dependencies / Blockers / Current frontier

- Dependencies：`SSP-298`（AIWR-01 邊界契約）= ACCEPTED_GO_20260908。
- Blockers：無。
- Current frontier：`SSP299-S01`。

## Scope

- 新 `規格/v0.1/ai-task-card-record.yaml`：`fields`（每欄型別、必填、format）、`status_enum` 與 `allowed_status_transitions`、`lifecycle_event_to_status`（`start→OPEN`、`block→BLOCKED`、`unblock→OPEN`、`submit_review→IN_REVIEW`、`complete→DONE`、`cancel→CANCELLED`）、`fail_closed_rules`（缺必填欄位 / `status: DONE` 但 `evidence_refs` 為空 / `acceptance` 為空 → 拒）、`sensitive_content_rule`（沿用 `reference_only_never_copied`）、`reconstruction`（同一事件序列必須產生同一張卡的 deterministic 說明）。
- 引用 `ai-work-record-boundary.yaml` 的 `task_card` 邊界並交叉驗證（`is_personal_memory: false`、`forbidden_fields`、`forbidden_authority` 與本卡 fields 一致，不重定義）。
- 正負 fixtures 與新薄 `scripts/validate_ai_task_card_record_contract.rb`。
- backlog 狀態更新。

## Constraints

- 不做 Skill / Hook / Loop / Harness / Hermes / runtime / connector / DB。
- 不重定義 `SSP-298` 的 task_card 邊界或升格路徑；只擴欄位級格式與事件映射。
- 不改 EMEM / STD 既有契約。
- validator 只做薄判斷；不新增 workflow engine / registry / FSM / 狀態機引擎（`allowed_status_transitions` 是資料表，不是引擎）。
- 不新增 package dependency。推同 branch，不 merge。

## Product fit

- Measured gap：`SSP-298` 只定義 task_card 是什麼、不是什麼、必含哪些欄位；沒有欄位型別、沒有事件→status 映射、沒有「缺欄位 / 假 DONE」的 fail-closed 規則、沒有 deterministic 重建說明。`SSP-300` 的 Skill 與 `SSP-305` 的主管視圖需要一個能被驗的欄位級格式。
- Why not less：只留邊界契約，`SSP-300` 會自行定義欄位型別與事件映射，重演格式分裂與假完成。
- Why not more：Skill 轉換邏輯、Hook 事件擷取、Loop 收口、主管視圖 render 都不是本卡。
- Do not absorb：AI Core 的 task card frontmatter schema 實作、ExecutionRequest/Receipt platform、runtime-native event normalization、provider registry。
- Rollback：新 yaml + fixtures + 薄 validator，不連 runtime，可單獨 revert。

## Acceptance

1. `fields`：`card_id`（URN）、`objective` / `scope` / `constraints` / `acceptance`（非空字串或結構）、`status`（enum）、`evidence_refs`（URN 陣列）的型別與必填規則可驗。
2. `allowed_status_transitions`：`OPEN→{BLOCKED, IN_REVIEW, CANCELLED}`、`BLOCKED→{OPEN, CANCELLED}`、`IN_REVIEW→{OPEN, DONE, CANCELLED}`、`DONE→{}`、`CANCELLED→{}`（exact，validator 鎖定）。
3. `lifecycle_event_to_status`：6 個事件的確定性映射，validator 鎖 exact map。
4. `fail_closed_rules`：缺任一必填欄位 → 拒；`status: DONE` 但 `evidence_refs` 空或 `acceptance` 空 → 拒（不得假完成）；非法 status 轉移 → 拒。
5. 敏感內容只存 reference：帶 `sensitive_content_copied: true` 或把 `forbidden_fields`（`SSP-298` 已封）塞進卡片 → 拒。
6. `reconstruction`：同一 `lifecycle_events` 序列輸入必須 deterministic 產生同一張卡（validator 以 fixture 證明至少一個真實任務事件序列可重建）。
7. 與 `ai-work-record-boundary.yaml` `task_card` 交叉一致：`is_personal_memory`、`status_enum`、`forbidden_fields`、`forbidden_authority` 不得分歧（validator 交叉讀兩份 yaml 斷言）。
8. 負例至少：缺必填欄位、假 DONE（無 evidence）、非法 status 轉移、事件映射被竄改、敏感內容複製、與邊界契約 status_enum 分歧。
9. 每個負例單一 mutation + exact failure code；移除對應 enforcement → gate 轉紅。
10. `ruby scripts/validate_ai_task_card_record_contract.rb`、`ruby scripts/validate_ai_work_record_boundary_contract.rb`（regression）、personal-memory、STD schema engine、STD-00~03、cross-layer、JSON/YAML parse、`git diff --check` 全 PASS。

## Stop conditions

- 若要表達欄位格式必須改 `SSP-298` 的 task_card 邊界 → 停，回 Owner（可能要先回 `SSP-298` repair line）。
- 若事件→status 映射無法用資料表表達、需要狀態機引擎 → 停，回 Owner。
- 只有 P0/P1 阻塞 Lane B 後續。

## Likely files

- `規格/v0.1/ai-task-card-record.yaml`（新）
- `規格/v0.1/fixtures/ai-task-card-record-positive-fixtures.json`（新）
- `規格/v0.1/fixtures/ai-task-card-record-negative-fixtures.json`（新）
- `scripts/validate_ai_task_card_record_contract.rb`（新）
- `文件/待辦補充-個人知識庫Harness-20260830.md` 或 AIWR backlog 段
- `.work/evidence/SSP299-TASK-CARD-FORMAT-20260908.md`

## Evidence

`.work/evidence/SSP299-TASK-CARD-FORMAT-20260908.md`
