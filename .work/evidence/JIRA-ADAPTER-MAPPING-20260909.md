# Evidence｜Jira Adapter Mapping（repo #3）

- 卡：`.work/CARD-JIRA-ADAPTER-MAPPING-20260909.md`
- Tier：T1
- branch：`cc/jira-adapter-mapping`（off `main` @ `ba518a0`，與 repo #2 並行）
- lane：A（repo 施工順序 #3 / EMEM-02 前置）

## 交付物

| 檔 | 說明 | 行數 |
|---|---|---|
| `規格/v0.1/jira-adapter-mapping.yaml` | Jira Cloud issue 文字欄位（summary/description/comment/ADF）→ STD-01 + Jira anchor profile 的確定性 mapping：raw_evidence_projection（compound source_version、source_aliases、transport）/ source_anchor_projection / reconciliation / determinism / cross_reference | 166 |
| `scripts/validate_jira_adapter_mapping_contract.rb` | 薄 validator：結構斷言（mapping 值皆為 STD-01 + Jira profile schema 合法欄位／enum／const）+ 純函式 `jira_mapping_failure(projection, target)` evaluator；交叉讀 2 個 schema JSON；沿用 `scripts/lib/omos_contract_helpers.rb` | 208 |
| `規格/v0.1/fixtures/jira-adapter-mapping-positive-fixtures.json` | `jira_mapping_cases` ×2（DESCRIPTION + reconciliation / COMMENT_BODY） | — |
| `規格/v0.1/fixtures/jira-adapter-mapping-negative-fixtures.json` | `jira_mapping_negative_cases` ×11，各單一 mutation + `expected_failure_code` + `covers_jira_map_negative_fixture` | — |

檔案大小守 `.agentskills/docs/coding-standards.md` §2（validator 208 < 400）。

## 契約重點（對應 Acceptance）

- **確定性身份**：`source_identity.native_id_basis` 鎖 `JIRA_CLOUD_ID_PLUS_ISSUE_ID`（cloud_id +
  issue_id），非 native 基底 → `JIRA_MAP_NONDETERMINISTIC_IDENTITY`。
- **compound source_version**：`basis: COMPOUND_OBSERVED` + `kind: UPDATED_AT_DIGEST` +
  非空 `secondary_digest`（ADF sha256）；basis/kind 對 `raw-evidence-envelope.schema.json`
  的 `source_version.basis`/`kind` enum 交叉驗證；不符 → `JIRA_MAP_VERSION_NOT_COMPOUND`。
- **source_aliases**：issue key rename 加 alias，evidence identity（cloud_id + issue_id）不變。
- **payload reference-only**：`I_JSON` + `RFC8785_JCS`，`payload_ref` 為 reference、無 inline
  → `JIRA_MAP_PAYLOAD_INLINE`。
- **anchor profile 綁定 STD-02 locked profile**：`profile == JIRA_CLOUD_ENTITY_SEGMENT_V1`
  且等於 `source-anchor-jira-cloud-entity-segment-v1.schema.json` 的 profile const；
  `profile_details` key set == 該 schema 的 `profile_details.required`（10 欄，`additionalProperties: false`）
  → `JIRA_MAP_PROFILE_MISMATCH` / `JIRA_MAP_PROFILE_DETAILS_MALFORMED`。另驗
  `deployment_type == CLOUD`、`entity_type == issue`、`issue_id` 符 `^[0-9]+$`、
  `text_selector.unit == UNICODE_CODE_POINT` + `START_INCLUSIVE_END_EXCLUSIVE` + `end >= start >= 0`。
- **selector**：`selectors` 含 `JSON_POINTER` → `JIRA_MAP_SELECTOR_MISSING`。
- **reconciliation**：`changed_identity == true` → `JIRA_MAP_RECONCILIATION_CHANGES_IDENTITY`；
  `detected_gap == true` 但 `emitted_evidence_or_gap != true` → `JIRA_MAP_RECONCILIATION_SILENT_GAP`。
