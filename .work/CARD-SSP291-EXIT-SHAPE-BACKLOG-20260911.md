---
id: SSP291-EXIT-SHAPE-BACKLOG-20260911
status: BACKLOG
type: implementation
tier: T1
jira: SSP-291（已 ACCEPTED_GO + merged @ 7cfe2fe，本卡為後續強化）
origin: "SSP302-RETURN-CONTRACT-SPEC-FREEZE-20260911 FP-2-A：Owner 簽核只套 SSP-302，SSP-291 同類缺口另開"
---

# SSP-291 evaluator 出口形狀凍結（後續強化）

## Measured gap（實測，非推論）

`scripts/validate_personal_evidence_profile_contract.rb` 的 `evidence_profile_failure`
與 `loop_closeout_failure` 有**完全相同**的隱式回傳缺口。實測方式：
把尾端 `nil` 換成尾句隱式回傳一個未宣告的 code，完整 gate 仍綠。

`SSP-291` 的 `error_contract` 同樣宣稱「等於 evaluator 可回傳的 code 集合」，
但實作只驗到顯式 `return` 的 code（而且是 regex 掃描，比 SSP-302 現況更弱）。

## 為什麼不在 SSP-302 那張卡一起修

Owner 於 `SSP302-RETURN-CONTRACT-SPEC-FREEZE-20260911` 簽 `FP-2-A`：
只收 SSP-302，避免在一張卡裡動到另一條已驗收的 review line。

## 修法（等 SSP-302 closeout 取得 GO 後再排）

沿用 `scripts/lib/loop_return_contract.rb` 的機制 —— 該模組已是泛用的
（`source_path` + `evaluator_name` 皆為參數），SSP-291 只需：

1. 把 `reachable_failure_codes` 從 regex 掃描改為呼叫該模組。
2. 加上 `exit_shape_violations` 斷言。
3. 驗收比照 `FP-3-A`：F1~F8、E1~E2 全 RED，N1~N2 維持 GREEN，
   既有 2 正例 / 39 負例判定逐案不變。

模組名稱屆時應一併從 `loop_return_contract` 改為中性名稱（兩支共用）。

## 不做

不改 `evidence_profile_failure` 的任何判斷邏輯；不動上游；不新增外部套件。
