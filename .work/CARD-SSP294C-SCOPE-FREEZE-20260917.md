---
id: SSP294C-SCOPE-FREEZE-20260917
status: AWAITING_OWNER_SIGNATURE
type: scope_freeze
tier: T2
jira: SSP-294（EMEM-05 Promotion）切片 C
parent_card: CARD-SSP294-PROMOTION-20260909
---

# SSP-294 切片 C — 範圍裁決（碰 canonical writer 邊界，升 T2）

切片 A（gate 組成）與 B（15 決策格）皆已 `ACCEPTED_GO`。C 原訂做
「retention/deletion 傳遞 ＋ 不得繞過 canonical writer」，但研究後發現三件事
需要你先裁決——其中一件是名詞衝突，不先講清楚會接錯東西。

## 研究發現

### 1. 兩個不同的東西都叫「promotion」

| 名稱 | 實際是什麼 | 宣告在哪 |
|---|---|---|
| `ai-work-record-boundary.promotion_path` | **證據 → 個人記憶紀錄**的 6 步鏈（`RAW_EVIDENCE_ENVELOPE → CANDIDATE → VERIFICATION → PERSONAL_ACCEPTANCE → PERSONAL_MEMORY_RECORD`）| SSP-298 |
| `actor_action_policy.PROMOTE` | **個人 → 公司／共享**的可見範圍放寬 | `personal-harness-integration` |

前者是「東西怎麼變成個人記憶」，後者是「已是個人記憶的東西怎麼擴大可見範圍」。
**兩者不是同一條路徑**。repo #5 的常設 gate 綁的是前者。切片 A／B 做的是後者。

### 2. 「升格之後 retention 怎麼變」**上游沒有宣告**

`retention_and_lifecycle_policy` 有 `delete_semantics`／`export_semantics`
（逐材料類別），但沒有任何地方說「材料從 EMPLOYEE_PRIVATE 升格成
SHARED_WORK_CONTEXT 之後，retention 狀態／刪除權跟著怎麼走」。

這是**缺政策**，不是缺強制。切片 A／B 的性質是「強制既有宣告」，這一項不是。

### 3. `source_acl_inheritance` 有具體形狀可綁，但目前只有散文比對

上游宣告「source ACL 是天花板，個人記憶可收窄不可放寬，除非過 promotion
gate」，並列出 3 個 `required_receipts`：`source_acl_snapshot`、
`personal_acl_decision`、`policy_ref`。

目前唯一的檢查是 `validate_personal_memory_scope_contract.rb:137`——斷言
**規則的敘述文字裡含有 "cannot widen"**。三個 receipt 完全沒被驗。

---

## FP-1：升格後的 retention 傳遞怎麼處理？

- **(A)** 本片**不做** retention 傳遞。只做「不得繞過」的部分（見 FP-3）。
  傳遞語意屬於缺政策，另立一張 Owner 決策卡再談。**← CC 建議**——切片 A／B
  之所以順利，正因為它們只強制既有宣告；這一項沒有宣告可強制，硬做就是 CC
  自己設計治理政策。
- **(B)** 由 CC 提一組傳遞語意讓你簽。可行，但那是設計政策不是強制，且會把
  本片從 T1 實作變成另一輪 spec-freeze。
- **(C)** 沿用 repo #4 的 `delete_semantics` 當預設。不建議——那是「刪除時
  怎麼做」的語意，不是「升格後變怎樣」，硬套是猜。

## FP-2：兩個 promotion 的關係要怎麼宣告？

- **(A)** 在契約**明確宣告兩者是不同的東西**，本片只綁
  `actor_action_policy.PROMOTE`，並寫明不得與 `promotion_path` 互相套用。
  **← CC 建議**——名詞已經撞了，不寫下來遲早有人把 repo #5 的 6 步檢查套到
  可見範圍放寬上。
- **(B)** 視為同一條路徑，綁 `promotion_path`。會讓 repo #5 的常設 gate 開始
  對 `PROMOTE` run 套用 6 步檢查——語意上是錯的。
- **(C)** 不處理。名詞衝突留著，日後誤接的成本由後人承擔。

## FP-3：`source_acl_inheritance` 的 3 個 receipt 要不要在本片強制？

- **(A)** 要。它們正是「不得繞過」的具體、可驗形狀，而且目前只有散文比對
  ——`cannot widen` 這句話在不在文字裡，跟實際有沒有擋住是兩回事。
  **← CC 建議**
- **(B)** 不要，另立一片。會讓本片幾乎沒有可做的事（FP-1 若選 A）。

---

## 簽核方式

回三個字母，例如：`A A A`。

## 簽核後

若 `A A A`：本片縮為「source ACL ceiling 的強制」——綁 3 個 receipt ＋
`widening_requires_promotion_gate`，並宣告與 `promotion_path` 的區別。
以 T1 實作、走大 review。retention 傳遞另開 Owner 決策卡。
