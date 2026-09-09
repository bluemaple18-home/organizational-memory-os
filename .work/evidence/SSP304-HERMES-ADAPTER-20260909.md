# Evidence｜SSP-304 AIWR-07 Hermes 薄 Adapter

- 卡：`.work/CARD-SSP304-HERMES-ADAPTER-20260909.md`
- Tier：T1
- branch：`cc/ssp304-hermes-adapter`（off `main` @ `df34064`）
- lane：B

## 交付物

| 檔 | 說明 | 行數 |
|---|---|---|
| `規格/v0.1/ai-work-record-hermes-adapter.yaml` | Adapter 契約：event_mapping / authority / optional_dependency / compatibility / disable_and_rollback / no_org_wide_install / mapping_run / error_contract / cross_reference / hard_stops | 153 |
| `scripts/validate_ai_work_record_hermes_adapter_contract.rb` | 薄 validator：結構斷言 + `hermes_adapter_failure` / `hermes_rollback_failure` 兩純函式 evaluator；交叉讀 skill／task-card-record／harness／boundary；沿用 `scripts/lib/omos_contract_helpers.rb` | 263 |
| `規格/v0.1/fixtures/ai-work-record-hermes-adapter-positive-fixtures.json` | `hermes_adapter_cases` ×3（MAPPED / INCOMPATIBLE_FAIL_LOUD / DISABLED）+ `hermes_rollback_cases` ×2 | — |
| `規格/v0.1/fixtures/ai-work-record-hermes-adapter-negative-fixtures.json` | `hermes_adapter_negative_cases` ×10 + `hermes_rollback_negative_cases` ×1，各單一 mutation + `expected_failure_code` + `covers_hermes_negative_fixture` | — |

檔案大小守 `.agentskills/docs/coding-standards.md` §2（validator 263 < 400）。

## 契約重點（對應 Acceptance）

- **只映射既有 Skill I/O**：`allowed_map_targets` = `ai-task-card-record.lifecycle_event_to_status`
  的 key ∪ `ai-work-record-skill.input_contract.seed_field_keys`（validator 在執行期由兩份
  上游 yaml 計算）；`hermes_event_map` 某筆 `mapped_to ∉` 該集合 → `HERMES_MAP_TARGET_UNKNOWN`。
- **不加語意**：`event_mapping.adapter_adds_fields` 必須為空；run `adapter_adds_fields` 非空
  → `HERMES_ADAPTER_ADDS_SEMANTICS`。
- **不取得治理 authority**：`grants_acceptance` / `grants_permission` / `grants_canonical_writer`
  皆 `false`；run 帶 `personal_acceptance_ref` / `permission_decision_ref` /
  `canonical_write_receipt_ref` 等 5 個 forbidden 欄位 → `HERMES_EXCEEDS_AUTHORITY`。
- **可選依賴**：`hermes_required: false`、`core_flow_without_hermes: SUPPORTED`；run 宣稱
  `hermes_required: true` 或 `core_flow_blocked_without_hermes: true` → `HERMES_MANDATORY`。
- **相容性 fail-loud**：`supported_hermes_versions` 非空；mapping run `hermes_version` 不在支援
  清單但 `outcome != INCOMPATIBLE_FAIL_LOUD` → `HERMES_INCOMPAT_NOT_LOUD`。
- **非全員安裝**：`requires_all_users_install: true` → `HERMES_ORG_WIDE_INSTALL`。
- **mapping_run**：`outcome ∉ {MAPPED, INCOMPATIBLE_FAIL_LOUD, DISABLED}` → `HERMES_INVALID_OUTCOME`；
  `MAPPED` 但 `adapter_output_ref` 非 `urn:omos:` URN → `HERMES_OUTPUT_NOT_REF`；`MAPPED` 但
  `mapped_to ∉ allowed_map_targets` → `HERMES_MAP_TARGET_UNKNOWN`。
- **停用回退**：`disable_and_rollback` = `disable_switch: true` + `fallback: CORE_FLOW_DIRECT`
  + `side_effects[]` 逐副作用列 `{name, teardown, failure_state}`（event_subscription /
  version_probe_cache / partial_event_map 三個，非 fixed-diff）；`outcome == DISABLED` 但仍有
  `adapter_output_ref` → `HERMES_DISABLED_STILL_MAPPING`；side_effect 缺欄位 →
  `HERMES_ROLLBACK_SIDE_EFFECT_UNSPECIFIED`；缺 disable_switch / 錯 fallback →
  `HERMES_ROLLBACK_MISSING_FIELD`。
