---
id: SSP290-PERSONAL-KNOWLEDGE-LEVELS-20260907
status: DRAFT_OWNER_REVIEW
type: implementation
jira: SSP-290
lane: A
tier: T1
---

# SSP-290｜Personal Knowledge L1～L4 能力等級契約

👉 [假設與目標確認]
- 目標：把 `personal-harness-integration.yaml` 現有的 `capability_levels`（僅 name＋behavior 清單）擴成 machine-readable 能力矩陣，含合法升降級路徑，以及「降級不得移除的安全底線」不變性，並補正負 fixtures 與 validator 分支。
- 邊界：只動 employee personal memory 共用契約的 level 表達；不做 per-tenant / per-scope override 機制（那是 `SSP-296` / EMEM-07），不做 runtime enforcement，不做 UI。
- 驗收：見下方 Acceptance；未經獨立大 review 不得標 GO / LOCKED。

## Objective

以已鎖定的 EMEM-00 / EMEM-01 契約（`SSP-288` / `SSP-289`）為基礎，定義 Personal Knowledge 能力的 L1～L4 深度契約：每一級解鎖的自動化能力、合法升級與降級路徑、以及在任一級都必須成立的 safety floor。輸出一份可由 `scripts/validate_personal_memory_contract.rb` 驗證的能力矩陣，供 `SSP-291`（EMEM-02 Personal Evidence Profile）的 `capability_level` 欄位引用。

## Root question

能力等級目前只是行為敘述清單。如何讓「L1～L4 的能力授予、合法升降級、以及降級不得移除的 Permission / Provenance / Canonical Single Writer / L4 authority gate 安全底線」變成 machine-readable，而且每一條都有負例可證？

## Traces to

- `規格/v0.1/personal-harness-integration.yaml`：`capability_levels`、`core_invariants`、`promotion_widening_gate`、`hard_stops`。
- `文件/SaaS能力等級.md`：統一 Level 語言（L1 基礎 / L2 自動化 / L3 智慧化 / L4 自治化）、Personal Knowledge Capability 範例、「不可做付費牆的 Safety Floor」。
- `文件/待辦補充-個人知識庫Harness-20260830.md` 第 2 節 backlog registry。
- `文件/待辦重整.md` 第五節必填欄位。
- 下游：`SSP-291`（EMEM-02）`employee_memory_profile_minimum.memory_policy.capability_level`。
- Requirement IDs：原 spec 未定義 `US-*` / `FR-*` / `SC-*`；本卡以穩定 slice ID `SSP290-S01` 追溯上述節點，空白不當完成證明。

## Dependencies / Blockers / Current frontier

- Dependencies：`SSP-288`（EMEM-00）、`SSP-289`（EMEM-01）= 已完成（Jira 狀態「完成」）。
- Blockers：無。
- Current frontier：`SSP290-S01`。

## Scope

- `capability_levels` 擴為 `capability_matrix`：每級對應一組具名 capability grant（capture、ingestion、dedup/version/ACL、candidate queue、cross-source linking、conflict/freshness/gap hint、context-aware recall、promotion hint、active correction/promotion proposal、projection rebuild）。
- `level_transitions`：合法升級與降級路徑，以及非法跳躍 / 未授權轉換的拒絕規則。
- `capability_safety_floor`：任一 level 都成立的不變項清單，與「降級不得移除」的斷言。
- 正負 fixtures 與 `validate_personal_memory_contract.rb` 對應分支。
- backlog 狀態更新。

## Constraints

- 不新增 feature-flag 系統、entitlement service、billing 或第二套 workflow engine。
- 不改 EMEM-00 / EMEM-01 已鎖欄位、lifecycle、`core_invariants` 文字。
- 不做 `SSP-296` 的 per-role / per-tenant override，不做 runtime / connector / DB。
- 不新增 package dependency。不 merge / push。
- schema 與 imperative validator 各自責任都要有負例與 expected metadata，不得用無關 rejection 假裝 coverage。

## Product fit

