# 收 repo #5 F-01 — repair-02 evidence

回應 `f56560c` 的 NO_GO（P1 regression + P2 未收乾淨）。

## P1（repair 自己引入的漏口）：`covers` 界定了自己的檢查範圍

屬實，而且是我這輪修法自己造成的——**第四次同型錯誤**：我讓被驗的一方
（`covers`）決定要驗多大範圍。把 `covers` 前端或尾端砍掉，被砍掉的
canonical 步驟就落到 `first_index..last_index` 區間之外，不再被任何檢查看到。

修法：補上**區間外檢查**。宣告範圍以外不得再出現任何 canonical 步驟——
少報一步，那一步就會出現在區間外而轉紅。

```
covers 砍掉前端 PERSONAL_MEMORY_CANDIDATE
  → FAIL ...covers 宣告範圍之外仍出現 canonical 步驟（covers 少報？）：PERSONAL_MEMORY_CANDIDATE
covers 砍掉尾端 PERSONAL_MEMORY_RECORD
  → FAIL ...（同上）：PERSONAL_MEMORY_RECORD
```

## P2：只驗字串形狀還是在猜

屬實。`.promotion_path.bogus` 形狀完全正確、子路徑根本不存在，照樣被當成
有效 pointer。

修法照你的建議，**不再用 regex 猜**：把 pointer 去掉前綴後逐段 `dig` 進
boundary，dig 得到東西才算數。

```
ai-work-record-boundary.promotion_path.bogus            → FAIL（不再算綁定）
ai-work-record-boundary.promotion_path.ordered_steps    → PASS（未誤殺）
ai-work-record-boundary.promotion_path.receipts_required → PASS（另一條真實子路徑）
```

## 主動揭露：我用這輪的教訓去測自己的新檢查，找到一個邊界

送出前我拿「這個新檢查有沒有信任被驗方控制的東西」去問自己的兩道新檢查。
`resolvable_pointer?` 沒問題（完全 resolve 到上游結構）。但區間外檢查有一個
**已知邊界**：

```
把 VERIFICATION_LEGACY 放在 covers 宣告範圍「之外」（例如 OBJECT_LINKING 後面）
  → 兩支 gate 都沒抓到
```

原因：區間外檢查用「是否為現行 canonical 步驟」來辨識 straggler，孤兒名稱
不在現行清單裡，所以看不見——**又是同一個過濾陷阱，只是被擠到區間外**。

我沒有硬修它，理由是：區間外的項目並未宣稱自己是 canonical restatement 的
一部分（`core_pipeline` 本來就有 SOURCE／OBJECT_LINKING 等自己的階段），要
在那裡辨識「長得像 canonical 但已不是」需要語意猜測，那正是我這幾輪一直
做錯的事。**我選擇揭露而不是再猜一次**，請 reviewer 裁決這個邊界是否可接受，
或指定要用什麼事實去綁。

## 這是第四次同型錯誤

含前幾輪：整份檔案文字判定綁定／pointer prefix 太鬆／用現行名稱過濾後再
比對／讓被驗方界定檢查範圍。四者都是**比對的對象被前處理過或由被驗方決定**。

若這一輪再被打穿同一型，我不會再嘗試第五次，會停下來把這個結構問題升級。

## Gate

```
ruby scripts/validate_*.rb（27 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
```
