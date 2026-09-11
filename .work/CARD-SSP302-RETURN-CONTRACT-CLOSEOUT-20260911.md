---
id: SSP302-RETURN-CONTRACT-CLOSEOUT-20260911
status: IMPLEMENTED_AWAITING_TARGETED_REREVIEW
type: implementation
tier: T1
review_line: SSP-302 error-code 契約完整性
implements_spec_freeze: SSP302-RETURN-CONTRACT-SPEC-FREEZE-20260911
owner_signature: "FP-1: B / FP-2: A / FP-3: A / FP-4: A（2026-09-11）"
not_a_repair: >-
  這張卡實作的是 Owner 簽定的規格，不是 repair-03。
  SSP302-F-01 的 hard stop 已於第三輪觸發，repair 線就此關閉。
---

# SSP-302 Closeout — 實作 Owner 簽定的出口形狀凍結

👉 [假設與目標確認]
- 目標：實作 `FP-1-B`，讓 `loop_closeout_failure` 的出口集合成為**全集**而非逼近。
- 邊界：`FP-2-A` —— 只套 `loop_closeout_failure`；不動 SSP-291 已驗收範圍。
  不改既有錯誤語意、不重開 F-04 / F-05、不動上游、不新增外部套件。
- 驗收：`FP-3-A`。

## 實作

`scripts/lib/loop_return_contract.rb` 新增 `exit_shape_violations`：

- evaluator 的 `bodystmt` 不得有 `rescue` / `rescue-else` / `ensure` 子句
  （任一都會多出 tail position）。
- evaluator 的**最後一句必須恰好是 `nil` 字面量**。

加上既有的顯式 return 分類，方法只剩兩種回傳途徑：**被分類過的顯式 return，
或尾端那個 `nil`**。這是可窮舉的。

validator 在原有三層 assertion **之前**先驗出口形狀 —— 出口形狀不成立時，
後面的集合比對本來就不是全集，先報這一層才說得通。

契約 `error_contract_binding.evaluator_exit_shape_rule` 記錄這個凍結與其邊界。

### 邊界（寫進契約）

例外不是回傳值。evaluator 拋例外會讓 validator 崩潰並轉紅，
不會變成一個未被宣告的 code。

## FP-3-A 驗收結果

### 真正的隱式回傳（尾句本身就是違規 expression）—— 必須全 RED

| # | 尾句 | 結果 |
| --- | --- | --- |
| F1 | 未宣告 code 字面量 | RED/assertion |
| F2 | `if / else` | RED/assertion |
| F3 | 三元 | RED/assertion |
| F4 | `&&` 短路 | RED/assertion |
| F5 | 方法呼叫 | RED/assertion |
| F6 | `case` | RED/assertion |
| F7 | `begin` 區塊 | RED/assertion |
| F8 | **已宣告**的 code 字面量 | RED/assertion |
| E1 | 加入 `rescue` 子句 | RED/assertion |
| E2 | 加入 `ensure` 子句 | RED/assertion |

**10 RED / 0 GREEN。**

### no-op 對照組（必須維持 GREEN）

| # | 注入 | 結果 |
| --- | --- | --- |
| N1 | 中段 `if`（值被丟棄） | GREEN |
| N2 | 中段方法呼叫 | GREEN |

**2 / 2 維持 GREEN。** 這組是為了證明斷言不是「動什麼都變紅」——
它們在 Ruby 語意上確實回傳 `nil`，不該被攔。

### 前三輪的 C1~C12 回歸

**11 RED / 1 GREEN。** 唯一的 GREEN 是 C11（單引號但 code 已宣告），
reviewer 上一輪已明示「合理，不列 finding」。

### 其餘回歸

| 項目 | 結果 |
| --- | --- |
| 逐 code 改名 parity（15 個） | 15 RED / 0 GREEN |
| Guard parity（17 條 return site） | 17 RED / 0 GREEN，assertion 15 / exception 2 |
| 既有判定（對比修正前 `main` 的 24 案） | exact code 逐字相同，只新增本卡的 4 案 |
| Ruby validators | 21 PASS / 0 FAIL |
| 四支 Python engine | 全 PASS |
| `git diff --check` | clean |
| 檔案大小 | validator 380 行、lib 159 行，皆 `< 400` |

## FP-2-A 的已知後果（Owner 已簽核接受）

`SSP-291` 已 merge 進 `main` 的 `evidence_profile_failure` 有**完全相同**的隱式回傳缺口
（實測：同手法注入 → GREEN）。依 `FP-2-A` 本卡不處理，另開 backlog：
`.work/CARD-SSP291-EXIT-SHAPE-BACKLOG-20260911.md`。

## FP-4-A 停損（已簽核）

若本卡送定點 re-review 後仍因「某種 Ruby 構造沒被涵蓋」被判 NO_GO，
**不再修 validator**：整張 `SSP302-ERROR-CODE-COVERAGE` 標記 `DEFERRED`，
保留 `14cf20a` 已無爭議的改善，剩餘完整性問題轉獨立 backlog，不再阻塞 `SSP-307`。

## Evidence

`.work/evidence/SSP302-RETURN-CONTRACT-CLOSEOUT-20260911.md`
