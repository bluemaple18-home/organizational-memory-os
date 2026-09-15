# Native Adapters Correlation Closeout Repair 01 — 定點 re-review 交付包

同一條 review line。只收 1 筆 P1 finding。

## 1. 鎖定

```
base                28438bb
original_review     a01f26c5118fef69572dfcdcd654ac71f7bf41e1   （immutable，NO_GO）
repair_commit       a3b39a7b07619f6c0551192b66b22a056068e974
branch              cc/native-adapters-correlation-v2
```

定點 diff：`git diff a01f26c..a3b39a7`

## 2. 收法

你指出：兩份契約各有一段更早寫的 `design_note`
（`POST_MERGE_FIX_02`／`POST_MERGE_FIX_01`），仍宣稱 Hook 的
`event_envelope_fields` 欄位叫 `native_correlation_ref`、且批次組裝
依它自動 scope——這正是 `FP-1-A`／`FP-3-A` 要推翻的兩個宣稱，機械式改名
（`sed task_ref -> native_correlation_ref`）留下的殘留，就寫在「為何
恢復 lifecycle mapping 是安全的」核心 justification 裡。

驗證屬實：這兩段文字是**上一輪送審被 NO_GO 之前**寫的舊敘述，我後來
新增 `FP-1-A` 的 `native_correlation_ref_rule` 區塊時寫對了，但沒有
回頭複查同一份檔案裡更早的段落。

**只改契約文字，不動任何 `.rb` evaluator 邏輯**（跟你指定的範圍一致）：
移除兩處錯誤宣稱，改寫成 `native_correlation_ref` 本身**不會自動恢復
任何東西**——只給呼叫端一個真實穩定的 per-turn 識別碼；真正讓映射安全
仍需要呼叫端 (a) 把它解析成事件真正屬於的 task-card `task_ref`，
(b) 每個 `task_ref` 各自組一次 `hook_capture_failure` 呼叫。兩者都是
呼叫端責任，本 Adapter 不做也不宣稱做。

## 3. 請重播

```
grep -n "event_envelope_fields.native_correlation_ref\|scoped per native_correlation_ref\|Hook's batch\|own Hook batch" 規格/v0.1/codex-native-adapter.yaml 規格/v0.1/claude-code-native-adapter.yaml
```

我的結果：無殘留。

## 4. Gate

```
ruby scripts/validate_codex_native_adapter_contract.rb        → PASS
ruby scripts/validate_claude_code_native_adapter_contract.rb  → PASS
ruby scripts/validate_ai_work_record_hook_contract.rb         → PASS
ruby scripts/validate_*.rb（全部）                              → 23 PASS / 0 FAIL
四支 Python engine                                              → 全 PASS
git diff --check                                                → clean
```

檔案大小：`codex-native-adapter.yaml` 334 行（原 321）、
`claude-code-native-adapter.yaml` 363 行（原 344）。皆在 `< 400` 內。

## 5. 未動的部分

`FP-2-A`（`stop_hook_active`）你已接受，未重開；`ai-work-record-hook.yaml`
未改動；所有 evaluator 邏輯逐字未變。

請就這筆 P1 finding 給 `GO` 或 `NO_GO`。
