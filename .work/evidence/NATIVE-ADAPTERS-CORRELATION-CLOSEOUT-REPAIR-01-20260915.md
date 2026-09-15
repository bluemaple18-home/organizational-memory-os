# Native Adapters Correlation Closeout Repair 01 — evidence

日期：2026-09-15　branch：`cc/native-adapters-correlation-v2`
原 review commit：`a01f26c`（immutable）　base：`28438bb`

收 1 筆 finding（P1）。驗證屬實，純文字修正，不改 evaluator 邏輯——
與 reviewer 指出的範圍一致。

## 驗證

`grep -n "event_envelope_fields"` 在修正前的兩份契約裡各找到一處
真正的問題：

```
codex-native-adapter.yaml:106       ...event_envelope_fields, which
                                     includes native_correlation_ref...
claude-code-native-adapter.yaml:121 ...event_envelope_fields.native_correlation_ref),
```

兩處都在寫「為什麼恢復 lifecycle mapping 是安全的」核心說明段落裡，
且都宣稱 `ai-work-record-hook.yaml` 的 `event_envelope_fields` 欄位
就叫 `native_correlation_ref`，並宣稱 Hook 的批次組裝是**依它自動**
scope 的。兩者都是機械式改名（`sed s/task_ref/native_correlation_ref/`）
留下的殘留——這段文字是 `POST_MERGE_FIX_02`／`POST_MERGE_FIX_01` 的
舊敘述，是**上一輪送審被 NO_GO 之前**寫的，改名腳本跑過去卻沒有人工
複查這段核心 justification 是否還成立。我在後來新增 `FP-1-A` 的
`native_correlation_ref_rule` 區塊時寫對了，但沒有回頭檢查同一份檔案
裡更早的舊段落，漏掉了。

## 修法

只改契約文字，兩份 `design_note` 各自的舊段落，不動任何 `.rb` 檔：

1. 移除「Hook 的 `event_envelope_fields` 就叫 `native_correlation_ref`」
   與「批次組裝依它自動 scope」兩個錯誤宣稱。
2. 新增一段 `SPEC_FREEZE FP-1-A / FP-3-A` 敘述，明確寫：
   - Hook 真正的欄位是 `task_ref`，不是 `native_correlation_ref`；
     必須是 OMOS task-card URN，跟原生 `turn_id`／`prompt_id` 是不同
     身分。
   - `hook_capture_failure` 不依 `task_ref` 分組——逐筆驗 URN 格式後，
     對整個 `raw` 陣列去重＋replay，沒有斷言同批只有一個 `task_ref`。
   - `native_correlation_ref` 本身**不會自動恢復任何東西**——它只是
     給呼叫端一個真實、穩定的 per-turn 識別碼。真正讓映射安全，仍然
     需要呼叫端 (a) 把 `native_correlation_ref` 解析成這個事件真正
     屬於的 task-card `task_ref`，(b) 每個 `task_ref` 各自組一次
     `hook_capture_failure` 呼叫。兩者都是呼叫端責任，本 Adapter
     不做、也不宣稱做。

## 驗證

```
grep -n "event_envelope_fields.native_correlation_ref\|scoped per native_correlation_ref\|Hook's batch\|own Hook batch" 規格/v0.1/codex-native-adapter.yaml 規格/v0.1/claude-code-native-adapter.yaml
→ 無殘留
```

三支受影響 validator 各自 PASS。

## Gate

```
ruby scripts/validate_*.rb                     → 23 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
```

檔案大小：`codex-native-adapter.yaml` 334 行（原 321）、
`claude-code-native-adapter.yaml` 363 行（原 344）。皆在 `< 400` 內。

## 本輪沒有做的事

- 沒有改任何 `.rb` evaluator 邏輯——reviewer 明確指出不需要。
- 沒有重開 FP-2-A（`stop_hook_active`）——reviewer 已接受。
- 沒有動 `ai-work-record-hook.yaml`。
