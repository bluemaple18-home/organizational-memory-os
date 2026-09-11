---
id: SSP302-RETURN-CONTRACT-SPEC-FREEZE-20260911
status: AWAITING_OWNER_SIGNATURE
type: spec_freeze
tier: T2
review_line: SSP-302 error-code 契約完整性
blocker: SSP302-F-01
blocker_failures: 3
supersedes_repair: "不開 repair-03（hard stop 已觸發）"
frozen_refs:
  base: 096cea3
  original_review: 19b099bd3bb14325d1b6cca6c22b1d0535bbf505
  repair_01: cf62d640b78000bb2516526bb4bb75d1afb34a04
  repair_02: 14cf20a879922aa0910458c7ae276a0288fd8d7f
---

# Owner Spec-Freeze — evaluator 回傳契約要凍結到什麼程度

👉 [假設與目標確認]
- 目標：由 Owner 簽定一個**可窮舉的**規格，決定 validator 的自我綁定要驗到什麼程度，
  之後由一張 T1 closeout 卡實作。
- 邊界：本卡**不實作**。不重開 F-04 / F-05，不動上游，不改既有錯誤語意。
- 驗收：Owner 在下方每個 freeze point 簽選項。

## 為什麼走到這裡

`SSP302-F-01` 連續三輪 NO_GO，全域規則「同一 blocker 第 3 次失敗即停」觸發。
reviewer 本輪也明示應停 repair-03、轉 T2。

三輪的 finding 是同一句話的三個實例：

| 輪次 | 我的分析方法隱含的假設 | reviewer 舉的反例 |
| --- | --- | --- |
| 原始（`19b099b`） | return 一定是雙引號字面量 | `return 'LOOP_UNDECLARED'` |
| repair-01（`cf62d64`） | return 一定在以 `return` 開頭的實體行 | `if run["x"]; return CONST; end` |
| repair-02（`14cf20a`） | 回傳一定是顯式 `return` node | 方法最後一個 expression 的**隱式回傳** |

每一輪我都修好了那一個 case，然後下一輪被下一種合法 Ruby 打穿。
**問題不在少驗了哪個構造，而在我一直在逼近一個開放集合。**

## 缺口已實測（不是推論）

在 `14cf20a` 上，把 evaluator 尾端的 `nil` 換掉：

| 變體 | 結果 |
| --- | --- |
| D1 直接換成 `"LOOP_UNDECLARED"` | RED —— 但**是被正例 fixture 攔下的**（正例預期 allow 卻被拒），不是被完整性綁定攔下 |
| D2 `"LOOP_UNDECLARED" if run["x"] == true` 然後 `nil` | **GREEN(bad)** |
| D3 尾端改成 `if / else` 隱式回傳 | **GREEN(bad)** |
| D4 尾端改成三元運算子隱式回傳 | **GREEN(bad)** |

D2~D4 正例完全不受影響（正例的 run 沒有 `x`），所以只有完整性綁定該攔 —— 它沒攔。
reviewer 的判讀成立：契約仍宣稱「`error_contract` keys == evaluator **實際可回傳** 集合」，
但實作只驗到「顯式 return 的 code 集合」。

## 這是規格問題，不是又一個 bug

reviewer 把它歸類為「本卡沒做到自己宣稱的事」。我同意 —— 但**修法的選擇**是規格層決定：
要把宣稱降到實作做得到的程度，還是把實作提高到宣稱的程度，
以及願意為此付出多少限制與成本。這不該由我在第四輪繼續猜。

---

## Freeze Point 1：完整性的目標定義

**FP-1-A**　維持現宣稱「== evaluator 實際可回傳集合」，並用完整 tail-position 控制流分析達成。
　　需處理：bodystmt 尾句、`if`/`unless`/`case` 各分支尾句、`begin`/`rescue`/`ensure`、
　　`&&`/`||` 尾、三元、`and`/`or`。這是一個迷你控制流分析。
　　**風險：這正是前三輪的同一個模式 —— 追一個開放集合。我預期會有第四輪。**

