# SSP-309 repair-01 — 定點 re-review 交付包

同一條 review line。只收 `6ebd527` 的 P2×2。

## 鎖定

```
base                5e511c4
original_review     6ebd527   （NO_GO，P2=2）
repair_commit       31b7d56
branch              cc/ssp309-native-adapter-conformance
```

定點 diff：`git diff 6ebd527..31b7d56` —— 只動
`scripts/validate_ssp309_native_adapter_conformance.rb`，沒有動任何契約
檔案或其他 validator。

## 逐筆收法

### F-01（P2）：C-01 只驗 key 存在

`platform_specific_field?` 原本 `own_rule_keys.include?(key)`——key 存在
就算數。改成讀該 key 的值，要求是非空 `String` 才給豁免；`nil` 不算。

### F-02（P2）：C-02 掃 raw text、count>=2

`error_contract_conformance_failures` 不再接受／讀取 raw file text。新增
`rationale_text(spec)`：遞迴走 parsed YAML，只收 `design_note` 或
`*_rule` 這些敘述性欄位的非空字串值，串成一份文字；平台專屬錯誤碼必須
真的出現在這份文字裡。comment 不在 parsed YAML 裡，這條攻擊面在結構上
消失。

## 請重播（用你原本的兩個 mutation，對真實檔案）

```
# F-01：codex-native-adapter.yaml 的 mapping_run.fields 加
# other_platform_field，並加 other_platform_field_rule: null
# 預期：validator FAIL（mapping_run 核心欄位集合須相等）

# F-02：codex-native-adapter.yaml 的 error_contract 加
# CODEX_REAL_NEW_DIFFERENCE，只在檔尾加兩行 comment（不進任何
# design_note／*_rule 欄位）
# 預期：validator FAIL（沒有在任何 design_note／*_rule 敘述性欄位裡被引用）
```

我這邊兩個都用 Python 腳本直接改真實檔案重放過，皆正確 FAIL，
`git checkout --` 還原後 `git diff` 0 行差異——細節見
`.work/evidence/SSP309-NATIVE-ADAPTER-CONFORMANCE-REPAIR-01-20260915.md`。

## Gate

```
ruby scripts/validate_ssp309_native_adapter_conformance.rb  → PASS（正例，真實契約現狀）
ruby scripts/validate_*.rb（全部 24 支）                      → PASS
四支 Python schema engine                                     → PASS
git diff --check                                               → clean
```

檔案大小：210 行（原 148），仍在 `< 400` 內。

## 請只判斷

這兩筆 P2 是否已關閉——不擴大範圍。C-01 原計畫刪除第三條斷言那部分你
已接受，未重開。
