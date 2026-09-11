---
id: SSP302-ERROR-CODE-COVERAGE-REPAIR-01-20260911
status: SUPERSEDED_BY_REPAIR_02
type: repair
review_line: SSP-302 error-code 契約完整性
original_review_sha: 19b099bd3bb14325d1b6cca6c22b1d0535bbf505
base_sha: 096cea3
verdict_being_repaired: NO_GO (P0=0, P1=0, P2=1, P3=0)
tier: T1
---

# SSP-302 Repair 01 — SSP302-F-01 掃描語法繞過

👉 [假設與目標確認]
- 目標：只收 `SSP302-F-01`。讓「宣告集合 == evaluator 實際可回傳集合」這個命題
  無法被合法但掃不到的 Ruby return 語法靜默繞過。
- 邊界：不引入 coverage 工具、不做 branch-level coverage machinery（reviewer 明說不需要）；
  不改任何既有錯誤語意；不重開 F-04 / F-05；不動上游。
- 驗收：見 Acceptance。

## 被修的 finding

`SSP302-F-01`（P2）：`reachable_loop_failure_codes` 用
`/return "([A-Z][A-Z0-9_]*)"/` 掃描，只認雙引號字面量。在 evaluator 新增

```ruby
return 'LOOP_UNDECLARED' if run["x"]
```

是 Ruby 真正可回傳的新 code，但 scanner 看不到；既有 15 個 code、YAML、鎖定常數、
負例都不必改，三層 assertion 全綠。**這直接推翻交付包的核心命題。**

根因：regex scanner 必然是語法特定的，而我只保證了「掃到的都對」，
沒有保證「沒有掃不到的」。

## 修法（採 reviewer 提供的第二條路）

reviewer 給了兩條：(a) 把取得方式做到無法被任何合法 return 語法繞過；
(b) 明確機器限制 evaluator 只能採用 scanner 可辨識的 return 形式，再補 bypass mutation。

選 **(b)**。理由：(a) 要用 regex 涵蓋 Ruby 全部 return 語法（插值、heredoc、常數、
方法回傳、`%w` 等）本質上做不完，做了也只是換一個更難察覺的 under-approximation；
(b) 把不確定性關掉——形式白名單是可窮舉的，違反即轉紅。

1. `ALLOWED_EVALUATOR_RETURN`：evaluator 內每一條 `return` 語句只能是
   `return nil` 或 `return "<CODE>"`（可帶 `if` / `unless` 修飾）。其他一律轉紅。
2. scanner 同時放寬到單引號，讓單引號 code **同時**踩中形式白名單與完整性斷言（雙層）。
3. 抽出 `loop_evaluator_body`，掃描與形式檢查共用同一段函式本體，不會各掃各的。
4. YAML `error_contract_binding` 增加 `evaluator_return_form_rule`，把這個限制寫進契約。

## Acceptance

1. 在 evaluator 插入 `return 'LOOP_UNDECLARED' if ...` → gate 轉紅（reviewer 指定的 bypass mutation）。
2. 其他繞過形式（字串插值、heredoc、常數、`return` 接方法呼叫）同樣轉紅。
3. 既有 15 個 code 的逐一改名 parity 維持全紅。
4. guard parity 17 條維持全紅。
5. 既有 28 案（6 正例 / 22 負例）判定與 exact code 完全不變。
6. 全 21 validator + 4 Python engine + `git diff --check` 全 PASS；validator `< 400` 行。

## Stop conditions

- 若形式白名單會逼 evaluator 改寫既有判斷邏輯 → 停，回 Owner（本卡不得改錯誤語意）。
