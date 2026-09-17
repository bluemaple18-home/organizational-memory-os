---
id: SSP294B-PROMOTION-POLICY-20260917
status: ACCEPTED_GO
merged_commit: 75ac95d
type: implementation
tier: T1
jira: SSP-294（EMEM-05 Promotion）切片 B
parent_card: CARD-SSP294-PROMOTION-20260909
sibling: CARD-SSP294A-PROMOTION-GATE-20260917（ACCEPTED_GO）
---

# SSP-294 切片 B — actor × 材料類別決策表重放

👉 [假設與目標確認]
- 目標：把上游 15 個升格決策格（5 actor × 3 材料類別）變成真的會攔的
  evaluator。目前只有 `MANAGER/COMPANY_MANAGED_PERSONAL` 那一格的 3 條條件
  被驗，其餘 14 格的 decision 與條件從來沒有任何 evaluator 會擋。
- 邊界：只做決策表。gate 組成是切片 A（已 `ACCEPTED_GO`）；retention/deletion
  傳遞與 canonical writer 是切片 C。
- 驗收：見 Acceptance。

## 關鍵設計

### 1. 不重述上游表

actor／類別／decision／條件全部 evaluation 時從上游讀，契約一個名稱都不抄。
另有斷言禁止本契約文字出現任何上游名稱。

### 2. 覆蓋斷言是「決策感知」的

光是「每格被踩過」不夠——我自己探測時發現：把 `ADMIN/SHARED_WORK_CONTEXT`
從 `DENY` 翻成 `CONDITIONAL`，原本的 `DENIED` 正例照樣通過，**治理上的放寬
沒有人發現**。

改成：`CONDITIONAL` 格必須有**成功升格**的正例（才會真的去驗條件），
`DENY` 格必須有**被拒**的正例。三種上游變動因此都會轉紅：

| 上游變動 | 結果 |
|---|---|
| `DENY` 格放寬成 `CONDITIONAL` | RED（缺成功升格 fixture）|
| 新增一個 actor | RED（新格缺 fixture）|
| `CONDITIONAL` 格新增一條條件 | RED（既有正例缺該條件）|

### 3. fixture 可自帶 policy（少數 guard 用）

`decision` 是無法辨識的值、`required_conditions` 不是清單——健康的上游產不出
這兩種輸入，但 guard 必須存在（上游若打錯字，沒有 guard 就會落進寬鬆分支）。
這類 case 可自帶 policy；沒自帶的一律對真實上游評估。覆蓋斷言排除自帶的案例。

## Constraints

- 不重述上游表；不建 identity／receipt store／writer。
- 不做 gate 組成（切片 A）、不做傳遞語意（切片 C）。
- validator `< 400` 行。

## Acceptance

1. `DENY` 格報 `PROMOTED` → 拒，無論帶什麼條件。
2. `CONDITIONAL` 格報 `PROMOTED` → 必須滿足該格**全部**條件，且每條帶 omos
   URN receipt。
3. `DENIED` 永遠可接受（拒絕升格不需理由）。
4. 未知 actor／未知材料類別／未知條件／非 map 條件 → 全部 fail-closed，
   **不做任何寬容轉型**（切片 A 就是栽在 `.to_a` 上）。
5. 決策感知覆蓋：上游放寬 `DENY`、新增 actor、新增條件三者皆轉紅。
6. 逐 return site parity 全紅；既有 28 支 validator 不受影響。

## 已知邊界（主動宣告）

`provenance_boundary` 承認兩件本層驗不了的事：receipt 真實性，以及
**宣告的 actor 是否真的是該 actor**——run 宣稱自己是權限較寬的角色，就會被
對著那格評估。認證 actor 需要本契約不擁有的 identity 邊界。

## 已知重複（主動宣告）

`satisfied_conditions` 的型別與 URN 檢查與切片 A 相同（約兩行）。未抽共用
helper，因為那要動已 `ACCEPTED_GO` 的切片 A；為兩行去重構已驗收程式碼是壞
交易。第三片若需要同樣形狀，那才是正式抽出的時機。

## 大 review 記錄

- `4b5924d`：**GO**，P0=P1=0，P2×2 residual（皆不阻擋，已登 backlog）：
  1. 決策感知覆蓋把正負例混在一起只看 `outcome == PROMOTED`——同格若有
     PROMOTED 負例，刪掉唯一成功正例仍會 PASS。註解宣稱的「CONDITIONAL 必須
     有成功正例」因此沒有完全被 enforce。修法：promoted coverage 只取
     `expected == allow` 的正例。
  2. `provenance_boundary` 承認了 actor 可能是自述，但 `material_class` 同樣
     由 caller 自述、同樣能選到不同 policy cell，未列入 `does_not_verify`。
     修法：補 `THE_DECLARED_MATERIAL_CLASS_IS_THE_REAL_CLASS`。

## Evidence

`.work/evidence/SSP294B-PROMOTION-POLICY-20260917.md`
