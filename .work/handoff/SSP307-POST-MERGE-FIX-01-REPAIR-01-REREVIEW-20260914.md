# SSP-307 Post-Merge Fix 01 Repair 01 — 定點 re-review 交付包

同一條 review line。只收 `SSP307-PMF01-F-01`。

## 1. 鎖定

```
base                536f110
original_review     78ea865aa02fe9f114bf994b09483fabcd42ffb6   （immutable，NO_GO）
repair_commit       0cccba8245eee85b3eac53eba306c28d27f6f323
branch              cc/ssp307-per-turn-cadence-fix
```

定點 diff：`git diff 78ea865..0cccba8245eee85b3eac53eba306c28d27f6f323`

## 2. 收法

只改契約文字，`規格/v0.1/codex-native-adapter.yaml` 的 `design_note`／
`task_started_note`，不動任何 `.rb`。你已明講「不需要改 evaluator 邏輯」。

**修正前**：830-session 逐 session 分布數字（624/830、611/830）被文字
描述成「818-session corpus」，而 `measured_native_vocabulary.
sampled_sessions` 本身確實是 818——兩個不同時間點、不同方法的量測被
混用同一個數字。

**修正後**：明確拆成兩句——`measured_native_vocabulary` 的 818 是原始
實作時凍結的 vocabulary snapshot；830 是本輪獨立、另外跑的逐 session
cadence scan，並說明兩次掃描時間點不同（真實時間過去、session 數量
從 818 增加到 830）。

## 3. 請重播

```
grep -n "818\|830" 規格/v0.1/codex-native-adapter.yaml
```

我的結果：每一處引用 830 的地方都明確標註「this round」／「as it exists
now」；唯一保留的 818 只出現在 `sampled_sessions: 818` 本身，與明確
指稱「the 818-session vocabulary snapshot」的排除句裡。不再有把 830
的數字歸到 818 corpus 的文字。

## 4. Gate

```
ruby scripts/validate_*.rb                     → 23 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
```

契約 278 行（< 400）。validator 逐字未改。

## 5. 未動的部分

生命週期修法本身（`lifecycle_event_map` 清空）、`CODEX_MAPPING_TARGET_
MISMATCH` 移除——你明確不列 finding，本輪未重開。

請就 `SSP307-PMF01-F-01` 給 `GO` 或 `NO_GO`。