- Measured gap：`capability_levels` 目前只是 name＋behavior 字串，validator 只確認四級鍵存在（`EXPECTED_CAPABILITY_LEVELS` / `EXPECTED_CAPABILITY_KEYS`）。沒有能力矩陣、沒有升降級規則、沒有 safety-floor 不變性。`SSP-291` 的 profile 需要引用一個真的能被驗的 level 契約。
- Why not less：只留行為清單無法擋「L1 profile 宣稱擁有 L3 跨來源關聯」或「降級把 Permission-before-Retrieval floor 拿掉」。
- Why not more：per-tenant / per-scope override、runtime enforcement、UI slider 都不是此 slice 的必要證據。
- Do not absorb：OpenFGA / OPA / Cerbos entitlement 模型、任何 billing / plan gating 系統、AI Core 的 capability vector。
- Rollback：`capability_matrix` / `level_transitions` / `capability_safety_floor` 是 yaml 內新增區塊＋validator 新增分支，可單獨 revert，不連 runtime。

## Acceptance

1. L1～L4 各自的能力授予以 machine-readable 矩陣表達：
   - L1：manual evidence capture / marking、candidate generation、employee confirmation、basic recall with citation。
   - L2：automatic source ingestion、deterministic dedup / version / ACL / retention、automatic candidate queue；candidate 仍待確認。
   - L3：cross-source object linking、WorkRecord correlation、conflict / freshness / gap suggestion、context-aware recall、promotion suggestion。
   - L4：continuous stale / conflict / gap monitoring、correction 與 promotion proposal、projection rebuild 與 regression evaluation；`authority_gate_required: true`。
2. 合法升級與降級路徑明確；非法跳躍或未授權轉換被拒。
3. Safety floor 在任一 level 都成立且降級不得移除：Permission-before-Retrieval、Provenance、Canonical Single Writer、L4 動作的 authority gate、`promotion_widening_gate` 的 forbidden 清單。
4. 負例至少覆蓋：某 level 宣稱超出該級的 capability grant、降級 fixture 移除任一 safety-floor 項、L4 auto-accept / auto-promote 未過 authority gate、profile 引用不存在的 level、`same_contract_all_levels` 被違反（不同 level 用不同 lifecycle）。
5. 每個負例為單一主要 mutation，具 expected failure code / path；移除對應 enforcement 時 gate 必須轉紅。
6. `ruby scripts/validate_personal_memory_contract.rb`、`uv run --script scripts/validate_std_schema_engine.py`、STD-00～03 與 cross-layer validator、JSON / YAML parse、`git diff --check` 全數 PASS。
7. backlog（`文件/待辦補充-個人知識庫Harness-20260830.md`、`規格/v0.1/personal-harness-integration.yaml` 的 `backlog`）只在證據完整後改 `READY_FOR_REVIEW`；未經獨立 review 不得標 `GO` / `LOCKED`。

## TDD / checkpoint

- RED：先加一個 L1-claims-L3 負例，證明現有 validator 不知道能力矩陣。
- GREEN：最少矩陣＋validator 分支使當前垂直路徑通過。
- Checkpoint A：`capability_matrix` 與 per-level 正例、超權負例通過。
- Checkpoint B：`level_transitions`、`capability_safety_floor` 降級負例與全量 regression 通過。

## Stop conditions

- 若要表達能力矩陣必須修改 EMEM-00 / EMEM-01 已鎖欄位或 `core_invariants` 文字 → 停在 `SSP290-S01`，回 Owner（升 T3）。
- 只有 P0 / P1 阻塞 Lane A 後續；P2 / P3 留 backlog。

## Likely files

- `規格/v0.1/personal-harness-integration.yaml`
- `規格/v0.1/fixtures/personal-memory-positive-fixtures.json`
- `規格/v0.1/fixtures/personal-memory-negative-fixtures.json`
- `scripts/validate_personal_memory_contract.rb`
- `文件/待辦補充-個人知識庫Harness-20260830.md`
- `文件/待辦重整.md`
- `.work/evidence/SSP290-PERSONAL-KNOWLEDGE-LEVELS-20260907.md`

## Evidence

`.work/evidence/SSP290-PERSONAL-KNOWLEDGE-LEVELS-20260907.md`（實作開始後建立）
