# 收 repo #5 F-01 — repair-01 evidence

回應 `1f3b0f4` 的 NO_GO（P1×1 + P2×1）。

## P1：用「現行 upstream 名稱」過濾，等於把要抓的孤兒自己濾掉

屬實，而且**這正是本卡存在的目的**，所以是最該收的一筆。

原本：

```ruby
pipeline_canonical_steps = personal_core_pipeline.select { |step| promotion_steps.include?(step) }
```

`VERIFICATION_LEGACY` 不在現行 upstream 裡 → 被 `select` 濾掉 → 剩下的剛好
等於 `covers` → PASS。孤兒殘留完全隱形。

修法照 reviewer 指示：取 `core_pipeline` 中「`covers` 首元素到末元素」的
**實際切片**，逐項比對，不做任何過濾。

```ruby
first_index = personal_core_pipeline.index(covers.first)
last_index  = personal_core_pipeline.rindex(covers.last)
actual_slice = personal_core_pipeline[first_index..last_index]
assert(actual_slice == covers, ...)
```

重播 reviewer 的案例：

```
core_pipeline: ... CANDIDATE → VERIFICATION_LEGACY → VERIFICATION → ACCEPTANCE ...
covers:            [CANDIDATE, VERIFICATION, ACCEPTANCE, RECORD]

→ FAIL core_pipeline 在 covers 涵蓋範圍內的實際內容必須逐項等於 covers
       （不得殘留或插入）：實際=[..., VERIFICATION_LEGACY, ...] 宣告=[...]
```

## P2：pointer matcher 的 prefix bypass

屬實。原本 `/\A<pointer>[\w.]*\z/` 會讓
`ai-work-record-boundary.promotion_pathology` 通過——`[\w.]*` 把 `ology`
吃掉了。

改成 `/\A<pointer>(\.[\w.]+)?\z/`：要嘛整值就是 pointer，要嘛延伸段前面
必須真的有一個 `.`。

```
假 pointer promotion_pathology        → FAIL（不再被當成綁定）
真 pointer .promotion_path.ordered_steps → PASS（未誤殺）
```

## 這兩個洞的共同型態（自我檢討，非 finding）

本卡連同前一輪，我已經在**同一個地方**犯了三次同類錯：

1. canonical gate 用整份檔案文字判定綁定（散文提一句就算數）
2. pointer matcher 的 prefix 太鬆（`promotion_pathology` 也算）
3. 用現行 upstream 名稱過濾後再比對（孤兒被自己濾掉）

三者都是「比對的**對象**選錯，而不是比對邏輯寫錯」——我一直在比一個已經
被自己前處理過、失去資訊的集合。之後寫這類綁定檢查時，第一個要問的是
「我比對的東西，有沒有在比之前就被我過濾掉了關鍵資訊」。

## Gate

```
ruby scripts/validate_*.rb（27 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
```

未改動 canonical 權威本身，未碰 F-02。
