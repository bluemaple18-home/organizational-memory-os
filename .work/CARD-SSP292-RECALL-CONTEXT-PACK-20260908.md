---
id: SSP292-RECALL-CONTEXT-PACK-20260908
status: DRAFT_OWNER_REVIEW
type: implementation
jira: SSP-292
lane: A
tier: T1
---

# SSP-292｜EMEM-03 Recall 與 MemoryContextPack

👉 [假設與目標確認]
- 目標：把 `personal-harness-integration.yaml` 現有的 `recall_context_pack`（僅 input/output 欄位清單 + 兩條 rule）與 `MemoryContextPack`（僅 purpose 一行）擴成可驗契約：request 契約、permission-before-retrieval 順序、輸出必含 gap/permission receipt、禁止「全庫搜尋後靠 prompt 防洩漏」。補正負 fixtures 與 validator 分支。
- 邊界：只封 recall/context-pack 契約與其 permission ordering；不做實際 retrieval engine、向量索引、context budget 演算法、LLM 呼叫。
- 驗收：見 Acceptance；未經獨立大 review 不得標 GO。

## Objective

以 EMEM-01（`SSP-289`）的 `PersonalMemoryRecord` 契約與 EMEM-00 的 scope/permission 語意為基礎，定義一次「取回適用、最新、有引用的個人記憶」的可驗契約：輸入（intent / requester / scope / ownership / visibility / context_budget）、permission 過濾必須在 retrieval 與任何模型看到資料之前完成（INTERSECTION 策略）、輸出必含 selected memory refs + source refs + freshness + `permission_decision_ref` + `omitted_or_gap_notice` + `budget_usage`。供 `SSP-295` pilot 的 recall 路徑引用。

## Root question

如何讓「permission-before-retrieval、bounded recall、過期/超預算要有明確 gap notice、不存在 search-all-then-prompt-guard 路徑」變成 machine-readable，而且每一條都有負例可證（合法 recall、被拒 recall、過期記憶、超預算省略、企圖全庫搜尋）？

## Traces to

- `規格/v0.1/personal-harness-integration.yaml`：`recall_context_pack`、`personal_memory_governance`、`contract_registry.define_for_employee_memory.MemoryContextPack`、`hard_stops`（`no search-all-personal-memory-before-permission`）、`core_invariants`（`PERSONAL_CANONICAL_MEMORY_IS_PERSONAL_SCOPE_ONLY`）。
- `文件/個人證據與工作紀錄.md`：Permission inheritance、Scope。
- `文件/上下文預算與檢索.md`：Context Budget / Bounded Retrieval / Permission-before-Retrieval。
- `jira-tasks.json` 的 `JIRA-DRAFT-EPM-005` acceptance / dod。
- 下游：`SSP-295`（EMEM-06 pilot）recall 路徑。
- Requirement IDs：spec 未定義 `US-*`/`FR-*`/`SC-*`；本卡以穩定 slice ID `SSP292-S01` 追溯。

## Dependencies / Blockers / Current frontier

- Dependencies：`SSP-289`（EMEM-01）= 完成；`SSP-290`（能力矩陣）= ACCEPTED_GO（recall 深度與 capability level 對齊時引用）。
- Blockers：無。
- Current frontier：`SSP292-S01`。

## Scope

- `recall_context_pack` 擴為可驗契約：`request` 必填欄位、`permission_ordering`（permission decision 必須先於 candidate set 構成）、`output` 必填欄位、`gap_notice_required_when`（stale / not-applicable / budget-omitted）、`forbidden`（`search_all_then_prompt_guard`、`unrestricted_global_personal_memory_search`）。
- `MemoryContextPack` resource 契約：identity、`request_ref`、`permission_decision_ref`、`selected_memory_refs`（必須全部 resolve 到 owner 一致或帶 `permission_intersection_ref` 的 `PersonalMemoryRecord`）、`source_refs`、`freshness`、`omitted_or_gap_notice`、`budget_usage`。
- 正負 fixtures 與 `scripts/validate_personal_memory_contract.rb` 對應分支（或視情況新增薄 `validate_recall_context_pack_contract.rb`；優先擴既有 validator）。
- backlog 狀態更新。