- **fail-loud**：mapping 有 `error` 但 `ok != false` → `FAIL_SILENT`。
- **不重定義 STD**：`hard_stops` 明訂；validator 只讀 schema 不寫。

## 驗證

### gate 全綠（branch head）

```
19 Ruby validator（含 jira-adapter 本卡 + AIWR ×8 + personal-memory aggregator + 4 slice
+ STD-00~03 + cross-layer）  exit=0 PASS
std_schema_engine.py   PASS  coverage 12/12、16/16、9/9（不變）
validate_cc_cross_layer_contract.py   PASS
git diff --check   clean
```

### 負例 enforcement parity（移除 enforcement → gate 轉紅）

逐一 neutralize 每個 `return "<CODE>"`：`JIRA_MAP_UNKNOWN_FIELD_KIND` / `FAIL_SILENT` /
`JIRA_MAP_FIELD_NOT_IN_TARGET_SCHEMA` / `JIRA_MAP_NONDETERMINISTIC_IDENTITY` /
`JIRA_MAP_PAYLOAD_INLINE` / `JIRA_MAP_VERSION_NOT_COMPOUND` / `JIRA_MAP_PROFILE_MISMATCH` /
`JIRA_MAP_SELECTOR_MISSING` / `JIRA_MAP_PROFILE_DETAILS_MALFORMED`(keyset) /
`JIRA_MAP_RECONCILIATION_CHANGES_IDENTITY` / `JIRA_MAP_RECONCILIATION_SILENT_GAP` ——
全部移除後 `ruby scripts/validate_jira_adapter_mapping_contract.rb` exit 1（RED），還原後 `PASS`。
11 個 enforcement 全數 load-bearing。

### DoD：正向 + 相容性 + 停用回退

- 正向：`JIRA_MAP_POS_DESCRIPTION`（compound version + JSON_POINTER anchor + reconciliation
  detected_gap 且已 emit）與 `JIRA_MAP_POS_COMMENT_BODY`（POLL ingestion + comment json_pointer）
  → allow。
- 相容性 / reconciliation：`JIRA_MAP_NEG_VERSION_NOT_COMPOUND`（`CONTENT_ONLY`）→ 拒；
  `JIRA_MAP_NEG_RECONCILIATION_CHANGES_IDENTITY` / `JIRA_MAP_NEG_RECONCILIATION_SILENT_GAP` → 拒。
- 11 個負例覆蓋 field kind 不合法／投影非目標 schema 欄位／非 native 身份／payload 內嵌／
  version 非 compound／profile 不符／selector 缺／profile_details key set 錯／
  reconciliation 改 identity／reconciliation 靜默漏 gap／fail-silent。

### 上游 schema 未被改動

`git diff --name-status ba518a0..HEAD` 僅新增 4 檔 + 卡 + evidence；未碰
`raw-evidence-envelope.schema.json`（STD-01）／`source-anchor-jira-cloud-entity-segment-v1.schema.json`
（STD-02 profile）—— 皆 `LOCKED_OWNER_ACCEPTED`。`target` enum / const / property 集合由執行期
讀 schema JSON。dup-key fail-closed 對 3 個新檔已跑（`StrictJsonObject` /
`assert_unique_yaml_mapping_keys`，來自共用 lib）。

---

## Repair 01（2026-09-10）— NO_GO(4×P1) 針對性修復

卡：`.work/CARD-JIRA-ADAPTER-MAPPING-REPAIR-01-20260910.md`。原 review SHA `170da7f` 不動；
repair delta = `170da7f..<repair SHA>`（同一條 review line）。

### F-01 positive = 完整 STD instance + JSON Schema instance gate

