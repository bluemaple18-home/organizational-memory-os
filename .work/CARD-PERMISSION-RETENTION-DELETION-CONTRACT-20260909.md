---
id: PERMISSION-RETENTION-DELETION-CONTRACT-20260909
status: BLOCKED_AWAITING_OWNER_SPEC_FREEZE
type: implementation
lane: A（repo 施工順序 #4 / SSP-294 前置）
tier: T2
---

# Permission / Retention / Deletion Contract（repo #4）

👉 [假設與目標確認]
- 目標：定義 `RawEvidenceEnvelope` 既有欄位 `permission_decision_ref` /
  `payload_retention_state` / `deletion_confirmation_ref` 的**狀態機與治理規則**：ACL delta
  傳遞、來源刪除 → payload 狀態轉換、retention tier、legal hold 覆蓋、projection / cache
  cleanup 的可驗契約。ENTERPRISE_GOVERNANCE / P0 / FIRST FRONTIER。
- 邊界：不新增 subsystem、不新增 registry / DB / writer；只在既有 STD-01 欄位上定義
  transition 契約 + 一個薄 validator。
- 驗收：待 Owner 簽凍結點後補。

## 為什麼 T2（先凍結 spec，Owner 簽核，再依 T1 實作）

依 `~/.claude/CLAUDE.md`：`FORBIDDEN_BY_DEFAULT: new ledger/registry/FSM/DB/writer`、
`OWNER_ONLY_CHANGES`、`PRODUCT_FIT_TRIGGER: governance / memory/lifecycle`。本卡定義
retention / deletion / legal-hold 的授權語意，屬 `DOMAIN_CORE / ENTERPRISE_GOVERNANCE`，
blast radius 觸及 STD-01 欄位的意義與所有下游投影。**CC 不自行開工。**

需 Owner 簽核的凍結點（`.work/CARD-...-SPEC-FREEZE.md` / 對應提案文件）：

1. **retention state machine**：`payload_retention_state` 的合法值集合與 transition
   （例如 `RETAINED → SCHEDULED_FOR_DELETION → DELETED` / `LEGAL_HOLD`），哪些 actor 能觸發。
2. **deletion 語意**：來源刪除 → `deletion_confirmation_ref` 何時必填、payload 是否
   tombstone、evidence identity 是否保留（推測應保留，只清 payload）——需 Owner 定。
3. **legal hold 覆蓋規則**：`legal_hold` 是否無條件擋 delete/purge（`ai-work-record` 系有
   `legal_hold_overrides_delete_and_purge: true` 先例，需確認一致）。
4. **ACL delta 傳遞**：`permission_decision_ref` 隨來源 ACL 變更如何更新，是否重新
   permission-before-retrieval。
5. **projection / cache cleanup**：deletion 後 downstream projection / retrieval index 的
   cleanup 是可驗要求還是 best-effort。

## Traces to

- `規格/v0.1/raw-evidence-envelope.schema.json`：`permission_decision_ref` /
  `payload_retention_state` / `deletion_confirmation_ref`（欄位已存在，語意未鎖）。
- `文件/待辦重整.md` 第二節「Permission / Retention / Deletion Contract | MISSING / DONOR_AVAILABLE
  | DOMAIN_CORE / ENTERPRISE_GOVERNANCE | P0 | FIRST FRONTIER」。
- `文件/最小核心重基準.md` §施工順序 #4。
- 六條 Truth Boundary（Permission-before-Retrieval / Managed Policy Floor）。
- 下游：`SSP-294`（EMEM-05 Promotion，其 retention / deletion 傳遞語意來源）。

## Dependencies / Blockers

- Dependencies：STD-01 = LOCKED。
- Blockers：**Owner 尚未簽凍結點（上述 5 項）**。在簽核前本卡不進 implement。

## Do not absorb / Constraints

- 不建 retention DB、deletion queue、legal-hold registry、新 writer。
- 不改 STD-01 欄位名（只定義其值域與 transition）。
- 實作階段沿用薄 validator + fixtures 模式；不引入狀態機引擎。

## 解除條件

Owner 簽核凍結文件後 → 本卡轉 `DRAFT_OWNER_REVIEW`，依 T1 迴圈實作
（新 `規格/v0.1/permission-retention-deletion.yaml` + `scripts/validate_permission_retention_deletion_contract.rb`
+ fixtures），走大 review。

## Likely files（解除後）

- `規格/v0.1/permission-retention-deletion.yaml`（新）
- `規格/v0.1/fixtures/permission-retention-deletion-*-fixtures.json`（新）
- `scripts/validate_permission_retention_deletion_contract.rb`（新）
- `.work/evidence/PERMISSION-RETENTION-DELETION-CONTRACT-<date>.md`
