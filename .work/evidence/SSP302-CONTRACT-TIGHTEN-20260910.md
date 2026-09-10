# Evidence｜SSP-302 契約強化（F-04 CLOSED 語意 + F-05 timeout 反向一致性）

- 卡：`.work/CARD-SSP302-CONTRACT-TIGHTEN-20260910.md`
- Tier：T1｜Lane B
- branch：`cc/ssp302-contract-tighten`（off `main` @ `f2e47ca`）
- 前置：repo #2 / #3 adapter mapping 皆已 `ACCEPTED_GO` + merged（閘門已開）

## 交付物

| 檔 | 說明 | 行數 |
|---|---|---|
| `規格/v0.1/ai-work-record-loop.yaml` | `termination.timeout_reached_rule`、`run_record.required_present_rule`、`error_contract` +2、`required_negative_fixtures` +2 | +18 |
| `scripts/validate_ai_work_record_loop_contract.rb` | evaluator +2 return；`EXPECTED_LOOP_ERROR_CODES` 與 2 條 rule 的結構斷言 | 312（< 400） |
| `規格/v0.1/fixtures/ai-work-record-loop-positive-fixtures.json` | +1 判別控制正例 | +15 |
| `規格/v0.1/fixtures/ai-work-record-loop-negative-fixtures.json` | +2 負例 | +33 |

差異為**純新增**（109 insertions / 0 deletions），未改動任何既有 case。

## F-04（採卡上預設選項 (a)）

`terminal_condition == ALL_REQUIRED_PRESENT` 時，最後一輪 `remaining_gaps` 必須為空，否則
`LOOP_REQUIRED_PRESENT_WITH_GAPS`。`MAX_ITERATIONS_REACHED` 維持較弱語意（達上限、普通
auto-fixable 缺口可交人），`CLOSED` 在該條件下仍成立 —— 未新增 outcome 值。

**置放順序**：檢查放在既有第 10 步（mandatory-stop gap 逐輪檢查）**之後**，因此帶
`requires_human_decision` / `auto_fixable:false` 的缺口仍回報原本更精確的
`LOOP_SKIPPED_HUMAN_DECISION` / `LOOP_UNFIXABLE_NOT_LOUD`，既有負例判定完全不變。

- 新正例 `LOOP_POS_MAX_ITERATIONS_WITH_ORDINARY_GAP`：`CLOSED` + `MAX_ITERATIONS_REACHED` +
  最後一輪留一個 `auto_fixable:true` 缺口 → allow。這是選項 (a) 的**判別控制**，證明沒有
  過度收緊。
- 新負例 `LOOP_NEG_REQUIRED_PRESENT_WITH_GAPS`：同樣的缺口配 `ALL_REQUIRED_PRESENT`
  → `LOOP_REQUIRED_PRESENT_WITH_GAPS`。

兩者只差 `terminal_condition` 一個欄位，正好把新規則的邊界夾出來。

## F-05（等號邊界：必須嚴格大於）

`terminal_condition == TIMEOUT` 時要求 `elapsed_seconds > timeout_seconds`，否則
`LOOP_TIMEOUT_NOT_REACHED` —— 補上原本只有單向（`elapsed > timeout` 未 fail-loud →
`LOOP_OVER_TIMEOUT`）的另一半。放在既有 timeout 檢查（第 2 步）正後方，兩者是同一條規則的
兩個方向。

- 新負例 `LOOP_NEG_TIMEOUT_NOT_REACHED` 刻意取 `elapsed == timeout`（300/300），直接把卡上
  明定的「嚴格大於」邊界釘住。

## 自查時發現並補掉的既有缺口（spec ↔ enforcement 綁定）

第一輪 parity 探針時抓到：**YAML 的 `error_contract` 與新規則文字完全沒有被 validator 斷言**
（原 SSP-302 就沒有這層綁定），因此移除 YAML 裡的新 code 宣告或規則文字，gate 仍會綠 ——
宣告與 enforcement 可以漂移。依卡上 Scope「結構斷言相應更新」補上：

- `EXPECTED_LOOP_ERROR_CODES`（14 個 code）必須逐字等於 YAML `error_contract` 的 key 集合。
- `termination.timeout_reached_rule` / `run_record.required_present_rule` 必須存在。

## 驗收對照

| Acceptance | 結果 |
|---|---|
| 1. F-04 收緊 + `MAX_ITERATIONS_REACHED` 仍 allow | PASS（新正例 + 新負例夾邊界） |
| 2. F-05 收緊，等號邊界明定 | PASS（`elapsed == timeout` 負例） |
| 3. 既有正例/負例判定不變 | PASS（純新增，0 deletions；validator 逐例比對 exact code） |
| 4. TIMEOUT 且 `elapsed > timeout` 正例 | PASS（既有 `LOOP_POS_TIMEOUT_TERMINATED` 305/300 已涵蓋，未重複新增） |
| 5. 每個新負例單一 mutation + exact code；移除 enforcement → RED | PASS（7 項 parity 全 RED） |
| 6. 全 gate + `git diff --check` | PASS |

## Gate

```
ruby validate_ai_work_record_loop_contract.rb   PASS（正例 6、負例 18）
全 20 個 Ruby validators                        PASS
validate_std_schema_engine.py (uv)              PASS
validate_cc_cross_layer_contract.py (uv)        PASS
git add -A && git diff --cached --check         clean
validator 行數                                   312（< 400）
```

## Enforcement parity（cp-based restore，7 項全 RED）

```
evaluator 移除 LOOP_TIMEOUT_NOT_REACHED            RED
evaluator 移除 LOOP_REQUIRED_PRESENT_WITH_GAPS     RED
F-05 邊界 >  改成 >=（等號視為逾時）                RED
YAML error_contract 移除 LOOP_TIMEOUT_NOT_REACHED  RED
YAML error_contract 移除 LOOP_REQUIRED_PRESENT_WITH_GAPS  RED
YAML 移除 timeout_reached_rule                     RED
YAML 移除 required_present_rule                    RED
```

## 未擴張的範圍

- 只動 loop 契約的這兩點；未改其他 SSP-302 enforcement、未動上游（SSP-298/299/300）、
  未重跑 S03。
- 未新增 outcome 值（維持 `CLOSED / BLOCKED / FAILED_LOUD`）。
- 未新增 package；未動任何 `LOCKED_OWNER_ACCEPTED` schema。
- stop conditions 皆未觸發：既有 5 個正例對兩條新規則都天然成立
  （`ALL_REQUIRED_PRESENT` 那筆最後一輪無缺口；`TIMEOUT` 那筆 305 > 300）。
