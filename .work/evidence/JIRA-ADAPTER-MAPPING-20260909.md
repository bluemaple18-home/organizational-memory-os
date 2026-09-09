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
