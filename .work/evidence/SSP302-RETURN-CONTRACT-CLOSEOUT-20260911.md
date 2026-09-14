# SSP-302 Closeout — 出口形狀凍結　evidence

日期：2026-09-11　branch：`cc/ssp302-error-code-coverage`
spec-freeze：`SSP302-RETURN-CONTRACT-SPEC-FREEZE-20260911`（Owner 簽 `B A A A`）
**這不是 repair-03。** repair 線已於第三輪 hard stop 關閉。

## 實作（FP-1-B）

`LoopReturnContract.exit_shape_violations`：

- `bodystmt` 不得有 `rescue` / `rescue-else` / `ensure` 子句。
- 最後一句必須恰好是 `nil` 字面量。

加上既有顯式 return 分類，方法只剩兩種回傳途徑 —— 被分類過的顯式 return，
或尾端那個 `nil`。**出口集合成為全集，不再是逼近。**

validator 在原有三層 assertion **之前**先驗出口形狀：出口形狀不成立時，
後面的集合比對本來就不是全集。

## 我在本輪自行發現並更正的一個錯誤（主動回報）

spec-freeze 卡原先寫「D2~D4 三個變體都 GREEN，缺口成立」。
closeout 實作時我用 Ruby 實際執行驗證，發現 **D2 的判定是錯的**：

```ruby
def d2(x)
  "LOOP_UNDECLARED" if x == true   # 值被丟棄
  nil
end
d2(true)  # => nil
```

我當時的注入把違規 expression 放在**倒數第二句**，它是 no-op，方法實際回傳 `nil`。
所以 D2 的 GREEN 是**正確行為**，不是缺口。真缺口是 D1 / D3 / D4
——「**尾句本身**就是違規 expression」。

finding 與 Owner 簽核不受影響（D1/D3/D4 已足以證立），但我的證據陳述不精確。
**這是我第三次在自撰 evidence 裡放進未經實際執行驗證的判斷**
（前兩次：SSP-302 TIGHTEN-F-02 的「只差一欄」、SSP-291 的「19 個負例全差一個 leaf」）。

因此本輪驗收刻意加入 **no-op 對照組**，要求它們維持 GREEN ——
不只證明「該紅的紅」，也證明「不該紅的沒紅」。spec-freeze 卡已就地更正。

## FP-3-A 驗收

### A. 真正的隱式回傳（尾句即違規 expression）—— 必須全 RED

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
| E1 | `rescue` 子句 | RED/assertion |
| E2 | `ensure` 子句 | RED/assertion |

**10 RED / 0 GREEN，全部 assertion-RED。**

F8 值得一提：即使尾句回傳的是**已宣告**的 code，仍然 RED ——
凍結的是**形狀**，不是「有沒有漏掉 code」。形狀一鬆，全集的論證就不成立。

### B. no-op 對照組 —— 必須維持 GREEN

| # | 注入 | 結果 |
| --- | --- | --- |
| N1 | 中段 `if`（值被丟棄） | GREEN |
| N2 | 中段方法呼叫 | GREEN |

**2 / 2。** 證明斷言不是「動什麼都變紅」。

### C. 前三輪 C1~C12 回歸

**11 RED / 1 GREEN。** 唯一 GREEN 是 C11（單引號、code 已宣告），
reviewer 上一輪已明示「合理，不列 finding」。

### D. 其餘回歸

| 項目 | 結果 |
| --- | --- |
| 逐 code 改名 parity（15 個） | **15 RED / 0 GREEN** |
| Guard parity（17 條 return site） | **17 RED / 0 GREEN**，assertion 15 / exception 2 |
| 既有判定（對比修正前 `main` 的 24 案） | **exact code 逐字相同**，只新增本卡的 4 案 |
| Ruby validators | 21 PASS / 0 FAIL |
| 四支 Python engine | 全 PASS |
| `git diff --check` | clean |
| `validate_ai_work_record_loop_contract.rb` | 380 行（`< 400`） |
| `scripts/lib/loop_return_contract.rb` | 159 行（`< 400`） |

既有 evaluator 判斷邏輯逐字未改，17 條 return 一個都沒動。

## FP-2-A 的已知後果（Owner 已簽核接受）

`SSP-291` 已 merge 的 `evidence_profile_failure` 有**完全相同**的隱式回傳缺口
（實測：同手法注入 → GREEN）。依 `FP-2-A` 不在本卡處理，已開
`.work/CARD-SSP291-EXIT-SHAPE-BACKLOG-20260911.md`。
該 backlog 卡記載：`loop_return_contract` 模組本身已是泛用的
（`source_path` + `evaluator_name` 皆為參數），屆時只需改名並接上。

## FP-4-A 停損（已簽核，在此重申）

若本卡送定點 re-review 後仍因「某種 Ruby 構造沒被涵蓋」被判 NO_GO，
**不再修 validator**：整張 `SSP302-ERROR-CODE-COVERAGE` 標 `DEFERRED`，
保留 `14cf20a` 已無爭議的改善（`LOOP_MISSING_FIELD` 補齊、控制測資對齊、
15/15 code 覆蓋），剩餘完整性問題轉獨立 backlog，不再阻塞 `SSP-307`。
