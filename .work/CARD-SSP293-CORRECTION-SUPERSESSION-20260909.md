---
id: SSP293-CORRECTION-SUPERSESSION-20260909
status: DRAFT_OWNER_REVIEW
type: implementation
jira: SSP-293
lane: A
tier: T1
---

# SSP-293｜EMEM-04 Correction 與 Supersession

👉 [假設與目標確認]
- 目標：把 `personal-harness-integration.yaml` 現有的 `correction_flow`（僅 steps 清單 + `history_erasure: forbidden`）與 `MemoryCorrectionProposal` / `MemorySupersessionReceipt`（各一行 purpose）擴成可驗契約：correction 由 Evidence + Proposal 啟動、Amend/Invalidate/Supersede 有明確狀態與 receipt、舊 Record 不原地覆寫、修正前必過 verification + acceptance。補正負 fixtures 與 validator 分支。
- 邊界：只封 correction / supersession 契約與其歷史追溯不變性；不做實際 diff 演算法、conflict 自動判定、UI。
- 驗收：見 Acceptance；未經獨立大 review 不得標 GO。

## Objective

以 EMEM-01（`SSP-289`）的 `PersonalMemoryRecord` lifecycle（`ACTIVE → {SUPERSEDED, INVALIDATED, ARCHIVED}`）與 `SSP-292` 的 verification/acceptance 語意為基礎，定義修正一筆個人記憶的可驗契約：`MemoryCorrectionProposal`（由 correction evidence 啟動、帶 target record ref、correction kind）、`MemorySupersessionReceipt`（immutable，記錄 amend/invalidate/supersede 決定、old→new record ref、verification + acceptance ref）。歷史不得被抹除；舊 Record 只轉狀態，不原地改內容。供 `SSP-295` pilot 的 correction 路徑引用。

## Root question

如何讓「correction 必須由 Evidence + Proposal 啟動、修正前必過 verification + acceptance、舊 Record 不原地覆寫、supersession receipt immutable、history erasure forbidden」變成 machine-readable，而且每一條有負例可證（合法 amend / 合法 supersede / 缺 evidence / 跳過 acceptance / 原地覆寫 / 抹除歷史）？

## Traces to

- `規格/v0.1/personal-harness-integration.yaml`：`correction_flow`、`contract_registry.define_for_employee_memory.{MemoryCorrectionProposal, MemorySupersessionReceipt}`、`core_invariants`（`CORRECTION_CREATES_REVISION_NOT_HISTORY_ERASURE`）、`personal_memory_resource_contracts.resources.PersonalMemoryRecord.lifecycle`、`hard_stops`（`no correction history erasure`）。
- `文件/個人證據與工作紀錄.md`、`文件/驗證治理.md`。
- `jira-tasks.json` 的 `JIRA-DRAFT-EPM-006` acceptance / dod。
- 下游：`SSP-295`（EMEM-06 pilot）correction 路徑。
- Requirement IDs：spec 未定義 `US-*`/`FR-*`/`SC-*`；本卡以穩定 slice ID `SSP293-S01` 追溯。

## Dependencies / Blockers / Current frontier

- Dependencies：`SSP-289`（EMEM-01）= 完成；`SSP-292`（Recall/verification 語意）= ACCEPTED_GO。
- Blockers：無。
- Current frontier：`SSP293-S01`。

## Scope

- `correction_flow` 擴為可驗契約：`proposal_required_fields`、`supersession_receipt_required_fields`、`correction_kinds`（`AMEND` / `INVALIDATE` / `SUPERSEDE`）與各自對 target record 的 lifecycle 轉移映射、`gate`（proposal → verify(PASS) → accept(ACCEPTED) → receipt）、`forbidden`（`history_erasure`、`in_place_record_overwrite`、`skip_verification`、`skip_acceptance`、`receipt_mutation`）。
- `MemoryCorrectionProposal` / `MemorySupersessionReceipt` resource 契約（identity URN、target refs、evidence/proposal/verification/acceptance refs、old→new record ref、immutable 標記）。
- 正負 fixtures 與 `scripts/validate_personal_memory_contract.rb` 對應分支。
- backlog 狀態更新。

