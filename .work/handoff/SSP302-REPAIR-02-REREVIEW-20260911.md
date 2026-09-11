# SSP-302 Repair 02 — 定點 re-review 交付包

同一條 review line。只收 `SSP302-F-01`。**這是該 blocker 的第 2 次修正。**

## 1. 鎖定

```
base                096cea3
original_review     19b099bd3bb14325d1b6cca6c22b1d0535bbf505   （immutable）
repair_01           cf62d640b78000bb2516526bb4bb75d1afb34a04   （immutable，已被判 NO_GO）
repair_02           14cf20a879922aa0910458c7ae276a0288fd8d7f   ← 本輪
branch              cc/ssp302-error-code-coverage
```

定點 diff：`git diff cf62d64..14cf20a`

## 2. 為什麼不再補 regex

你兩輪指出的是同一句話的兩個實例：

| 輪次 | regex 的隱含假設 | 你舉的反例 |
| --- | --- | --- |
| 原始 | return 一定是雙引號字面量 | `return 'LOOP_UNDECLARED'` |
| repair-01 | return 一定在以 `return` 開頭的實體行 | `if run["x"]; return CONST; end` |

再補第三次 regex，只會把漏洞推到 `x and return y`、block 內 return、三元、heredoc。
問題不在少驗了哪個 case，而在**分類本身不是全集**。

## 3. 修法

改用 `Ripper`（Ruby stdlib，**不新增相依**）解析 validator 自身，
窮舉 `loop_closeout_failure` 的全部 return site。

新檔 `scripts/lib/loop_return_contract.rb`（123 行）：
語法樹定位 evaluator 定義 → 走訪子樹收集所有 `:return` / `:return0` → 逐一分類。

契約：每個 return 只能是 `return nil`，或 `return` 單一且無插值的字串字面量
且符合 `<CODE>` 命名；其餘一律 `DISALLOWED`。

**validator 內不再有任何 regex 參與 return site 判定** —— 連函式本體的擷取都改由語法樹，
不再是 `/^def loop_closeout_failure.*?^end$/m`。

## 4. 請重播 —— 12 種合法 Ruby return 寫法

我的結果：**11 RED / 1 GREEN，全部 assertion-RED，無 exception。**

```ruby
C1   if run["x"] == true; return EXPECTED_OUTCOMES.first; end   # 你指定的     → RED
C2   if run["x"]; return 'LOOP_UNDECLARED'; end                 → RED
C3   run["x"] and return EXPECTED_OUTCOMES.first                → RED
C4   多行 if 區塊內 return EXPECTED_OUTCOMES.first               → RED
C5   run.each { |_k,_v| return EXPECTED_OUTCOMES.first if ... } → RED
C6   return（裸）                                               → RED
C7   return(run["x"] ? "LOOP_A" : "LOOP_B")                     → RED
C8   return(<<~CODE.strip)                                      → RED
C9   return %w[LOOP_UNDECLARED].first                           → RED
C10  return 'LOOP_UNDECLARED'                                   → RED
C11  return 'LOOP_UNBOUNDED'（單引號、code 已宣告）              → GREEN ← 見 §5
C12  return "LOOP_#{run["x"]}"                                  → RED
```

## 5. 唯一的 GREEN 是刻意放寬，請你裁決

repair-01 禁止單引號，那是**為了遷就 regex 看不見單引號**才加的限制。
語法樹看到的是字串的**值**，`return 'LOOP_UNBOUNDED'` 會被正確列入可回傳集合 ——
**那個 return 有被算到**，且回傳的是已宣告的 code。完整性命題不受影響。

既然限制的理由消失，我移除了它，並把契約文字改寫成實際 enforce 的性質
（「單一、無插值的字串字面量」），不再提引號風格 ——
否則又會出現一次「契約說的」與「實際驗的」不一致，那正是這條 review line 的起點。

如果你認為風格一致性仍該機器強制，那是新的 **style finding**，
不是 `SSP302-F-01` 的完整性缺口。可用 `Ripper.lex` 補。我不自行擴大本輪範圍。

## 6. 回歸

| 項目 | 結果 |
| --- | --- |
| 逐 code 改名 parity（15 個） | 15 RED / 0 GREEN |
| Guard parity（17 條 return site） | 17 RED / 0 GREEN，assertion 15 / exception 2 |
| 既有判定（對比修正前 `main` 的 24 案） | exact code 逐字相同，只新增本卡的 4 案 |
| Ruby validators | 21 PASS / 0 FAIL |
| 四支 Python engine | 全 PASS |
| `git diff --check` | clean |

既有 evaluator 判斷邏輯逐字未改，17 條 return 一個都沒動。請確認：

```
git diff cf62d64..14cf20a -- scripts/validate_ai_work_record_loop_contract.rb
```

## 7. 上一輪自報的檔案大小風險已解除

| 檔 | 行數 |
| --- | --- |
| `scripts/validate_ai_work_record_loop_contract.rb` | 390 → **371** |
| `scripts/lib/loop_return_contract.rb`（新） | 123 |

不是順手重構 —— 本輪修法本來就要新增一整組語法樹處理，不抽出去必然爆 400。

## 8. Hard stop（本輪明示）

`SSP302-F-01` 已連續兩輪 NO_GO。依全域規則「同一 blocker 第 3 次失敗即停」：
**若本輪再判 NO_GO，我不會開 repair-03。** 會直接轉 Owner spec-freeze（T2），
由 Owner 裁決「validator 的完整性要驗到什麼程度」這個規格問題 ——
而不是由我再猜下一種 Ruby 語法。

若你仍有 finding，請一併說明它屬於「本卡沒做到自己宣稱的事」還是
「本卡宣稱的標準本身需要 Owner 重新定義」，那會決定下一步走 repair 還是 spec-freeze。

## 9. 邊界（未變）

沒有做 branch-level coverage machinery、沒有改既有錯誤語意或 evaluator 判斷邏輯、
沒有重開 F-04 / F-05、沒有動上游、沒有新增外部套件（`Ripper` 是 stdlib）。

請就 `SSP302-F-01` 給 `GO` 或 `NO_GO`。
