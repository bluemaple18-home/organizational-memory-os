# 大 Review 交接｜SSP-302 契約強化（F-04 + F-05）

## 1. 審什麼

`規格/v0.1/ai-work-record-loop.yaml` + `scripts/validate_ai_work_record_loop_contract.rb`
的兩點 fail-closed 收緊，清 SSP-302 大 review 遺留的 F-04（P3）/ F-05（P2）。

## 2. Frozen commit

- branch：`cc/ssp302-contract-tighten`
- base：`f2e47ca`（main）
- review 範圍：`git diff f2e47ca..<checkpoint SHA>`

## 3. 契約變更

| | 規則 | 新 code |
|---|---|---|
| F-04 | `terminal_condition == ALL_REQUIRED_PRESENT` → 最後一輪 `remaining_gaps` 必須為空 | `LOOP_REQUIRED_PRESENT_WITH_GAPS` |
| F-05 | `terminal_condition == TIMEOUT` → `elapsed_seconds` 必須**嚴格大於** `timeout_seconds` | `LOOP_TIMEOUT_NOT_REACHED` |

`MAX_ITERATIONS_REACHED` + `CLOSED` + 普通 auto-fixable 缺口**仍然合法**（選項 (a)，未新增
outcome 值）。

## 4. 特別請看的點

1. **F-04 的置放順序**：新檢查放在既有 mandatory-stop gap 檢查之後，目的是讓
   human-decision / unfixable 缺口維持回報原本更精確的 code。請確認這個順序沒有讓任何
   既有負例的 exact code 改變。
2. **F-05 的等號邊界**：契約明定「嚴格大於」，負例用 `elapsed == timeout`（300/300）。
   請確認 `>=` 不是更合理的選擇（若是，這是 spec 問題不是 code 問題）。
3. **我自查補上的 spec↔enforcement 綁定**：原 SSP-302 的 `error_contract` 與規則文字從未被
   validator 斷言，移除 YAML 宣告 gate 仍綠。已補 `EXPECTED_LOOP_ERROR_CODES` 與 2 條 rule
   的存在斷言。請確認這層綁定本身正確（14 個 code 是否確實等於 evaluator 可回傳集合）。
4. **判別控制正例**：`LOOP_POS_MAX_ITERATIONS_WITH_ORDINARY_GAP` 與負例
   `LOOP_NEG_REQUIRED_PRESENT_WITH_GAPS` 只差 `terminal_condition` 一欄，請確認這確實夾出
   了新規則的邊界而非其他因素。

## 5. Mutation 要求

不要只讀 validator。請翻某個已知良好 fixture 的一個 bit，確認 allow↔deny 真的翻轉；
並確認移除任一新 enforcement（evaluator return 或 YAML 宣告）會讓 gate 轉紅。

## 6. 邊界

read-only against frozen commit；不重寫架構；只有 P0/P1 阻擋。不重開已 `ACCEPTED_GO` 的
SSP-302 其他 enforcement、不動上游 SSP-298/299/300。

## 7. 已跑的 gate

見 `.work/evidence/SSP302-CONTRACT-TIGHTEN-20260910.md`：20/20 Ruby validator、STD schema
engine、cross-layer、`git diff --check` 全 PASS；7 項 enforcement parity 全 RED-on-tamper。

## 8. 上游未被改動

`git diff --name-status f2e47ca..HEAD` 僅 4 個檔（loop yaml / loop validator / 兩份 loop
fixture）+ 卡與 evidence；未碰任何 `LOCKED_OWNER_ACCEPTED` schema。
