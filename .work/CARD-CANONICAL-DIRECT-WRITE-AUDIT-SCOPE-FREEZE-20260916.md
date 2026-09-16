---
id: CANONICAL-DIRECT-WRITE-AUDIT-SCOPE-FREEZE-20260916
status: AWAITING_OWNER_SIGNATURE
type: scope_freeze
tier: T3
implements_card: CARD-CANONICAL-DIRECT-WRITE-AUDIT-20260909
jira: SSP-294 最後一個前置（repo #5）
---

# repo #5 Canonical Direct-Write Audit — Owner 範圍裁決

👉 [假設與目標確認]
- 目標：把 `CARD-CANONICAL-DIRECT-WRITE-AUDIT-20260909`（自 2026-09-09
  `BLOCKED_AWAITING_OWNER_SCOPE_DECISION`）的四個 scope 問題，變成可以用
  字母簽掉的選項。
- 邊界：本卡**只做範圍裁決**，不稽核。這是 T3——稽核對象是 `LOCKED` 的
  Canonical Single Writer Truth Boundary，CC 不自行定範圍、也不自行判定
  哪條路徑該被擋。
- 驗收：Owner 簽四個字母。

## 研究結論（讓範圍具體化）

1. **稽核面實際有多大**：`grep` 後確認有 **11 份契約**引用
   promotion／acceptance／canonical writer：
   `ai-work-record-boundary`／`-e2e-acceptance`／`-harness`／
   `-hermes-adapter`／`-skill`／`-loop`／`-hook`、兩份 native adapter、
   `permission-retention-deletion`、`personal-harness-integration`。
2. **上游權威是機器可讀的**：`ai-work-record-boundary.yaml` 的
   `promotion_path` 有 6 個有序步驟
   （`TASK_CARD_OR_WORK_RECORD → RAW_EVIDENCE_ENVELOPE →
   PERSONAL_MEMORY_CANDIDATE → VERIFICATION → PERSONAL_ACCEPTANCE →
   PERSONAL_MEMORY_RECORD`）與 4 條 rules，含
   `skip_any_step: forbidden`、`task_card_direct_to_record: forbidden`。
   ——所以「有沒有被弱化」可以機器比對，不必人工判讀。
3. **repo 內沒有任何實體 writer 實作**，只有契約宣稱。這直接決定 FP-2。

---

## FP-1：稽核範圍掃到哪裡？

- **(A)** 只掃契約宣告面（`規格/v0.1/*.yaml` ＋ `*.schema.json`）。
- **(B)** 契約宣告面 **＋ `scripts/` validator 是否真的強制**。
  **← CC 建議**。理由：這整個 session 反覆出現的缺陷型態就是
  「契約宣稱了、evaluator 沒真的擋」——只掃宣告面會漏掉正是最危險的那一類。
- **(C)** 再加掃 `.work/` 卡片流。卡片是 control artifact，不是 write path，
  價值低而雜訊高。

## FP-2：judgement 的單一判準是什麼？

- **(A)** 以 `ai-work-record-boundary.promotion_path` 為**單一判準**：
  每個引用 promotion／acceptance／writer 的契約都必須 pointer-bind 回它，
  且不得弱化（不得少步驟、不得放寬 `forbidden` 規則）。**← CC 建議**
  （卡片自己在 Q4 也提了這個方向；SSP-305 repair-01 已有先例）。
- **(B)** 同時稽核「未來 runtime 的 write path」。但 repo 內沒有任何 writer
  實作，這等於對不存在的東西做推測，違反 `EVIDENCE_LIMIT`。
- **(C)** 不設單一判準，逐契約各自認定。結果不可重現，也無法交叉驗證。

## FP-3：findings 的處置權

- **(A)** CC 產出 findings 清單（含嚴重度與證據），**不自行開 repair 卡**，
  逐條回 Owner 裁決。**← CC 建議**——稽核對象是 `LOCKED` 的 Truth Boundary，
  「哪條路徑該被擋」屬 Owner 判斷。
- **(B)** CC 直接開 repair 卡並實作。速度快，但等於 CC 自行決定 Truth
  Boundary 的鬆緊。
- **(C)** 分級：P2／P3 CC 自行修，P0／P1 回 Owner。折衷，但「這條算 P1 還是
  P2」本身又是 CC 在判斷。

## FP-4：稽核輸出要不要留下常設防線？

- **(A)** 只產 findings 文件（一次性稽核）。
- **(B)** findings 文件 **＋ 一支常設 validator**，把「任何契約弱化 SSP-298
  `promotion_path`」變成以後會自動轉紅的 gate。**← CC 建議**——否則這次掃
  乾淨了，下次有人新增契約時又會漂掉；本 session 已經證明純文件約束會漂。

---

## 簽核方式

回四個字母，例如：`B A A B`。

## 簽核後

本卡轉 `IN_PROGRESS`，CC 產出
`.work/evidence/CANONICAL-DIRECT-WRITE-AUDIT-20260916.md`，依 FP-3 的裁決
決定後續。完成後 `SSP-294`（EMEM-05 Promotion）的兩個前置就全部解除。