- **fail-loud**：`authority.error_behavior: FAIL_LOUD`（與 boundary `error_behavior_enum` 交叉鎖）；
  run 有 `error` 但 `ok != false` → `FAIL_SILENT`。
- **cross_reference**：`must_match` 四 pointer 字串 exact，引用目標
  （`lifecycle_event_to_status`、skill `seed_field_keys`、harness `schema_id`、boundary
  `error_behavior_enum`）存在。
- **runtime_independence: true**：fixtures 無 runtime-specific 欄位。

## 驗證

### gate 全綠（branch head）

```
17 Ruby validator（含 hermes-adapter 本卡 + harness/loop/hook/skill/boundary/task-card-record
regression + personal-memory aggregator + STD-00~03 + 4 個 personal-memory slice）  exit=0 PASS
std_schema_engine.py   PASS  coverage 12/12、16/16、9/9（不變）
validate_cc_cross_layer_contract.py   PASS
git diff --check   clean
```

### 負例 enforcement parity（移除 enforcement → gate 轉紅）

逐一 neutralize 每個 `return "<CODE>"`：`HERMES_EXCEEDS_AUTHORITY`（forbidden fields）／
`FAIL_SILENT`／`HERMES_MANDATORY`／`HERMES_ORG_WIDE_INSTALL`／`HERMES_ADAPTER_ADDS_SEMANTICS`／
`HERMES_MAP_TARGET_UNKNOWN`（event_map loop）／`HERMES_INVALID_OUTCOME`／
`HERMES_DISABLED_STILL_MAPPING`／`HERMES_INCOMPAT_NOT_LOUD`／`HERMES_OUTPUT_NOT_REF`／
`HERMES_ROLLBACK_SIDE_EFFECT_UNSPECIFIED` —— 全部移除後 `ruby scripts/validate_ai_work_record_hermes_adapter_contract.rb`
exit 1（RED），還原後 `PASS`。11 個 enforcement 全數 load-bearing。

### DoD 三類案例

- Hermes mapping：`HERMES_POS_MAPPED`（`hermes_event_map` 全 valid、`outcome: MAPPED`、
  `hermes_version: 1.1` ∈ 支援清單、`adapter_output_ref` 為 URN）→ allow。
- 相容性負例：`HERMES_NEG_INCOMPAT_NOT_LOUD`（`hermes_version: 9.9` + `outcome: MAPPED`）→
  `HERMES_INCOMPAT_NOT_LOUD`；`HERMES_POS_INCOMPATIBLE_FAIL_LOUD`（`hermes_version: 2.0` +
  `outcome: INCOMPATIBLE_FAIL_LOUD`）→ allow。
- 停用回退：`HERMES_POS_DISABLED`（`outcome: DISABLED`、無 `adapter_output_ref`）→ allow；
  `HERMES_NEG_DISABLED_STILL_MAPPING`（`DISABLED` 但仍帶 `adapter_output_ref`）→
  `HERMES_DISABLED_STILL_MAPPING`；rollback 契約 `HERMES_RB_POS_FULL` → allow，
  `HERMES_RB_NEG_SIDE_EFFECT_MISSING_FIELD` → `HERMES_ROLLBACK_SIDE_EFFECT_UNSPECIFIED`。
- 無全員安裝：`HERMES_NEG_ORG_WIDE_INSTALL`（`requires_all_users_install: true`）→
  `HERMES_ORG_WIDE_INSTALL`；`HERMES_NEG_MANDATORY`（`hermes_required: true`）→ `HERMES_MANDATORY`。

### 上游契約未被改動

`git diff --name-status df34064..HEAD` 僅新增 4 檔 + 卡 + evidence + 待辦重整；未碰
`ai-work-record-skill.yaml`／`ai-task-card-record.yaml`／`ai-work-record-harness.yaml`／
`ai-work-record-boundary.yaml`／`ai-work-record-loop.yaml`／`ai-work-record-hook.yaml` 或其
validator（`git diff --stat` 對這些檔為空）。`allowed_map_targets` 由執行期讀上游 yaml 計算，
若上游 lifecycle events / seed keys 改變會自動失配。dup-key fail-closed 對 3 個新檔已跑
（`StrictJsonObject` / `assert_unique_yaml_mapping_keys`，來自共用 lib）。