- positive fixtures 重寫：`JIRA_MAP_POS_DESCRIPTION` / `JIRA_MAP_POS_COMMENT_BODY` /
  `JIRA_MAP_POS_RECONCILE_NEWER_WITH_RENAME`，各帶 compact `projection` ＋完整
  `raw_evidence_instance`（STD-01）＋ `source_anchor_instance`（STD-02 Jira profile）。
- 新 companion `scripts/validate_jira_adapter_mapping_instances.py`（jsonschema 4.25.1 +
  rfc3339-validator 0.1.4）：Draft 2020-12 `Registry`（raw-evidence + base source-anchor +
  Jira profile，keyed by `$id`）驗每個 positive instance 對 locked target schema 合法、
  每個 instance-negative 確實被拒。
- yaml `instance_validation.engine` 指向 companion；Ruby validator assert engine 存在、
  每個 positive 帶兩個 instance。
- 新 `jira-adapter-mapping-instance-negative-fixtures.json` ×3：RawEvidence 缺
  `idempotency_basis`；Jira anchor 缺 base required `quote`；Jira anchor
  `text_selector` 巢狀 shape 錯。

### F-02 compound version machine-verifiable

- evaluator：`secondary_digest` 須 `^sha256:[0-9a-f]{64}$`
  （`JIRA_MAP_SECONDARY_DIGEST_MALFORMED`）；`source_version.value` 須為存在的 RFC3339(UTC Z)
  timestamp（`JIRA_MAP_VERSION_VALUE_INVALID`）。
- reconciliation `decision` 與觀測版本序一致性：`NEW_EVIDENCE` 須 `current > previous`、
  `NOOP` 須 `<=`，否則 `JIRA_MAP_RECONCILIATION_VERSION_DECISION_MISMATCH`。
- yaml `source_version` 加 `value_format` / `secondary_digest_format`；`reconciliation` 加
  `version_decisions`。
- 負例：`JIRA_MAP_NEG_SECONDARY_DIGEST_MALFORMED` / `JIRA_MAP_NEG_VERSION_VALUE_INVALID` /
  `JIRA_MAP_NEG_RECONCILIATION_VERSION_DECISION_MISMATCH`。
- 正例：`JIRA_MAP_POS_RECONCILE_NEWER_WITH_RENAME` 帶 previous/current version 比較。

### F-03 reconciliation identity 實際前後比較

- evaluator：reconciliation 帶 `previous_identity` / `current_identity`（各
  `{cloud_id, issue_id}`）→ component-wise 比較，不同即
  `JIRA_MAP_RECONCILIATION_IDENTITY_DRIFT`（不論自報旗標）；自報 `changed_identity == true`
  仍另判 `JIRA_MAP_RECONCILIATION_CHANGES_IDENTITY`。
- issue-key rename：`issue_key_change {from,to}` → `to` 須進 `raw_evidence.source_aliases`
  且 identity 不變，否則 `JIRA_MAP_ISSUE_KEY_RENAME_NOT_ALIASED`。
- yaml `source_identity.identity_components` / `reconciliation.identity_components` /
  `source_aliases.rule` 更新。
- 負例：`JIRA_MAP_NEG_RECONCILIATION_IDENTITY_DRIFT` / `JIRA_MAP_NEG_ISSUE_KEY_RENAME_NOT_ALIASED`。

### F-04 field_kind ↔ field_id / json_pointer binding

- evaluator：`profile_details.field_id == field_id_by_kind[field_kind]`
  （`JIRA_MAP_FIELD_ID_KIND_MISMATCH`）；`profile_details.json_pointer` 須以
  `json_pointer_prefix_by_kind[field_kind]` 開頭（`JIRA_MAP_JSON_POINTER_FIELD_MISMATCH`）。
- yaml 新增 `source_anchor_projection.json_pointer_prefix_by_kind` + `rule` 註記
  「locked Jira profile field_id 為任意非空字串，binding 只在本層強制」。
- 負例：`JIRA_MAP_NEG_FIELD_ID_KIND_MISMATCH` / `JIRA_MAP_NEG_JSON_POINTER_FIELD_MISMATCH`。

