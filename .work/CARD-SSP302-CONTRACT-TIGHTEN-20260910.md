---
id: SSP302-CONTRACT-TIGHTEN-20260910
status: DRAFT_OWNER_REVIEW
type: implementation
jira: SSP-302（後續強化，原卡已 ACCEPTED_GO）
lane: B
tier: T1
---

# SSP-302 契約強化：F-04 CLOSED 語意 + F-05 timeout 反向一致性

👉 [假設與目標確認]
- 目標：清 `文件/待辦重整.md` 規範債 backlog 中 SSP-302 的兩條 review 遺留項——
  F-04（P3，`CLOSED` 是否代表完整收乾淨）與 F-05（P2，`terminal_condition == TIMEOUT`
  是否應要求 `elapsed_seconds > timeout_seconds`）。對已 merged 的
  `規格/v0.1/ai-work-record-loop.yaml` + `scripts/validate_ai_work_record_loop_contract.rb`
  做兩個 fail-closed 收緊，各補正負 fixtures，走大 review。
- 邊界：只動 loop 契約的這兩點語意；不改其他 SSP-302 enforcement、不動上游、不重跑 S03。
- 驗收：見 Acceptance；兩條收緊各有正負例，enforcement parity RED，既有正例仍 PASS。

## Objective

1. **F-04**：`outcome_condition_map` 目前允許 `CLOSED` + `MAX_ITERATIONS_REACHED` 且不要求
   最後一輪 `remaining_gaps` 為空 → `CLOSED` 可能被解讀為「已收乾淨」但實際仍有普通缺口。
   收緊選項（擇一，卡上定）：
   - (a) `terminal_condition == ALL_REQUIRED_PRESENT` 時，最後一輪 `remaining_gaps` 必須為空
     （新 code `LOOP_REQUIRED_PRESENT_WITH_GAPS`）；`MAX_ITERATIONS_REACHED` 仍可留普通缺口
     （代表「達上限，普通缺口交人」）。
   - (b) 更嚴：`CLOSED` 只能配 `ALL_REQUIRED_PRESENT`；`MAX_ITERATIONS_REACHED` 需要一個
     非成功 outcome（需新增 outcome，blast radius 大 → 傾向 (a)）。
   本卡預設 **(a)**。
2. **F-05**：`terminal_condition == TIMEOUT` 時要求 `elapsed_seconds > timeout_seconds`
   （或明確定義 `>=` 等號邊界），否則新 code `LOOP_TIMEOUT_NOT_REACHED` —— 補上目前只單向
   （`elapsed > timeout` 未 fail-loud → `LOOP_OVER_TIMEOUT`）的另一半。

## Root question

如何在不改其他 enforcement、不動上游、行為對既有正例不變的前提下，把 SSP-302 的
`CLOSED` 語意與 `TIMEOUT` 一致性收成雙向 fail-closed？

## Traces to

- `規格/v0.1/ai-work-record-loop.yaml`（SSP-302，已 merged @ `47c8ea4`）。
- `.work/CARD-SSP302-REPAIR-01-20260909.md` + `.work/evidence/SSP302-REREVIEW-01-20260909.yaml`
  的 F-04 / F-05 條目。
- `文件/待辦重整.md` 規範債 backlog。
- Requirement IDs：以穩定 slice ID `SSP302-TIGHTEN-S01` 追溯。

## Dependencies / Blockers / Current frontier

- Dependencies：SSP-302 = `ACCEPTED_GO` + merged。
- Blockers：無。
- Current frontier：`SSP302-TIGHTEN-S01`。

## Scope

- `規格/v0.1/ai-work-record-loop.yaml`：`outcome_condition_map` 註記 (a) 規則；`termination`
  補 `timeout_reached_rule`；`error_contract` +`LOOP_REQUIRED_PRESENT_WITH_GAPS` +`LOOP_TIMEOUT_NOT_REACHED`；
  `required_negative_fixtures` +2。
- `scripts/validate_ai_work_record_loop_contract.rb`：evaluator 補兩個 return；結構斷言相應更新。
- `規格/v0.1/fixtures/ai-work-record-loop-{positive,negative}-fixtures.json`：+1 正例（TIMEOUT
  且 `elapsed > timeout`）+2 負例。
- `文件/待辦重整.md` 規範債 backlog 標記 F-04 / F-05 已清。

## Constraints

- 只動這兩點；不改其他 SSP-302 enforcement 或 fixture 判定。
- 不新增 outcome 值（維持 `CLOSED / BLOCKED / FAILED_LOUD`）。
- validator 維持 `< 400`；不新增 package。推 branch，不 merge。

## Product fit

- Measured gap：SSP-302 大 review 留下的 F-04（P3）/ F-05（P2），reviewer 建議 backlog 補。
- Why not less：不補則 `CLOSED` 語意歧義、`TIMEOUT` 一致性單向，未來 Harness/主管視圖
  引用 loop outcome 時會踩到。
- Why not more：不重開 S03、不動上游、不新增 outcome。
- Rollback：兩個 return + fixtures，可單獨 revert。

## Acceptance

1. F-04：`terminal_condition == ALL_REQUIRED_PRESENT` 但最後一輪 `remaining_gaps` 非空
   → `LOOP_REQUIRED_PRESENT_WITH_GAPS`；`MAX_ITERATIONS_REACHED` + `CLOSED` + 普通缺口仍 allow。
2. F-05：`terminal_condition == TIMEOUT` 但 `elapsed_seconds <= timeout_seconds`
   → `LOOP_TIMEOUT_NOT_REACHED`（等號邊界在卡上明定為「必須嚴格大於」）。
3. 既有 4 正例 + repair 01 新增正例全部仍 PASS；既有負例判定不變。
4. 新增正例：`TIMEOUT` 且 `elapsed_seconds > timeout_seconds` 且 `FAILED_LOUD` → allow。
5. 每個新負例單一 mutation + exact failure code；移除對應 enforcement → gate 轉紅。
6. `ruby scripts/validate_ai_work_record_loop_contract.rb` + 其餘 17 validator + schema engine
   + cross-layer + `git diff --check` 全 PASS。

## Stop conditions

- 若收緊 (a) 會讓既有正例轉紅 → 停，回 Owner 確認 `MAX_ITERATIONS_REACHED` 語意。
- 若需新增 outcome 值才能表達 → 停，回 Owner（那是 blast radius 大的變更）。

## Likely files

- `規格/v0.1/ai-work-record-loop.yaml`
- `scripts/validate_ai_work_record_loop_contract.rb`
- `規格/v0.1/fixtures/ai-work-record-loop-positive-fixtures.json`
- `規格/v0.1/fixtures/ai-work-record-loop-negative-fixtures.json`
- `文件/待辦重整.md`
- `.work/evidence/SSP302-CONTRACT-TIGHTEN-20260910.md`

## Evidence

`.work/evidence/SSP302-CONTRACT-TIGHTEN-20260910.md`
