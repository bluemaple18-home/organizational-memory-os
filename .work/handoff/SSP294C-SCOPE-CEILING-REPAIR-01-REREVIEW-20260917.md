# SSP-294 切片 C repair-01 — 定點 re-review 交付包

同一條 review line。只收 `61ba39b` 的那一筆 P1。

## 鎖定

```
base                9864303
original_review     61ba39b   （NO_GO，P1=1）
repair_commit       <見對話中的派工區塊>
branch              cc/ssp294-scope-ceiling
```

## 收法

FP-2-A 原本只驗散文有沒有寫著「不能綁 promotion_path」，沒驗契約結構本身有
沒有真的綁。新增結構化掃描：走遍整份契約，任何字串值**整值**符合
`ai-work-record-boundary.promotion_path`（或子路徑）的形狀即違規。用
`\A...\z` 整值比對，散文提及不誤殺。

## 請重播（你的原始 exploit）

```yaml
ceiling_binding:
  promotion_path_ref: ai-work-record-boundary.promotion_path.ordered_steps
```

我的結果：`FAIL FP-2-A 違規：...ceiling_binding.promotion_path_ref`
（修正前 PASS）。另測兩個變體（裸前綴、藏在陣列裡）與一個對照（散文提及不
誤殺），結果一致。

## 無 repair regression

逐 return site parity 重跑：7/7 全紅（未動 evaluator 本體）。30 支既有
validator 全 PASS，`git diff --check` clean。

## 依你指示登 backlog、未在本輪動

兩筆 P2（覆蓋斷言宣稱過寬／`from_scope == to_scope` 語意未定義）已登
`文件/待辦重整.md`，修法已知，未在本輪修。

## Gate

```
ruby scripts/validate_*.rb（30 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
```
