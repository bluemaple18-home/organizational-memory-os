---
id: SSP294A-PROMOTION-GATE-20260917
status: AWAITING_BIG_REVIEW
type: implementation
tier: T1
jira: SSP-294（EMEM-05 Promotion）切片 A
parent_card: CARD-SSP294-PROMOTION-20260909
---

# SSP-294 切片 A — promotion widening gate 的強制

👉 [假設與目標確認]
- 目標：把 `personal-harness-integration.yaml` 早已宣告、但幾乎沒有被強制的
  `promotion_widening_gate`（6 required ＋ 3 forbidden）變成真的會攔的 evaluator。
- 邊界：**只做 gate 組成**。逐 actor × 材料類別的 15 個決策格是切片 B；
  retention/deletion 傳遞與 canonical writer 不得繞過是切片 C。
- 驗收：見 Acceptance。

## 研究發現（決定了本卡的性質）

`SSP-294` 不是「設計升格政策」——政策早就寫在上游了：

| 上游宣告 | 目前實際被驗到的部分 |
|---|---|
| gate 的 6 個 required | **只有 1 個**（`validate_personal_memory_scope_contract.rb:138` 斷言 `reviewer_approval` 要在清單裡）|
| gate 的 3 個 forbidden | **完全沒有** |

所以本卡是**強制既有宣告**，不是新增政策。前置四項（repo #2～#5）皆已完成，
卡片原本的 blocker 表停在 2026-09-09，本輪一併校正。

## 關鍵設計：不重述上游清單

`emem-promotion-gate.yaml` **不寫** required／forbidden 的內容，evaluation 時
從上游讀。validator 另有一道斷言：本契約文字裡不得出現任何一個上游條件名稱
——出現就是在複製，會轉紅。

效果已實測：**上游新增一個 required 條件或一條 forbidden 路徑，本檔一行不改
就立刻開始擋。**

## Constraints

- 不重述上游 gate 的 required／forbidden。
- 不建 receipt store／registry／writer。
- 不做 per-actor 政策（切片 B）、不做傳遞語意（切片 C）。
- validator `< 400` 行。

## Acceptance

1. `PROMOTED` 必須滿足上游**全部** required 條件，且每個條件帶 omos URN receipt。
2. 宣告任一 forbidden 路徑即拒——**即使所有 required 條件都滿足**（禁止路徑不可
   被 approvals 贖回）。
3. `DENIED` 不需備齊條件（被擋下的升格本來就不必）。
4. 宣告上游沒有的條件名稱 → 拒（對著本 repo 不認得的 gate 說話）。
5. 上游新增 required／forbidden → 本檔不改任何一行，行為立刻跟上。
6. 逐 return site parity 全紅；既有 27 支 validator 不受影響。

## 已知邊界（主動宣告，非缺口）

`provenance_boundary`：本層驗「run 有沒有為每個 required 條件指名 receipt」，
**不驗那些 receipt 是否真實**——系統裡沒有 receipt store 可以 resolve，建立它
超出範圍。與 `permission-retention-deletion.yaml#provenance_boundary` 同一邊界，
先講清楚而不是等 review 抓。

## Evidence

`.work/evidence/SSP294A-PROMOTION-GATE-20260917.md`