**FP-1-B（CC 建議）**　維持現宣稱，但改成**凍結 evaluator 的出口形狀**，讓出口集合成為全集：
　　- 斷言 evaluator 的 `bodystmt` 不得有 `rescue` / `else` / `ensure` 子句；
　　- 斷言 evaluator 的**最後一句必須恰好是 `nil` 字面量**。
　　加上既有的顯式 return 分類，方法的出口就只剩兩種：被分類過的顯式 return，或尾端的 `nil`。
　　**這是可窮舉的，不是逼近。**
　　已驗證可表達：語法樹直接給出 `bodystmt` 的四個子句與最後一句節點。
　　成本：約 15 行。代價：evaluator 永遠必須以 `nil` 結尾、不得使用 `rescue` / `ensure`。

**FP-1-C**　降低宣稱：契約改寫成「== 顯式 return 的 code 集合，且 evaluator 出口形狀受限」，
　　把殘餘風險寫進契約。誠實，但放棄了原本的性質。

**FP-1-D**　改變 evaluator 的回傳型別：回傳 Symbol，code 字串集中在凍結 map，
　　綁定變成「每個用到的 symbol 都是 map 的 key」。
　　代價：必須改既有 evaluator 判斷邏輯 —— 這條 review line 的邊界一直明文禁止，
　　且會讓 17 條 return 全部重寫，blast radius 遠超本卡。

（已考慮並排除：執行期取樣。無法窮舉輸入，不構成完整性證據。）

**CC 建議：FP-1-B。** 理由與 Document Adapter Mapping 那條 review line 的 FP-3 相同 ——
凍結**一個總分類**，而不是為每一種新構造再加一條綁定。那次 FP-3 不但解決了六輪都沒解決的
問題，還讓 validator 變短。

## Freeze Point 2：這個限制要套用到哪些 evaluator

**FP-2-A（CC 建議）**　只套用 `loop_closeout_failure`。本卡範圍，blast radius 最小。

**FP-2-B**　套用到所有走「原始碼綁定 error_contract」的 evaluator
　　（目前還有 `personal-evidence-profile` 的 `evidence_profile_failure`，SSP-291 已 merge）。
　　一致性較好，但等於在本卡改動另一條已驗收的 review line。

**CC 建議：FP-2-A**，並在 closeout 卡的 evidence 裡記錄
`evidence_profile_failure` 有同樣的隱式回傳缺口，另開 backlog 卡處理。
**注意：這代表 Owner 簽 FP-2-A 就是接受 SSP-291 暫時帶著同一個缺口。**

## Freeze Point 3：驗收要求

**FP-3-A（CC 建議）**　closeout 必須實測以下全部為 RED：
　　D2 / D3 / D4 三個隱式回傳變體、前三輪的 C1~C12 全部、以及 `rescue` / `ensure` 注入。
　　並且既有 24 案判定與 exact code 逐字不變。

**FP-3-B**　只要求 reviewer 本輪舉的例子 RED。
　　**CC 不建議** —— 前三輪都是「只修被舉的那個例子」才走到這裡。

## Freeze Point 4：後續輪次的停損

**FP-4-A（CC 建議）**　closeout 送定點 re-review；若再被判 NO_GO 且理由仍是
　　「某種 Ruby 構造沒被涵蓋」，則**不再修 validator**，改為把
　　`SSP302-ERROR-CODE-COVERAGE` 整張標記為 `DEFERRED`、保留 `14cf20a` 的既有改善
　　（`LOOP_MISSING_FIELD` 補齊、控制測資對齊、15/15 code 覆蓋都已成立且無爭議），
　　把剩餘的完整性問題轉成獨立 backlog，不再阻塞 Lane B。

**FP-4-B**　不設停損，修到 GO 為止。

**CC 建議：FP-4-A。** 這張卡本身是非阻塞收尾，已經吃掉三輪 review。
它擋住的是 `SSP-307`（Lane B 唯一能動的前線）。

---

## Owner 簽核

```
FP-1: ____    FP-2: ____    FP-3: ____    FP-4: ____
簽核日期: ____
```

簽完之後由一張 **T1 closeout 卡**實作（`CARD-SSP302-RETURN-CONTRACT-CLOSEOUT-<date>.md`），
**明確不是 repair-03**：它實作的是 Owner 簽定的規格，而不是再猜一次 reviewer 的下一題。

## 本卡不做

不實作、不改任何檔案、不重開 F-04 / F-05、不動上游。
