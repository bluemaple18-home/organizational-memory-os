# SSP-302 Repair 02 — SSP302-F-01 改用語法樹　evidence

日期：2026-09-11　branch：`cc/ssp302-error-code-coverage`
原 review：`19b099b`　前一輪 repair：`cf62d64`　base：`096cea3`

## 收的 finding

`SSP302-F-01`（P2），同一條 blocker 的**第 2 次**修正。

## 根因（兩輪是同一句話）

| 輪次 | regex 的隱含假設 | 反例 |
| --- | --- | --- |
| 原始 | return 一定是雙引號字面量 | `return 'LOOP_UNDECLARED'` |
| repair-01 | return 一定在以 `return` 開頭的實體行 | `if run["x"]; return CONST; end` |

兩次都不是「少驗了一個 case」，而是**分類本身不是全集**。
再補第三次 regex，只會把漏洞推到 `x and return y`、block 內 return、三元、heredoc。

## 修法：Ripper 語法樹

新檔 `scripts/lib/loop_return_contract.rb`（123 行）。`Ripper` 是 Ruby stdlib，
不新增相依。連 evaluator 函式本體的擷取都改由語法樹定位，validator 內不再有
任何 regex 參與 return site 的判定。

契約：每個 return 只能是 `return nil`，或 `return` 單一且無插值的字串字面量
且符合 `<CODE>` 命名。其餘一律 `DISALLOWED`。

## 驗證

### Bypass mutation（12 種合法 Ruby return 寫法）

| # | 注入 | 結果 |
| --- | --- | --- |
| C1 | `if run["x"] == true; return EXPECTED_OUTCOMES.first; end`（**reviewer 指定**） | RED/assertion |
| C2 | `if run["x"]; return 'LOOP_UNDECLARED'; end` | RED/assertion |
| C3 | `run["x"] and return EXPECTED_OUTCOMES.first` | RED/assertion |
| C4 | 多行 `if` 區塊內 `return CONST` | RED/assertion |
| C5 | block 內 `return CONST` | RED/assertion |
| C6 | 裸 `return` | RED/assertion |
| C7 | 三元運算子 `return(x ? "A" : "B")` | RED/assertion |
| C8 | heredoc | RED/assertion |
| C9 | `return %w[LOOP_UNDECLARED].first` | RED/assertion |
| C10 | `return 'LOOP_UNDECLARED'`（單引號、未宣告） | RED/assertion |
| C11 | `return 'LOOP_UNBOUNDED'`（單引號、**已宣告**） | **GREEN** |
| C12 | 字串插值 `return "LOOP_#{...}"` | RED/assertion |

**11 RED / 1 GREEN（全部 assertion-RED，無 exception）。**

C1~C9、C12 由形式分類攔下；C2 與 C10 由完整性斷言攔下（語法樹看得到單引號字面量，
所以未宣告的 code 直接對不上 `error_contract`）。

### C11 是刻意放寬，不是漏洞（主動回報）

repair-01 禁止單引號，是**為了遷就 regex 看不見單引號**才加的限制。
語法樹看到的是字串的**值**，`return 'LOOP_UNBOUNDED'` 會被正確列入可回傳集合 ——
那個 return **有被算到**，且它回傳的是已宣告的 code，完整性命題不受影響。
既然限制的理由消失，我把它移除，並把契約文字改寫成實際 enforce 的性質
（「單一、無插值的字串字面量」），不再提引號風格 ——
避免又出現一次「契約說的」和「實際驗的」不一致。

若 reviewer 認為風格一致性仍該機器強制，那是新的 style finding，
不是 `SSP302-F-01` 的完整性缺口。可用 `Ripper.lex` 補，但我不自行擴大本輪範圍。

### 回歸（全部維持）

| 項目 | 結果 |
| --- | --- |
| 逐 code 改名 parity（15 個） | **15 RED / 0 GREEN** |
| Guard parity（17 條 return site） | **17 RED / 0 GREEN**，assertion 15 / exception 2 |
| 既有判定（對比修正前 `main` 的 24 案） | **exact code 逐字相同**，只新增本卡的 4 案 |
| Ruby validators | 21 PASS / 0 FAIL |
| 四支 Python engine | 全 PASS |
| `git diff --check` | clean |

### 檔案大小（上一輪自報的風險已解除）

| 檔 | 行數 |
| --- | --- |
| `scripts/validate_ai_work_record_loop_contract.rb` | 390 → **371** |
| `scripts/lib/loop_return_contract.rb`（新） | 123 |

把綁定機制抽成獨立檔，順帶解掉上一輪自報的「距 400 硬上限只剩 10 行」。
這不是順手重構 —— 是本輪修法本來就需要新增一整組語法樹處理，不抽出去必然爆表。

## Hard stop（寫進卡片，本輪明示）

`SSP302-F-01` 已連續兩輪 NO_GO。依全域規則「同一 blocker 第 3 次失敗即停」：
**若本輪再被判 NO_GO，不得再開 repair-03。** 直接轉 Owner spec-freeze（T2），
由 Owner 裁決「validator 的完整性要驗到什麼程度」這個規格問題，
而不是由我再猜下一個 reviewer 會舉哪一種 Ruby 語法。

## 本輪沒有做的事

- 沒有做 branch-level coverage machinery（reviewer 兩輪都明說不需要）。
- 沒有改既有錯誤語意或 evaluator 判斷邏輯（現有 17 條 return 逐字未動）。
- 沒有重開 F-04 / F-05、沒有動上游、沒有新增外部套件（`Ripper` 是 stdlib）。
