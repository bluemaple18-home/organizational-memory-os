# SSP-302 Closeout — 定點 re-review 交付包

**這不是 repair-03。** `SSP302-F-01` 的 hard stop 已於第三輪觸發，repair 線關閉。
本卡實作的是 Owner 於 spec-freeze 簽定的規格。

## 1. 鎖定

```
base                096cea3
original_review     19b099b   （immutable）
repair_01           cf62d64   （immutable，NO_GO）
repair_02           14cf20a   （immutable，NO_GO）
spec_freeze         8b03bbc   → Owner 簽 FP-1: B / FP-2: A / FP-3: A / FP-4: A
closeout            81e1e86a1503efb529d63e53264bc3ed759bbf40   ← 本輪
branch              cc/ssp302-error-code-coverage
```

定點 diff：`git diff 14cf20a..81e1e86`

## 2. 審什麼

Owner 簽定的 `FP-1-B` 有沒有被正確實作，以及 `FP-3-A` 的驗收是否成立。

**不必重開**：前三輪已裁決的項目、C11 單引號已宣告 code 的 GREEN、
code-level coverage assertion 的層級、`LOOP_MISSING_FIELD` 補齊、控制測資對齊。

## 3. 實作（FP-1-B）

`LoopReturnContract.exit_shape_violations`：

- evaluator 的 `bodystmt` 不得有 `rescue` / `rescue-else` / `ensure` 子句。
- evaluator 的**最後一句必須恰好是 `nil` 字面量**。

加上既有的顯式 return 分類，方法只剩兩種回傳途徑：被分類過的顯式 return，
或尾端那個 `nil`。**出口集合是全集，不是逼近。**

validator 在原有三層 assertion **之前**先驗出口形狀 ——
出口形狀不成立時，後面的集合比對本來就不是全集。

**邊界（已寫進契約）**：例外不是回傳值。evaluator 拋例外會讓 validator 崩潰並轉紅，
不會變成一個未被宣告的 code。

## 4. 我自行發現並更正的一個錯誤（請先看這段）

spec-freeze 卡原先寫「D2~D4 三個變體都 GREEN，缺口成立」。
closeout 實作時我用 Ruby **實際執行**驗證，發現 D2 的判定是錯的：

```ruby
def d2(x)
  "LOOP_UNDECLARED" if x == true   # 值被丟棄
  nil
end
d2(true)  # => nil
```

我當時的注入把違規 expression 放在**倒數第二句**，它是 no-op。
所以 D2 的 GREEN 是**正確行為**，不是缺口。真缺口是「**尾句本身**就是違規 expression」。

你的 finding 與 Owner 簽核不受影響（D1/D3/D4 已足以證立），但我的證據陳述不精確。
freeze 卡已就地更正，並標明這是我第三次在自撰 evidence 裡放進未經實際執行驗證的判斷。

**因此本輪驗收加入 no-op 對照組**，要求它們維持 GREEN ——
不只證明「該紅的紅」，也證明「不該紅的沒紅」。

## 5. FP-3-A 驗收 —— 請重播

### A. 真正的隱式回傳（尾句即違規 expression），必須全 RED

我的結果：**10 RED / 0 GREEN，全 assertion-RED。**

```
F1 尾句 = "LOOP_UNDECLARED"                          → RED
F2 尾句 = if / else                                  → RED
F3 尾句 = 三元                                        → RED
F4 尾句 = run["x"] && "LOOP_UNDECLARED"              → RED
F5 尾句 = run["x"].to_s                              → RED
F6 尾句 = case ... end                               → RED
F7 尾句 = begin ... end                              → RED
F8 尾句 = "LOOP_UNBOUNDED"（已宣告的 code）           → RED
E1 加入 rescue 子句                                   → RED
E2 加入 ensure 子句                                   → RED
```

F8 特別請看：尾句回傳**已宣告**的 code 仍然 RED。
凍結的是**形狀**，不是「有沒有漏掉 code」—— 形狀一鬆，全集的論證就不成立。

### B. no-op 對照組，必須維持 GREEN

```
N1 中段 if（值被丟棄），尾句仍是 nil    → GREEN
N2 中段方法呼叫，尾句仍是 nil           → GREEN
```

我的結果：**2 / 2 維持 GREEN。**

### C. 前三輪 C1~C12 回歸

**11 RED / 1 GREEN**，唯一 GREEN 是 C11（你上一輪已裁決合理）。

### D. 其餘回歸

| 項目 | 結果 |
| --- | --- |
| 逐 code 改名 parity（15 個） | 15 RED / 0 GREEN |
| Guard parity（17 條 return site） | 17 RED / 0 GREEN，assertion 15 / exception 2 |
| 既有判定（對比修正前 `main` 的 24 案） | exact code 逐字相同，只新增本卡的 4 案 |
| Ruby validators | 21 PASS / 0 FAIL |
| 四支 Python engine | 全 PASS |
| `git diff --check` | clean |
| 檔案大小 | validator 380 行、lib 159 行，皆 `< 400` |

既有 evaluator 判斷邏輯逐字未改，17 條 return 一個都沒動。請確認：

```
git diff 14cf20a..81e1e86 -- scripts/validate_ai_work_record_loop_contract.rb
```

## 6. FP-2-A 的已知後果（Owner 已簽核接受）

`SSP-291` 已 merge 進 `main` 的 `evidence_profile_failure` 有**完全相同**的隱式回傳缺口
（我實測確認：同手法注入 → GREEN）。依 `FP-2-A` 不在本卡處理，
已開 `.work/CARD-SSP291-EXIT-SHAPE-BACKLOG-20260911.md`。

`loop_return_contract` 模組本身已是泛用的（`source_path` + `evaluator_name` 皆為參數），
屆時只需改中性名稱並接上。

## 7. FP-4-A 停損（已簽核，在此重申）

若本輪仍因「某種 Ruby 構造沒被涵蓋」被判 NO_GO，**不再修 validator**：
整張 `SSP302-ERROR-CODE-COVERAGE` 標 `DEFERRED`，保留 `14cf20a` 已無爭議的改善，
剩餘完整性問題轉獨立 backlog，不再阻塞 `SSP-307`。

若你有 finding，請一併說明它屬於「closeout 沒做到 Owner 簽定的規格」
還是「Owner 簽定的規格本身不足」—— 前者我會修，後者依 FP-4-A 走 DEFER。

## 8. 邊界（未變）

沒有做 branch-level coverage machinery、沒有改既有錯誤語意或 evaluator 判斷邏輯、
沒有重開 F-04 / F-05、沒有動上游、沒有新增外部套件（`Ripper` 是 stdlib）。

請就本 closeout 給 `GO` 或 `NO_GO`。