### 修復後 gate

```
ruby validate_jira_adapter_mapping_contract.rb               PASS
validate_jira_adapter_mapping_instances.py (uv)              PASS (positive_instances=6, instance_negatives=3)
全 19 Ruby validators（STD-00~03 / cross-layer / personal-memory / AIWR regression）  PASS
validate_std_schema_engine.py (uv)                           PASS (STD01 12/12, STD02 16/16, STD03 9/9)
validate_cc_cross_layer_contract.py (uv)                     PASS
enforcement parity（18× return "<CODE>" / key-set 判斷 neutralize）  每次 RED，還原 PASS
git add -A && git diff --cached --check                      clean
```

### 交付物（修復後）

| 檔 | 動作 | 行數 |
|---|---|---|
| `規格/v0.1/jira-adapter-mapping.yaml` | 改（value/secondary_digest format、json_pointer_prefix_by_kind、identity_components、version_decisions、instance_validation、error_contract +7、cross_reference、negative label +7） | 236 |
| `scripts/validate_jira_adapter_mapping_contract.rb` | 改（secondary_digest/RFC3339 檢查、field_id/json_pointer binding、reconciliation identity/rename/version-decision、instance-fixture 斷言） | 306 |
| `scripts/validate_jira_adapter_mapping_instances.py` | 新（JSON Schema Registry instance gate） | 113 |
| `規格/v0.1/fixtures/jira-adapter-mapping-positive-fixtures.json` | 改（3 case，compact projection + 完整 STD instance） | — |
| `規格/v0.1/fixtures/jira-adapter-mapping-negative-fixtures.json` | 改（18 mapping-semantic 負例） | — |
| `規格/v0.1/fixtures/jira-adapter-mapping-instance-negative-fixtures.json` | 新（3 instance-schema 負例） | — |

validator 306 / companion 113，守 `.agentskills/docs/coding-standards.md` §2（< 400）。

---

## Repair 02（2026-09-10）— Repair 01 再 review NO_GO(P1=4) 針對性修復

卡：`.work/CARD-JIRA-ADAPTER-MAPPING-REPAIR-02-20260910.md`。原 review SHA `170da7f`、Repair 01
`733a9e3` 皆不動；repair-02 delta = `733a9e3..<repair-02 SHA>`。集中修三件核心事 + json pointer
boundary，不改架構。

### F-03 identity 必填 + 綁實際 projected identity

- reconciliation 存在時 `previous_identity` / `current_identity` 皆必填、`cloud_id`/`issue_id`
  不得為空 → `JIRA_MAP_RECONCILIATION_IDENTITY_INCOMPLETE`（新 code）。
- `current_identity` 必須等於 `{cloud_id: profile_details.cloud_id, issue_id: profile_details.issue_id}`
  → 否則 `JIRA_MAP_RECONCILIATION_IDENTITY_DRIFT`。移除 rename 的「identity 沒帶＝穩定」退讓。
- YAML `reconciliation.identity_required: true` + rule 改寫。
- 負例：`RECONCILIATION_IDENTITY_INCOMPLETE`（只帶 previous）、`RECONCILIATION_CURRENT_NOT_PROJECTED`
  （previous==current 但 ≠ projected）；`SILENT_GAP` / `VERSION_DECISION_MISMATCH` 補 matching identity。

### F-02 version ordering 真 parse 比較

- `parse_instant` = `Time.iso8601`（`require "time"`）；`JIRA_MAP_VERSION_VALUE_INVALID` 改判
  parse 成功與否，移除自寫 `RFC3339_UTC_PATTERN`。
- decision 版本序：`current_instant > previous_instant`（Time 比較，非字串）。
- 負例：`VERSION_DECISION_FRACTIONAL`（NOOP + previous `12:00:00Z` / current `12:00:00.100Z`）。

### F-04 json pointer 真正定址

