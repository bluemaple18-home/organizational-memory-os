---
id: PERMISSION-RETENTION-DELETION-SPEC-FREEZE-20260916
status: AWAITING_OWNER_SIGNATURE
type: spec_freeze
tier: T2
implements_card: CARD-PERMISSION-RETENTION-DELETION-CONTRACT-20260909
jira: SSP-294 前置（repo #4）
---

# repo #4 Permission / Retention / Deletion — Owner 凍結點

👉 [假設與目標確認]
- 目標：把 `CARD-PERMISSION-RETENTION-DELETION-CONTRACT-20260909` 卡了
  很久的五個凍結點，變成可以用字母簽掉的具體選項。
- 邊界：本卡**只做決策收斂**，不實作。簽核後另開 T1 closeout 卡。
- 驗收：Owner 簽五個字母。

## 研究結論（縮小了決策範圍，先讀這段）

1. **`payload_retention_state` 的值集合已經鎖在 STD-01**（
   `raw-evidence-envelope.schema.json`）：
   `RETAINED / LEGAL_HOLD / RETENTION_EXPIRED / TOMBSTONED / PURGED`，
   且是 `required` 欄位。所以 FP-1 **不是發明狀態機**，只是定義這五個
   既有值之間哪些轉移合法。
2. **legal hold 擋刪除已有 repo 內先例**：
   `規格/v0.1/personal-harness-integration.yaml` 的 `DELETE` 對
   `EMPLOYEE_PRIVATE`／`COMPANY_MANAGED_PERSONAL`／`SHARED_WORK_CONTEXT`
   三類材料，**全部**把 `legal_hold_absent` 列為必要條件。
3. `permission_decision_ref` 與 `deletion_confirmation_ref` 欄位都已存在
   （`["string","null"]`），只是語意未鎖。

---

## FP-1：retention 狀態轉移

五個值已鎖，只決定哪些轉移合法。

- **(A)** 線性推進 ＋ legal hold 旁路：
  `RETAINED → RETENTION_EXPIRED → TOMBSTONED → PURGED`；
  `RETAINED ↔ LEGAL_HOLD`、`RETENTION_EXPIRED ↔ LEGAL_HOLD`
  （hold 可加可解，解除後回到原階段）；
  `TOMBSTONED`／`PURGED` 為終態，不可逆。**← CC 建議**
- **(B)** 額外允許 `TOMBSTONED → RETAINED`（可還原）。但 tombstone 的意義
  就是 payload 已清除，要能還原就得留著 payload，自相矛盾。
- **(C)** 不限制轉移，只記錄。等於沒有契約，validator 無事可驗。

## FP-2：deletion 語意 —— evidence identity 保不保留

- **(A)** **保留 identity，只清 payload**：進入 `TOMBSTONED` 時保留
  `evidence_id`／`digests`／`provenance`／`chronology`，payload 變成
  reference-only 的墓碑；進入 `TOMBSTONED` 或 `PURGED` 時
  `deletion_confirmation_ref` **必填**。**← CC 建議**（保住稽核鏈：
  能證明「曾經存在、已依規刪除」）
- **(B)** identity 一併刪除。下游所有 `evidence_refs` 變成斷鏈，且無法
  區分「從未存在」與「已刪除」。
- **(C)** 不設 tombstone 階段，直接 `PURGED`。同樣失去上述區別。

## FP-3：legal hold 是否無條件擋 delete／purge

- **(A)** **是，無條件擋**。`LEGAL_HOLD` 狀態下不得進入 `TOMBSTONED`／
  `PURGED`，沒有覆蓋路徑。與 `personal-harness-integration.yaml` 的
  `legal_hold_absent` 先例一致。**← CC 建議**
- **(B)** 可被更高權限覆蓋。那需要定義「誰有那個權限」，等於新增一層
  授權角色——踩 `FORBIDDEN_BY_DEFAULT` 的 enterprise RBAC 邊界。

## FP-4：ACL delta 傳遞

來源 ACL 變更後，既有的 `permission_decision_ref` 怎麼辦？

- **(A)** **標記為 stale，下次取用前必須重做 permission-before-retrieval**。
  不預先批次重算、不建佇列。契約要求：ACL 變更後，帶舊 decision 的取用
  一律 fail-closed。**← CC 建議**（不建 registry／queue／worker）
- **(B)** 來源 ACL 一變就批次重算所有受影響 evidence。需要 queue／worker，
  踩 `FORBIDDEN_BY_DEFAULT`。
- **(C)** 不處理，沿用舊 decision。直接違反 Permission-before-Retrieval
  這條 Truth Boundary。

## FP-5：projection / cache cleanup 是可驗要求還是 best-effort

- **(A)** **可驗，但以「收據」形式**：進入 `TOMBSTONED`／`PURGED` 時必須
  附 `projection_cleanup_receipt_ref`，validator 驗它存在且為合法 URN；
  收據指向的下游是否真的清乾淨，由該下游自己的契約負責。**← CC 建議**
  （可驗、但不需要 orchestrator）
- **(B)** best-effort，只記錄不驗。刪除後資料仍可能留在檢索索引裡，
  刪除承諾形同虛設。
- **(C)** 同步強制清除所有下游後才算刪除成功。需要 orchestrator／queue，
  踩禁令。

---

## 簽核方式

回五個字母，例如：`A A A A A`。

## Do not absorb（簽核後實作時仍適用）

- 不建 retention DB、deletion queue、legal-hold registry、新 writer。
- 不改 STD-01 欄位名（只定義值域與 transition）。
- 沿用薄 validator + fixtures，不引入狀態機引擎。

## 簽核後

轉 T1 closeout 卡，新增
`規格/v0.1/permission-retention-deletion.yaml` ＋
`scripts/validate_permission_retention_deletion_contract.rb` ＋ fixtures，
走大 review。之後才輪到 repo #5（T3，另需 Owner 定稽核範圍）與 `SSP-294`。
