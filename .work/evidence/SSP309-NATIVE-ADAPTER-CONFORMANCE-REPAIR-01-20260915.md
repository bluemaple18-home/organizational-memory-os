# SSP-309 repair-01 — evidence

回應 `6ebd527` 大 review NO_GO（P2×2）。同一條 review line，只收這兩筆。

## F-01：C-01 只驗 key 存在，被 `*_rule: null` 騙過

`platform_specific_field?` 原本只檢查 `own_rule_keys.include?(key)`——key
存在就算數，不管值是什麼。修法：改讀該 key 的**值**，要求是非空
`String` 才算「真的寫了理由」；`nil`／空字串一律不豁免。

## F-02：C-02 掃整份 raw text、count>=2，被任意 comment 騙過

`error_contract_conformance_failures` 原本對 raw file text 做
`String#scan(full_code).size >= 2`——档尾加兩行無語意 comment 就能讓
count 到 2。修法：不再讀 raw file text。新增
`collect_rationale_strings`／`rationale_text`，遞迴走過整份 parsed YAML，
只收 key 為 `design_note` 或以 `_rule` 結尾、且值是非空 `String` 的節點
文字，串成一份 rationale 文字；平台專屬錯誤碼必須真的出現在這份文字裡
才算有文件化理由。comment 不會進 parsed YAML，這個攻擊面在結構上消失，
不是靠額外規則擋。

## 驗證：重放 reviewer 給的兩個原始 mutation（對真實檔案，非 self-test）

```
F-01 復現：codex-native-adapter.yaml 的 mapping_run.fields 加
  other_platform_field，並加 other_platform_field_rule: null
  → FAIL mapping_run 核心欄位集合須相等 ...（正確被擋）

F-02 復現：codex-native-adapter.yaml 的 error_contract 加
  CODEX_REAL_NEW_DIFFERENCE，只在檔尾加兩行 comment（不進 parsed 欄位）
  → FAIL ... 沒有在任何 design_note／*_rule 敘述性欄位裡被引用（正確被擋）
```

兩次都用 Python 腳本直接改真實檔案、跑 validator 確認變紅、再
`git checkout --` 還原，`git diff` 確認 0 行差異，非 `cp` 備份／還原（因為
這次是還原**既有已 committed 的檔案**到 HEAD，不是還原 validator 腳本本身
——validator 腳本本身的 enforcement-parity 探針另外用 cp 驗證，見下）。

## 驗證：新版兩條斷言本身的 enforcement-parity（cp 備份／還原）

先前（`6ebd527`）已對兩條 assert 個別中和過一次；本輪修法改變了兩個
function 的內部邏輯（不是外層 assert 位置），額外對新邏輯跑同一組
self-test（見腳本內 `self_test_failures` 區塊）：F-01／F-02 復現案例 +
兩個對照組（真的寫了理由的平台專屬欄位應該被豁免；真的被 rationale
引用的錯誤碼應該通過）全部通過。

## Gate

```
ruby scripts/validate_*.rb（全部 24 支）              → PASS
document_adapter_mapping_instances.py                → PASS
cc_cross_layer_contract.py                            → PASS
jira_adapter_mapping_instances.py                     → PASS
std_schema_engine.py                                  → PASS
git diff --check                                       → clean
git status --short                                     → 只有
  scripts/validate_ssp309_native_adapter_conformance.rb 被改動
```

檔案大小：210 行（原 148 行），仍遠低於 400 行限制。