- `json_pointer_addresses_field?(pointer, prefix)` = `pointer == prefix || pointer.start_with?("#{prefix}/")`。
- `COMMENT_BODY` prefix `/fields/comment/comments/` → `/fields/comment/comments`（validator 常數 +
  YAML 同步）。
- 負例：`JSON_POINTER_PREFIX_BYPASS`（DESCRIPTION，`/fields/description_extra`）。

### F-01 regression — projection ↔ full STD instance 逐項綁定

- `projection_instance_consistency(test_case)`：逐項比對 compact projection 與完整 instance 的
  mapping-critical 欄位（profile / profile_details.{field_id,json_pointer,cloud_id,issue_id} /
  source_version.{basis,kind,value,secondary_digest} / payload.{structured_profile,
  canonicalization_profile,payload_ref} / provenance.ingestion_mode / source_system /
  native_id == issue_id / reconciliation.current_identity == instance identity）。任一不符 RED。
- YAML 新增 `projection_instance_consistency` 區塊（rule + bound_fields）。

### 修復後 gate

```
ruby validate_jira_adapter_mapping_contract.rb               PASS
validate_jira_adapter_mapping_instances.py (uv)              PASS (positive_instances=6, instance_negatives=3)
全 19 Ruby validators（含 AIWR / personal-memory regression）  PASS
validate_std_schema_engine.py (uv)                           PASS (STD01 12/12, STD02 16/16, STD03 9/9)
validate_cc_cross_layer_contract.py (uv)                     PASS
enforcement parity（cp-based restore）：
  neutralize IDENTITY_INCOMPLETE return                      RED
  neutralize current==projected 檢查                         RED
  parse_instant 比較換回字串比較                             RED（fractional 負例不再被拒）
  json_pointer helper 換回裸 start_with?(prefix)             RED（prefix-bypass 負例不再被拒）
  positive instance json_pointer / field_id drift            RED（projection↔instance 不一致）
git add -A && git diff --cached --check                      clean
```

### 交付物（Repair 02）

| 檔 | 動作 |
|---|---|
| `規格/v0.1/jira-adapter-mapping.yaml` | 改（reconciliation.identity_required + rule；json_pointer_prefix COMMENT_BODY；source_version rule；json pointer rule；新 projection_instance_consistency 區塊；error_contract +1；negative label +4） |
| `scripts/validate_jira_adapter_mapping_contract.rb` | 改（parse_instant / json_pointer_addresses_field? / identity_complete? helper；reconciliation 必填 identity + 綁 projected；version 決策 parse 比較；projection_instance_consistency；386 行） |
| `規格/v0.1/fixtures/jira-adapter-mapping-negative-fixtures.json` | 改（+4 負例；2 個既有 reconciliation 負例補 matching identity） |

validator 386 行、companion 113 行（< 400）。

---

## Repair 03（2026-09-10）— Repair 02 再 review NO_GO(P1=2) 針對性修復

卡：`.work/CARD-JIRA-ADAPTER-MAPPING-REPAIR-03-20260910.md`。`170da7f` / Repair 01 `733a9e3` /
Repair 02 `fb939c1` 皆不動；repair-03 delta = `fb939c1..<repair-03 SHA>`。只收 Repair 02 再
review 的 2 個 P1。

### F-01-F03-R02 — full instance source_identity end-to-end 綁到 (cloud_id, issue_id)

- `projection_instance_consistency()`（下沉共用 lib）新增：raw_evidence_instance 與
  source_anchor_instance 各驗 `source_system == jira-cloud` /
  `source_instance_id == profile_details.cloud_id` / `entity_type == "issue"` /
  `native_id == profile_details.issue_id`；且要求兩個 `source_identity` 相等。
