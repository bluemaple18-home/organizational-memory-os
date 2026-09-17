# 收 repo #5 F-01 repair-02 — 定點 re-review 交付包

同一條 review line。收 `f56560c` 的 P1 regression + P2。

## 鎖定

```
base                8bf224c
original_review     1f3b0f4
repair_01           f56560c   （NO_GO：P1 regression + P2 未收乾淨）
repair_commit       <見對話中的派工區塊>
branch              cc/core-pipeline-promotion-binding
```

## 收法

**P1**：補區間外檢查——`covers` 宣告範圍之外不得再出現任何 canonical 步驟。
`covers` 因此無法少報：少報一步，那步就落在區間外而轉紅。

**P2**：不再用 regex 猜形狀。pointer 去掉前綴後逐段 `dig` 進 boundary，
**resolve 得到東西才算綁定**。

## 請重播

```bash
# P1-A：covers 砍掉前端 PERSONAL_MEMORY_CANDIDATE → 應 FAIL
# P1-B：covers 砍掉尾端 PERSONAL_MEMORY_RECORD    → 應 FAIL
# P2  ：ai-work-record-boundary.promotion_path.bogus → 應 FAIL
# 對照：.ordered_steps / .receipts_required         → 應 PASS（不得誤殺）
```

## 主動揭露：我自己測出一個未修的邊界

送出前我拿「這個檢查有沒有信任被驗方控制的東西」回頭問自己的新檢查，
找到一個**兩支 gate 都抓不到**的情形：

```
把 VERIFICATION_LEGACY 放在 covers 宣告範圍之外（例如 OBJECT_LINKING 後面）
  → 兩支 gate 皆 PASS
```

原因是區間外檢查仍用「是否為現行 canonical 步驟」辨識 straggler，孤兒名稱
看不見——同一個過濾陷阱被擠到區間外。

**我沒有硬修**：區間外的項目並未宣稱自己屬於 canonical restatement
（`core_pipeline` 本來就有 SOURCE／OBJECT_LINKING 等自有階段），要在那裡
辨識「長得像 canonical 但已不是」需要語意猜測——那正是我這幾輪一直做錯的
事。請裁決這個邊界可否接受，或指定要綁什麼事實。

## 這是同型錯誤第四次

整份文字判定綁定／prefix 太鬆／過濾後比對／被驗方界定範圍。若這輪再被打穿
同一型，我不再嘗試第五次，會停下來升級這個結構問題。

## Gate

```
ruby scripts/validate_*.rb（27 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
```
