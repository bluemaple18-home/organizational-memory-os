# 收 repo #5 F-01 repair-01 — 定點 re-review 交付包

同一條 review line。收 `1f3b0f4` 的 P1×1 + P2×1。

## 鎖定

```
base                8bf224c
original_review     1f3b0f4   （NO_GO，P1=1 / P2=1）
repair_commit       <見對話中的派工區塊>
branch              cc/core-pipeline-promotion-binding
```

## 收法

**P1**（本卡核心目的，你抓得最準的一筆）：原本用
`select { promotion_steps.include?(step) }` 過濾後再比對——孤兒名稱不在現行
upstream 裡，直接被自己濾掉。改成取 `core_pipeline` 中 `covers` 首尾之間的
**實際切片**逐項比對，不過濾。

**P2**：`[\w.]*` 讓 `promotion_pathology` 通過。改成 `(\.[\w.]+)?`，延伸段前
必須真的有 `.`。

## 請重播

```bash
# P1：core_pipeline 插入 VERIFICATION_LEGACY 在 CANDIDATE 與 VERIFICATION 之間
#     （covers 不動）→ 應 FAIL
# P2：某契約用 ai-work-record-boundary.promotion_pathology 當 pointer → 應 FAIL
# 對照：用 ai-work-record-boundary.promotion_path.ordered_steps → 應 PASS（不得誤殺）
ruby scripts/validate_ai_work_record_boundary_contract.rb
ruby scripts/validate_canonical_promotion_binding.rb
```

我的結果與上述一致。

## 自我檢討（非 finding，但請一併看）

含前一輪，我在這個區域已經犯了三次同類錯：整份檔案文字判定綁定、pointer
prefix 太鬆、用現行名稱過濾後再比對。三者都是**比對的對象選錯**——我比的是
一個已經被自己前處理過、失去資訊的集合，而不是原始事實。

如果你在覆核時看到還有第四處同型，請直接點出來，那代表我這個盲區還沒清乾淨。

## Gate

```
ruby scripts/validate_*.rb（27 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
```

## 請只判斷這兩筆

F-02 維持 P3 未動；canonical 權威本身未動。