- YAML `projection_instance_consistency.full_instance_identity_binding` 說明。
- 負例：`INSTANCE_CLOUD_DRIFT`（兩 instance `source_instance_id` 換別的 cloud id）、
  `INSTANCE_ENTITY_TYPE_DRIFT`（`entity_type` → comment）—— `base_case_ref` + `instance_mutation`，
  主程式套 mutation 後 `projection_instance_consistency` 必須非空。
- parity：neutralize `source_instance_id == cloud_id` / `entity_type == issue` → RED；
  positive fixture drift `source_instance_id` → RED。

### F-02-R02 — reconciliation version ordering fail closed + compound 比較

- decision 段：`previous_version` 必填且可 parse，否則
  `JIRA_MAP_RECONCILIATION_VERSION_UNPARSEABLE`（新 code）；`current_version` 帶了就必須可 parse
  （移除 `|| version_instant` 靜默 fallback）。
- compound：`same_compound` = timestamp 相等且雙方 `secondary_digest` 皆存在且相等；
  `ordered_new = current > previous || (timestamp 相等 && !same_compound)` —— 等 timestamp、
  digest 不同即 newer，NOOP 不成立 → `RECONCILIATION_VERSION_DECISION_MISMATCH`。
- YAML `reconciliation.rule` 改寫 + `error_contract` +1；positive reconcile 案補
  `previous_version` / `current_version` 的 `secondary_digest`。
- 負例：`RECONCILIATION_VERSION_UNPARSEABLE_PREVIOUS`（`previous_version.value` 不可 parse）、
  `RECONCILIATION_COMPOUND_DIGEST_NOOP`（同 timestamp、digest 不同、decision NOOP）。
- parity：neutralize UNPARSEABLE fail-closed → RED；`ordered_new` 退回純 timestamp 比較 → RED。

### 檔案大小 / 重構

`validate_jira_adapter_mapping_contract.rb` 351 行（< 400）。`parse_instant` /
`json_pointer_addresses_field?` / `identity_complete?` / `projection_instance_consistency` +
新增 `deep_dup` / `set_path` 下沉共用 lib，既有 validator 行為不變。

### 修復後 gate

```
ruby validate_jira_adapter_mapping_contract.rb               PASS
validate_jira_adapter_mapping_instances.py (uv)              PASS (positive_instances=6, instance_negatives=3)
全 19 Ruby validators（含共用 lib 下沉回歸）                  PASS
validate_std_schema_engine.py (uv)                           PASS (STD01 12/12, STD02 16/16, STD03 9/9)
validate_cc_cross_layer_contract.py (uv)                     PASS
enforcement parity（cp-based restore，5 項）                 全數 RED-on-tamper
git add -A && git diff --cached --check                      clean
```

### 交付物（Repair 03）

| 檔 | 動作 |
|---|---|
| `規格/v0.1/jira-adapter-mapping.yaml` | 改（reconciliation.rule compound + unparseable；error_contract +1；projection_instance_consistency.full_instance_identity_binding；required_negative_fixtures +4） |
| `scripts/validate_jira_adapter_mapping_contract.rb` | 改（reconciliation decision 段 fail-closed + compound 比較；instance_mutation 負例迴圈；helper 下沉；351 行） |
| `scripts/lib/omos_contract_helpers.rb` | 改（下沉 parse_instant / json_pointer_addresses_field? / identity_complete? / projection_instance_consistency + 新增 deep_dup / set_path，+90 行） |
| `規格/v0.1/fixtures/jira-adapter-mapping-positive-fixtures.json` | 改（RECONCILE_NEWER 的 previous/current_version 補 secondary_digest） |
| `規格/v0.1/fixtures/jira-adapter-mapping-negative-fixtures.json` | 改（+4 負例：2 reconciliation version + 2 instance_mutation identity drift） |

---

## Repair 04（2026-09-10）— Repair 03 再 review NO_GO(P1=1) 針對性修復