## Constraints

- 不做 diff 演算法、conflict 自動判定、runtime / connector / DB / UI。
- 不改 EMEM-00/01 已鎖欄位、`SSP-290` `capability_*`、`SSP-292` `recall_context_pack.contract`、`core_invariants` 文字。
- validator 只做薄判斷；不新增 workflow engine / registry / FSM（correction_kind → lifecycle 映射是資料表）。
- 不新增 package dependency。推同 branch，不 merge。

## Product fit

- Measured gap：`correction_flow` 目前只是 5 步清單 + 一條 forbidden；兩個 resource 只有一行 purpose。沒有 proposal / receipt 欄位契約、沒有 correction_kind → lifecycle 映射、沒有「舊 Record 不原地覆寫 / receipt immutable」可驗表達。`SSP-295` pilot 需要能被驗的 correction 契約。
- Why not less：只留步驟清單無法擋「直接改 ACTIVE Record 的 content 欄位」或「supersede 但不留 receipt / 不過 acceptance」。
- Why not more：語意 diff、conflict interpretation、自動 correction 建議都不是此 slice 的必要證據。
- Do not absorb：EvolveMem 的 online config 改寫、任何自動改 production 記憶的路徑（`core_invariants` 已禁 model-confidence auto-acceptance）。
- Rollback：新契約區塊 + validator 分支 + fixtures，不連 runtime，可單獨 revert。

## Acceptance

1. `MemoryCorrectionProposal` 必含：`proposal_id`（URN）、`target_record_ref`、`correction_kind`、`correction_evidence_refs`（≥1）、`proposed_by`、`chronology.created_at`；缺任一 fail closed。
2. `correction_kind` ∈ `{AMEND, INVALIDATE, SUPERSEDE}`；各自對 target `PersonalMemoryRecord` 的合法 lifecycle 目標鎖定（`AMEND`/`SUPERSEDE` → `SUPERSEDED`；`INVALIDATE` → `INVALIDATED`），validator 鎖 exact 映射。
3. Gate：`MemorySupersessionReceipt` 生效必須帶 `verification_status = PASS` + `verification_receipt_ref` + `personal_acceptance_ref`；缺任一或 status 非 PASS → 拒。
4. 舊 Record 不原地覆寫：receipt 帶 `old_record_ref` 與（SUPERSEDE 時）`new_record_ref`，且 `new_record_ref != old_record_ref`；帶 `in_place_content_patch` 之類欄位 → 拒。
5. `MemorySupersessionReceipt` immutable：帶 `mutated` / `superseded_by` 之類事後改寫欄位 → 拒；`history_erasure: true` 或缺 `old_record_ref` → 拒。
6. 負例至少：缺 correction evidence、跳過 verification、跳過 acceptance、原地覆寫 ACTIVE record、抹除歷史（無 old_record_ref）、correction_kind 對應錯誤 lifecycle 目標、receipt 事後被改寫。
7. 每個負例單一 mutation + exact failure code；移除對應 enforcement → gate 轉紅。
8. `ruby scripts/validate_personal_memory_contract.rb`（含新分支）、STD schema engine、STD-00~03、cross-layer、JSON/YAML parse、`git diff --check` 全 PASS；`SSP-290` capability 與 `SSP-292` recall 斷言/label 不 regress。

## Stop conditions

- 若要表達 correction 契約必須改 EMEM-00/01 已鎖欄位或 `core_invariants` 文字 → 停，回 Owner（升 T3）。
- 只有 P0/P1 阻塞 Lane A 後續（`SSP-294` 起）。

## Likely files

- `規格/v0.1/personal-harness-integration.yaml`
- `scripts/validate_personal_memory_contract.rb`
- `規格/v0.1/fixtures/personal-memory-positive-fixtures.json`
- `規格/v0.1/fixtures/personal-memory-negative-fixtures.json`
- `文件/待辦補充-個人知識庫Harness-20260830.md`
- `.work/evidence/SSP293-CORRECTION-SUPERSESSION-20260909.md`

## Evidence

`.work/evidence/SSP293-CORRECTION-SUPERSESSION-20260909.md`
