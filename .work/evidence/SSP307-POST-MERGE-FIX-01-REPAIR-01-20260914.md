# SSP-307 Post-Merge Fix 01 Repair 01 — evidence

日期：2026-09-14　branch：`cc/ssp307-per-turn-cadence-fix`
原 review commit：`78ea865`（immutable）　base：`536f110`

收 1 筆 finding：`SSP307-PMF01-F-01`（P2）。驗證屬實，純文字修正，
不改任何 evaluator 邏輯。

## 驗證

`grep -n "818\|830"` 確認修正前的契約文字裡，`design_note` 與
`task_started_note` 都把 830-session 逐 session 分布數字（624/830、
611/830）描述成「818-session corpus」，而 `measured_native_vocabulary.
sampled_sessions` 本身確實是 818——這是兩個不同時間點、不同方法的量測
被文字混用同一個數字，reviewer 判讀正確。

## 修法

只改契約文字（`規格/v0.1/codex-native-adapter.yaml`），不動任何
`.rb` 檔：

1. `design_note`：明確拆成兩句——`measured_native_vocabulary` 的 818 是
   原始實作時凍結的 vocabulary snapshot；本輪的 830 是獨立、另外
   跑的逐 session cadence scan，並說明兩次掃描時間點不同、真實時間
   過去導致 session 數量增加（818 → 830）。
2. `task_started_note`：同步修正，明確排除「818-session vocabulary
   snapshot」與「原始實作時的聚合總數」兩種誤讀。
3. `task_complete_note` 本來就沒有引用具體 session 總數字樣，未受影響，
   未改動。

## 驗證

```
grep -n "818\|830" 規格/v0.1/codex-native-adapter.yaml
```

現在每一處引用 830 的地方都明確標註「this round」／「as it exists now」；
唯一保留的 818 只出現在 `sampled_sessions: 818`（`measured_native_
vocabulary` 本體，本來就正確）與明確指稱「the 818-session vocabulary
snapshot」的排除句裡。不再有把 830 的數字歸到 818 corpus 的文字。

## Gate

```
ruby scripts/validate_*.rb                     → 23 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
```

契約 278 行（< 400 硬上限）。validator 未改動。

## 本輪沒有做的事

- 沒有改任何 evaluator 邏輯（reviewer 明確指出不需要）。
- 沒有重開生命週期修法本身或 `CODEX_MAPPING_TARGET_MISMATCH` 移除
  （reviewer 明確不列 finding）。
- 沒有重新做 830-session 的逐 session 掃描——數字本身沒有爭議，
  爭議只在文字歸屬，不需要重新量測。