卡：`.work/CARD-JIRA-ADAPTER-MAPPING-REPAIR-04-20260910.md`。`170da7f` / `733a9e3` / `fb939c1` /
`3e18080` 皆不動；repair-04 delta = `3e18080..<repair-04 SHA>`。只收 F-02-R03（identity finding
已 CLOSED）。

### 1. supplied reconciliation version fail-closed 驗（與 decision 無關）

- 新 helper `reconciliation_version_problem(node)`（共用 lib）：非物件 / value 不可 parse →
  `JIRA_MAP_RECONCILIATION_VERSION_UNPARSEABLE`；`secondary_digest` 非合法 sha256 →
  `JIRA_MAP_RECONCILIATION_VERSION_DIGEST_MALFORMED`（新 code）。
- evaluator：`reconciliation.key?("previous_version"/"current_version")` 時無條件跑此驗，
  不再包在 `if present?(decision)` 內。

### 2. current compound version 唯一來源 = 實際 projection

- 移除 `parse_instant(current_version["value"]) || version_instant` 靜默 fallback；current
  一律取 `version_instant` / `version["secondary_digest"]`。
- `reconciliation.current_version` 有提供時必須逐字等於 projected `source_version`，否則
  `JIRA_MAP_RECONCILIATION_CURRENT_VERSION_NOT_PROJECTED`（新 code）。

### 3. decision enum

- `decision` 有值時必須 ∈ `[NEW_EVIDENCE, NOOP]`，否則
  `JIRA_MAP_RECONCILIATION_DECISION_UNKNOWN`（新 code）；`previous_version` 必填。

### 4. YAML / fixtures

- `reconciliation.rule` 改寫；`error_contract` +3；`required_negative_fixtures` +5。
- 既有 3 個 reconciliation-version 負例改寫為 current=projected 形式（code 不變）。
- 新 5 負例：`CURRENT_VERSION_WRONG_TYPE` / `CURRENT_NOT_PROJECTED` / `DECISION_UNKNOWN` /
  `VERSION_DIGEST_MALFORMED` / `MALFORMED_PREV_NO_DECISION`。
- positive `JIRA_MAP_POS_DESCRIPTION` 補 `decision` + `previous_version`（無 current_version）
  控制案例。

### 修復後 gate

```
ruby validate_jira_adapter_mapping_contract.rb               PASS
validate_jira_adapter_mapping_instances.py (uv)              PASS (positive_instances=6, instance_negatives=3)
全 19 Ruby validators（含共用 lib 回歸）                      PASS
validate_std_schema_engine.py (uv)                           PASS (STD01 12/12, STD02 16/16, STD03 9/9)
validate_cc_cross_layer_contract.py (uv)                     PASS
定點 reconciliation_version_problem：string/array/nil -> UNPARSEABLE（不 crash）；
  bad digest -> DIGEST_MALFORMED；valid -> nil
enforcement parity（cp-based restore）：neutralize CURRENT_VERSION_NOT_PROJECTED /
  DECISION_UNKNOWN / VERSION_DIGEST_MALFORMED、previous_version 驗證重新包回 decision 內 -> 皆 RED
git add -A && git diff --cached --check                      clean
```

### 交付物（Repair 04）

| 檔 | 動作 |
|---|---|
| `規格/v0.1/jira-adapter-mapping.yaml` | 改（reconciliation.rule；error_contract +3；required_negative_fixtures +5） |
| `scripts/validate_jira_adapter_mapping_contract.rb` | 改（reconciliation 版本驗證 fail-closed + current=projected + decision enum；RECONCILIATION_DECISIONS；367 行） |
| `scripts/lib/omos_contract_helpers.rb` | 改（+`reconciliation_version_problem`） |
| `規格/v0.1/fixtures/jira-adapter-mapping-positive-fixtures.json` | 改（POS_DESCRIPTION 補 decision + previous_version） |
| `規格/v0.1/fixtures/jira-adapter-mapping-negative-fixtures.json` | 改（3 個既有 reconciliation-version 負例改寫 + 5 新負例） |