## Constraints

- 不做 retrieval / 向量 / rerank / context-budget 演算法 / LLM 呼叫 / connector / DB。
- 不改 EMEM-00 / 01 已鎖欄位、`core_invariants` 文字、`SSP-290` 已鎖 `capability_*` 區塊。
- validator 只做薄判斷；不新增 workflow engine / registry / FSM。
- 不新增 package dependency。repair/commit 推同 branch，不 merge。

## Product fit

- Measured gap：`recall_context_pack` 目前只是欄位清單 + 兩條字串 rule；`MemoryContextPack` 只有一行 purpose。沒有 request 契約、沒有 permission-ordering 斷言、沒有 gap-notice 條件、沒有「禁止 search-all-then-prompt-guard」的可驗表達。`SSP-295` pilot 需要一個能被驗的 recall 契約。
- Why not less：只留欄位清單無法擋「先把全部 personal memory 丟給模型再叫它別洩漏」或「回過期記憶但不標 freshness」。
- Why not more：真正的 retrieval / budget 演算法、多來源學習檢索都不是此 slice 的必要證據。
- Do not absorb：具體 vector store、GraphRAG engine、Codex context engineering runtime、SimpleMem/EvolveMem 的 online config 改寫。
- Rollback：新契約區塊 + validator 分支 + fixtures，不連 runtime，可單獨 revert。

## Acceptance

1. `request` 契約必填：`intent`、`requester_identity`、`requester_scope`、`ownership_mode`、`visibility_scope`、`context_budget`；缺任一 fail closed。
2. Permission ordering：`permission_decision_ref` 必須存在且其決策範圍 ≥ 所有 `selected_memory_refs`；不存在「先組 candidate set 再套 prompt 防洩漏」的合法路徑（負例被拒）。
3. `output` 必填：`selected_memory_refs`、`source_refs`、`applicability`、`freshness`、`permission_decision_ref`、`omitted_or_gap_notice`、`budget_usage`。
4. Gap notice：當有 stale / not-applicable / budget-omitted 記憶時，`omitted_or_gap_notice` 必須非空且標明原因；回過期記憶而不標 freshness → 拒。
5. `selected_memory_refs` 全部 resolve 到 `PersonalMemoryRecord`；跨 owner 者必須帶 `permission_intersection_ref`，且不得放寬 source ACL。
6. 負例至少：缺 request 欄位、permission decision 範圍小於 selected set、search-all-then-prompt-guard、過期記憶無 freshness、超預算但無 budget-omitted notice、跨 owner 無 intersection。
7. 每個負例單一主要 mutation + exact failure code；移除對應 enforcement 時 gate 轉紅。
8. `ruby scripts/validate_personal_memory_contract.rb`（含新分支）、STD schema engine、STD-00~03、cross-layer、JSON/YAML parse、`git diff --check` 全 PASS；`SSP-290` 已鎖斷言與 6 個必備 capability negative label 不 regress。

## Stop conditions

- 若要表達 recall 契約必須改 EMEM-00/01 已鎖欄位或 `core_invariants` 文字 → 停，回 Owner（升 T3）。
- 只有 P0/P1 阻塞 Lane A 後續。

## Likely files

- `規格/v0.1/personal-harness-integration.yaml`
- `規格/v0.1/fixtures/personal-memory-positive-fixtures.json`
- `規格/v0.1/fixtures/personal-memory-negative-fixtures.json`
- `scripts/validate_personal_memory_contract.rb`
- `文件/待辦補充-個人知識庫Harness-20260830.md`
- `.work/evidence/SSP292-RECALL-CONTEXT-PACK-20260908.md`

## Evidence

`.work/evidence/SSP292-RECALL-CONTEXT-PACK-20260908.md`
