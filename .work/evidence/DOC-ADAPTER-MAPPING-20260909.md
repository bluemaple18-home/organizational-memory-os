# Evidence｜Document Adapter Mapping（repo #2）

- 卡：`.work/CARD-DOC-ADAPTER-MAPPING-20260909.md`
- Tier：T1
- branch：`cc/doc-adapter-mapping`（off `main` @ `ba518a0`）
- lane：A（repo 施工順序 #2 / EMEM-02 前置）

## 交付物

| 檔 | 說明 | 行數 |
|---|---|---|
| `規格/v0.1/document-adapter-mapping.yaml` | PDF / Markdown → STD-01/02/03 的確定性 mapping table：raw_evidence_projection / source_anchor_projection / normalized_document_projection / determinism / cross_reference | 178 |
| `scripts/validate_document_adapter_mapping_contract.rb` | 薄 validator：結構斷言（mapping 值皆為 STD schema 合法欄位／enum）+ 純函式 `document_mapping_failure(projection, target)` evaluator；交叉讀 3 個 STD schema JSON；沿用 `scripts/lib/omos_contract_helpers.rb` | 229 |
| `規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json` | `document_mapping_cases` ×2（PDF / Markdown 完整投影） | — |
| `規格/v0.1/fixtures/document-adapter-mapping-negative-fixtures.json` | `document_mapping_negative_cases` ×12，各單一 mutation + `expected_failure_code` + `covers_doc_map_negative_fixture` | — |

檔案大小守 `.agentskills/docs/coding-standards.md` §2（validator 229 < 400）。

## 契約重點（對應 Acceptance）

- **確定性身份**：`source_identity.native_id_basis` 鎖 `CONTENT_SHA256`；`source_version`
  鎖 `CONTENT_ONLY` / `CONTENT_DIGEST`（純文件無 authoritative native version）→
  `DOC_MAP_NONDETERMINISTIC_IDENTITY`。
- **投影欄位必須是目標 schema 的合法 property**：validator 執行期讀
  `raw-evidence-envelope.schema.json` 的 `properties.keys`，投影宣稱的欄位若不在其中 →
  `DOC_MAP_FIELD_NOT_IN_TARGET_SCHEMA`。同理 `payload.structured_profile` /
  `source-anchor.profile` / `selectors.selector_type` / `block.block_type` /
  `block.content_layer` 都對 schema enum 交叉驗證（cross_reference `must_match` 鎖 pointer 字串）。
- **payload reference-only**：`payload_ref` 為 reference、無 `inline_content` →
  `DOC_MAP_PAYLOAD_INLINE`。
- **profile 對映**：PDF → `PDF_REGION_V1` + `PDF_REGION` selector；Markdown →
  `MARKDOWN_TEXT_V1` + `TEXT_POSITION` selector；不符 → `DOC_MAP_PROFILE_MISMATCH` /
  `DOC_MAP_SELECTOR_MISSING`。
- **profile_details 確定 shape**：PDF `{page, bbox_normalized, coordinate_origin}`（page 正整數、
  bbox 四個 0..1 數）；Markdown `{codepoint_start, codepoint_end, line_start, line_end}`
  （`codepoint_end > codepoint_start`、`line_end >= line_start >= 1`）；key set 或型別不符 →
  `DOC_MAP_PROFILE_DETAILS_MALFORMED`。`normalization_profile` 鎖 `OMOS_TEXT_NORM_V1` const。
- **NormalizedDocument block**：`block_type` ∈ STD-03 enum（`DOC_MAP_BLOCK_TYPE_UNKNOWN`）；
  `content_layer` == `content_layer_by_block_type[block_type]`（`DOC_MAP_CONTENT_LAYER_MISMATCH`）；
  `table` block 帶 `attributes.table`、`image` block 帶 `attributes.asset`
  （`DOC_MAP_TABLE_IMAGE_ATTR_MISSING`）；每 block `source_anchor_refs` 非空
  （`DOC_MAP_BLOCK_NOT_ANCHORED`）。
- **fail-loud**：mapping 有 `error` 但 `ok != false` → `FAIL_SILENT`。
- **不重定義 STD**：`hard_stops` 明訂；validator 只讀 schema 不寫。

## 驗證

### gate 全綠（branch head）

```
19 Ruby validator（含 doc-adapter 本卡 + AIWR ×8 + personal-memory aggregator + 4 slice
+ STD-00~03 + cross-layer）  exit=0 PASS
std_schema_engine.py   PASS  coverage 12/12、16/16、9/9（不變）
validate_cc_cross_layer_contract.py   PASS
git diff --check   clean
```

### 負例 enforcement parity（移除 enforcement → gate 轉紅）

逐一 neutralize 每個 `return "<CODE>"`：`DOC_MAP_UNKNOWN_SOURCE_KIND` / `FAIL_SILENT` /
`DOC_MAP_FIELD_NOT_IN_TARGET_SCHEMA` / `DOC_MAP_NONDETERMINISTIC_IDENTITY` /
`DOC_MAP_PAYLOAD_INLINE` / `DOC_MAP_PROFILE_MISMATCH`(anchor) / `DOC_MAP_SELECTOR_MISSING` /
`DOC_MAP_PROFILE_DETAILS_MALFORMED`(keyset) / `DOC_MAP_BLOCK_TYPE_UNKNOWN` /
`DOC_MAP_CONTENT_LAYER_MISMATCH` / `DOC_MAP_TABLE_IMAGE_ATTR_MISSING` /
`DOC_MAP_BLOCK_NOT_ANCHORED` —— 全部移除後 `ruby scripts/validate_document_adapter_mapping_contract.rb`
exit 1（RED），還原後 `PASS`。12 個 enforcement 全數 load-bearing。

### DoD：正向 + fail-closed

- 正向：`DOC_MAP_POS_PDF`（PDF_REGION_V1 anchor + BINARY payload + section_header/paragraph/table
  blocks）與 `DOC_MAP_POS_MARKDOWN`（MARKDOWN_TEXT_V1 anchor + TEXT payload + title/code/image/
  list_item blocks）→ allow。
- fail-closed：12 個負例覆蓋來源類型不合法／投影非目標 schema 欄位／非內容基底身份／payload
  內嵌／profile 不符／selector 缺／profile_details key set 錯／block type 未知／content_layer 不符／
  table-image 缺 attribute／block 未 anchor／fail-silent。

### 上游 schema 未被改動

`git diff --name-status ba518a0..HEAD` 僅新增 4 檔 + 卡 + evidence；未碰
`raw-evidence-envelope.schema.json`／`source-anchor*.schema.json`／`normalized-document*.schema.json`
（皆 `LOCKED_OWNER_ACCEPTED`）。`target` enum / property 集合由執行期讀 schema JSON，schema
改動會自動失配。dup-key fail-closed 對 3 個新檔已跑（`StrictJsonObject` /
`assert_unique_yaml_mapping_keys`，來自共用 lib）。

---

## Repair 01（2026-09-10）— NO_GO(3×P1) 針對性修復

卡：`.work/CARD-DOC-ADAPTER-MAPPING-REPAIR-01-20260910.md`。原 review SHA `c2e184f` 不動；
repair delta = `c2e184f..<repair SHA>`（同一條 review line）。

### F-01 profile_details 逐字綁 locked profile schema

- yaml `source_anchor_projection.profile_details_shape`：
  `PDF_REGION_V1` = `[page, page_number_basis, bbox, block_id, char_range,
  char_representation_ref, char_representation_digest, selected_text]`；
  `MARKDOWN_TEXT_V1` = `[codepoint_range, line_range, line_number_basis, heading_path,
  selected_text]`。逐字等於 `source-anchor-pdf-region-v1.schema.json` /
  `source-anchor-markdown-text-v1.schema.json` 的 `profile_details.required`。
- validator 新讀那兩個 profile schema，`profile_details_required()` 從 `allOf` 取 required；
  structural assert 要 yaml shape 逐字等於 locked required（shape 漂移 → RED，已驗）。
- `cross_reference.must_match` 加 `pdf_profile_details_shape_from` /
  `markdown_profile_details_shape_from` pointer。
- 負例 `DOC_MAP_NEG_PROFILE_DETAILS_NOT_LOCKED_SHAPE`（舊 key set `[page, bbox_normalized,
  coordinate_origin]`）→ `DOC_MAP_PROFILE_DETAILS_NOT_LOCKED_SHAPE`。

### F-02 positive fixtures = 完整 STD instance + JSON Schema instance gate

- positive fixtures 重寫：`DOC_MAP_POS_PDF` / `DOC_MAP_POS_MARKDOWN` 各帶完整
  `raw_evidence_instance`（STD-01）/ `source_anchor_instance`（STD-02 profile-specific）/
  `block_instances[3]`（STD-03）。
- 新 companion `scripts/validate_document_adapter_mapping_instances.py`（PEP 723，jsonschema
  4.25.1 + rfc3339-validator 0.1.4）：Draft 2020-12 `Registry`（keyed by `$id`）驗每個
  positive instance 對 locked target schema 合法、每個 instance-negative 確實被拒。
- yaml `instance_validation.engine` 指向 companion；Ruby validator assert 檔案存在。
- 新 `document-adapter-mapping-instance-negative-fixtures.json` ×3：RawEvidence 缺 locked
  必填 / SourceAnchor 舊自創 shape / block table 錯 nested shape（`{rows,cols}` vs locked
  `columns[]/rows[]`）。
- companion 撰寫期抓出並修：`idempotency_basis` shape、digest 66→64 hex、
  `canonicalization_profile==NONE` 時 `canonical_digest` 須 `null`。

### F-03 deterministic derivation machine-verifiable

- yaml `deterministic_derivation`：`inputs: [content_digest, adapter_id, adapter_version]`；
  同 inputs 兩次執行須產出 byte-identical `projection_digest`。
- positive fixture 帶 `determinism.two_runs`（2×相同 inputs → 相同 digest）→ allow。
- 負例 `DOC_MAP_NEG_NONDETERMINISTIC_TWO_RUNS`（inputs 相同、`projection_digest` 不同）
  → `DOC_MAP_NONDETERMINISTIC_IDENTITY`。

### 修復後 gate

```
ruby validate_document_adapter_mapping_contract.rb            PASS
validate_document_adapter_mapping_instances.py (uv)           PASS (positive_instances=10, instance_negatives=3)
全 Ruby validators（STD-00~03 / cross-layer / personal-memory regression）  PASS
validate_std_schema_engine.py (uv)                            PASS (STD01 12/12, STD02 16/16, STD03 9/9)
validate_cc_cross_layer_contract.py (uv)                      PASS
enforcement parity（11× return "<CODE>" neutralize）           每次 RED，還原 PASS
structural-assert parity（profile_details_shape 漂移）          RED，還原 PASS
instance-gate parity（instance-negative 改成合法 → gate 轉紅）  RED，還原 PASS
git add -A && git diff --cached --check                       clean
```

### 交付物（修復後）

| 檔 | 動作 | 行數 |
|---|---|---|
| `規格/v0.1/document-adapter-mapping.yaml` | 改（locked profile_details shape + deterministic_derivation + instance_validation + cross_reference/error_contract/fixture-label 更新） | 223 |
| `scripts/validate_document_adapter_mapping_contract.rb` | 改（讀 2 個 profile schema、`profile_details_required()`、`document_mapping_failure` over mapping{}+determinism.two_runs） | 222 |
| `scripts/validate_document_adapter_mapping_instances.py` | 新（JSON Schema Registry instance gate） | 128 |
| `規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json` | 改（2 case，完整 STD instance + two_runs） | — |
| `規格/v0.1/fixtures/document-adapter-mapping-negative-fixtures.json` | 改（11 mapping-semantic 負例） | — |
| `規格/v0.1/fixtures/document-adapter-mapping-instance-negative-fixtures.json` | 新（3 instance-schema 負例） | — |

validator 222 / companion 128，守 `.agentskills/docs/coding-standards.md` §2（< 400）。

---

## Repair 02（2026-09-10）— Repair 01 再 review NO_GO(P1=2, P2=1) 針對性修復

卡：`.work/CARD-DOC-ADAPTER-MAPPING-REPAIR-02-20260910.md`。原 review SHA `c2e184f`、Repair 01
`faddb8c` 皆不動；repair-02 delta = `faddb8c..<repair-02 SHA>`。只做 review 指定的兩件核心事
＋ P2，不擴 scope。

### 核心 1 — mapping table ↔ spec/fixture 重新綁定（關 F-02 regression）

- Ruby validator 補回 `raw_evidence_projection` 結構斷言：enum-valued 值必須是對應
  `raw-evidence-envelope.schema.json` enum 成員（`structured_profile_by_kind` /
  `canonicalization_profile` / `allowed_ingestion_modes` / `source_version.basis` / `.kind`），
  且鎖定 `source_system == document` / `native_id_basis == CONTENT_SHA256` /
  `entity_type_by_kind` / `structured_profile_by_kind == {PDF: BINARY, MARKDOWN: TEXT}` /
  `allowed_ingestion_modes == [MANUAL_UPLOAD, BULK_EXPORT]` /
  `source_version.basis == CONTENT_ONLY` / `.kind == CONTENT_DIGEST`。
- **spec ↔ fixture 一致**：每個 positive 的 `raw_evidence_instance` / `source_anchor_instance` /
  `block_instances` 必須與 mapping table 對該 source kind 的宣告逐欄一致（source_system /
  entity_type / structured_profile / canonicalization_profile / ingestion_mode /
  source_version.basis·kind / anchor profile / required selector / normalization_profile /
  每個 block content_layer）。YAML 或 fixture 任一側漂移即 RED。
- YAML `raw_evidence_projection.rule` 補綁定說明。

### 核心 2 — determinism 由 validator 實算 canonical projection digest（關 F-03）

- YAML `deterministic_derivation` 新增 `identity_bearing_fields`（跨 run 必 byte-identical）+
  `excluded_from_canonical_digest`（ingestion-time / wall-clock surface：observed/received/
  persisted 時間、per-run receipt/activity/observation refs、activity_refs、
  source_anchor.resolution.resolved_at/resolver_version），並定義 `projection_digest` =
  `{raw_evidence, source_anchor, blocks}` 去除 excluded path 後遞迴 sorted-key canonical JSON
  的 SHA256。fixture 不再提供任何 digest。
- validator 帶 `DETERMINISTIC_EXCLUDED_PATHS` / `IDENTITY_BEARING_FIELDS` 常數，斷言 YAML
  兩份清單逐字等於常數。
- positive：`determinism.two_runs`（自報 digest）→ `determinism.runtime_only_patch`（只落在
  excluded path 的 pointer→值）。validator：patch key 全 ∈ excluded；
  `projection_digest(base) == projection_digest(patched)`；identity-bearing 欄位逐欄不變；
  拒收殘留 `two_runs` / 自報 `projection_digest`。
- negative：`DOC_MAP_NEG_NONDETERMINISTIC_TWO_RUNS` → `DOC_MAP_NEG_NONDETERMINISTIC_STABLE_FIELD_DRIFT`
  （`base_case_ref: DOC_MAP_POS_PDF` + `stable_field_mutation` 改 raw_digest / native_id）。
  validator 取實際 instance、apply mutation、自算兩份 canonical digest 必須不同，否則 RED；
  且 mutation 不能只落在 excluded path。

### P2 — required_instance_negative_fixtures 變活契約

- Ruby validator 讀 instance-negative fixture 檔，斷言 `covers` 排序剛好等於
  `required_instance_negative_fixtures`（並綁到 Ruby 常數）、`case_id` 唯一、每個 case 帶
  `target_schema` / `expected_result == REJECT` / `instance`。
- Python companion 加第二道防線：`covers` 排序等於硬編清單、`case_id` 唯一、每個 label 必須
  出現在 mapping spec 檔。刪任一 case → Ruby + Python 皆 RED。

### 檔案大小 / 重構

`validate_document_adapter_mapping_contract.rb` 373 行（< 400）。通用 `deep_dup` / `*_path` /
`canonical_json` 下沉到 `scripts/lib/omos_contract_helpers.rb`（+40 行），既有 validator 行為
不變。

### 修復後 gate

```
ruby validate_document_adapter_mapping_contract.rb           PASS
validate_document_adapter_mapping_instances.py (uv)          PASS (positive_instances=10, instance_negatives=3)
全 19 Ruby validators（含共用 lib 下沉回歸）                  PASS
validate_std_schema_engine.py (uv)                           PASS (STD01 12/12, STD02 16/16, STD03 9/9)
validate_cc_cross_layer_contract.py (uv)                     PASS
enforcement parity（cp-based restore，11 項）                 全數 RED，還原 PASS
git add -A && git diff --cached --check                      clean
```

### 交付物（Repair 02）

| 檔 | 動作 |
|---|---|
| `規格/v0.1/document-adapter-mapping.yaml` | 改（deterministic_derivation +identity_bearing_fields/+excluded_from_canonical_digest；raw_evidence_projection.rule 綁定說明） |
| `scripts/validate_document_adapter_mapping_contract.rb` | 改（raw_evidence_projection 結構斷言回歸 + spec↔fixture 一致 + 實算 canonical projection digest + instance-negative 活契約；373 行） |
| `scripts/validate_document_adapter_mapping_instances.py` | 改（instance-negative coverage / case_id / label-in-spec 第二道防線） |
| `scripts/lib/omos_contract_helpers.rb` | 改（下沉 deep_dup / *_path / canonical_json，+40 行） |
| `規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json` | 改（two_runs → runtime_only_patch，×2 case） |
| `規格/v0.1/fixtures/document-adapter-mapping-negative-fixtures.json` | 改（determinism 負例換成 base_case_ref + stable_field_mutation，covers label 不變） |

---

## Repair 03（2026-09-10）— Repair 02 再 review NO_GO(P1=2) 針對性修復

卡：`.work/CARD-DOC-ADAPTER-MAPPING-REPAIR-03-20260910.md`。`c2e184f` / Repair 01 `faddb8c` /
Repair 02 `d2ee1d2` 皆不動；repair-03 delta = `d2ee1d2..<repair-03 SHA>`。只收 Repair 02 再
review 的 2 個 P1，不擴 scope。

### F-02-R02 — source_version 表示法 end-to-end 鎖定

- normative：純文件 `source_version.value == null`、content SHA256 放 `secondary_digest`。
- YAML：`source_version` 加 `secondary_digest_basis: CONTENT_SHA256`；`digests` 由
  `canonical_digest_by_kind`（與 STD-01 allOf[0] 矛盾）改為 `canonical_digest_is_null: true`
  + `normalized_digest_basis`。
- 兩個 positive fixture 的 raw + anchor `source_version` → `{value: null, secondary_digest:
  <content digest>}`；`native_id` → 完整 content digest。
- Ruby：`assert value_is_null / secondary_digest_basis / canonical_digest_is_null`，並在
  derivation binding 逐項驗。
- parity：fixture 回退成舊表示法 → RED；YAML `value_is_null: false` → RED；移除
  `canonical_digest_is_null` → RED。

### F-03-R02 — derived = f(determinism.inputs) 由 validator 重算驗證

- YAML `deterministic_derivation.binding` map：native_id / source_version.value /
  source_version.secondary_digest / digests.raw_digest / digests.canonical_digest /
  provenance.adapter_id / provenance.adapter_version / idempotency_key 各自的綁定規則。
- Ruby `derivation_binding_failures(inputs, raw, anchor)`：依 `determinism.inputs` 重算每個
  derived 欄位，與 projected instance 逐項比對，回傳失配名稱。`EXPECTED_DERIVATION_BINDING_KEYS`
  綁 YAML `binding` 的 key。
- positive loop：`determinism.inputs` key set 鎖定 + `derivation_binding_failures(...).empty?`。
- 負例：3 筆 `base_case_ref` + `input_mutation`（content_digest / adapter_id / adapter_version
  各一），instance 不動 → `derivation_binding_failures(mutated_inputs, base instance)` 必須非空。
  covers label `a declared deterministic input changed but the derived fields did not`。
- parity：reviewer 原 mutation（positive inputs.content_digest 改、instance 不動）→ RED；
  `derivation_binding_failures` neutralize 成永遠 `[]` → RED；刪 3 個 input_mutation 負例 → RED；
  YAML 移除 `binding` block → RED。

### 檔案大小 / 重構

`validate_document_adapter_mapping_contract.rb` 399 行（< 400）。`triple_of` /
`profile_details_required` 下沉到共用 lib（+20 行），既有 validator 行為不變。

### 修復後 gate

```
ruby validate_document_adapter_mapping_contract.rb           PASS
validate_document_adapter_mapping_instances.py (uv)          PASS (positive_instances=10, instance_negatives=3)
全 19 Ruby validators（含共用 lib 下沉回歸）                  PASS
validate_std_schema_engine.py (uv)                           PASS (STD01 12/12, STD02 16/16, STD03 9/9)
validate_cc_cross_layer_contract.py (uv)                     PASS
enforcement parity（cp-based restore，7 項）                 全數 RED-on-tamper
git add -A && git diff --cached --check                      clean
```

### 交付物（Repair 03）

| 檔 | 動作 |
|---|---|
| `規格/v0.1/document-adapter-mapping.yaml` | 改（source_version.secondary_digest_basis；digests.canonical_digest_is_null；deterministic_derivation.binding；rule；required_negative_fixtures +1） |
| `scripts/validate_document_adapter_mapping_contract.rb` | 改（derivation_binding_failures + EXPECTED_DERIVATION_BINDING_KEYS + spec 斷言 + positive/negative 綁定；399 行） |
| `scripts/lib/omos_contract_helpers.rb` | 改（下沉 triple_of / profile_details_required，+20 行） |
| `規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json` | 改（source_version value→null / secondary_digest→digest；native_id 完整化；idempotency_key 改為計算值） |
| `規格/v0.1/fixtures/document-adapter-mapping-negative-fixtures.json` | 改（+3 derivation-input 負例） |

---

## Repair 04（2026-09-10）— Repair 03 再 review NO_GO(P1=1) 針對性修復

卡：`.work/CARD-DOC-ADAPTER-MAPPING-REPAIR-04-20260910.md`。`c2e184f` / `faddb8c` / `d2ee1d2` /
`df6b2ff` 皆不動；repair-04 delta = `df6b2ff..<repair-04 SHA>`。只收 F-03-R03（F-01 / F-02 /
P2 已 CLOSED）。

### 1. tenant_id 變成明確 deterministic input

- `deterministic_derivation.inputs` → `[content_digest, adapter_id, adapter_version, tenant_id]`。
- `derivation_binding_failures()` 的 idempotency 改由 `inputs["tenant_id"]` 計算（不再讀
  `raw["tenant_id"]`）；新 binding `tenant_id`（`raw_evidence.tenant_id == inputs.tenant_id`）。
- positive fixture `determinism.inputs` 補 tenant_id；負例
  `DOC_MAP_NEG_DERIVATION_INPUT_TENANT_ID`。

### 2. normalized_digest 綁到 SourceAnchor representation_digest

- 新 binding `normalized_digest`（`raw_evidence.digests.normalized_digest ==
  source_anchor.representation.representation_digest`）；負例
  `DOC_MAP_NEG_DERIVATION_INSTANCE_NORMALIZED_DIGEST`。

### 3. SourceAnchor identity binding

- 新 binding `anchor_source_identity`（`source_anchor.source_identity ==
  raw_evidence.source_identity`）與 `anchor_identity_content_bound`
  （`source_anchor.source_identity.native_id == inputs.content_digest` +
  `source_system == "document"` + `entity_type == raw.source_identity.entity_type`）；
  負例 `DOC_MAP_NEG_DERIVATION_INSTANCE_ANCHOR_IDENTITY`（兩條同時失配）。

### 4. 其他

- `source_version_value` / `source_version_secondary_digest` binding 涵蓋 RawEvidence 與
  SourceAnchor 兩份。`EXPECTED_DERIVATION_BINDING_KEYS` 8 → 12，綁 YAML `binding` key。
- derivation 負例迴圈由「只吃 input_mutation」擴為「input_mutation 或 instance_mutation」。
- `derivation_binding_failures()` 下沉共用 lib（lib 加 `require "digest"`）；validator 394 行。

### 修復後 gate

```
ruby validate_document_adapter_mapping_contract.rb           PASS
validate_document_adapter_mapping_instances.py (uv)          PASS (positive_instances=10, instance_negatives=3)
全 19 Ruby validators（含共用 lib 下沉回歸）                  PASS
validate_std_schema_engine.py (uv)                           PASS (STD01 12/12, STD02 16/16, STD03 9/9)
validate_cc_cross_layer_contract.py (uv)                     PASS
定點驗證 derivation_binding_failures：baseline [] / anchor identity drift
  -> ["anchor_source_identity","anchor_identity_content_bound"] / normalized drift -> ["normalized_digest"]
enforcement parity（cp-based restore，5 項）                 全數 RED-on-tamper
git add -A && git diff --cached --check                      clean
```

### 交付物（Repair 04）

| 檔 | 動作 |
|---|---|
| `規格/v0.1/document-adapter-mapping.yaml` | 改（deterministic_derivation.inputs +tenant_id；binding 12 條；rule；required_negative_fixtures +1） |
| `scripts/validate_document_adapter_mapping_contract.rb` | 改（DETERMINISM_INPUT_KEYS / EXPECTED_DERIVATION_BINDING_KEYS；derivation 負例迴圈 input_mutation+instance_mutation；derivation_binding_failures 下沉；394 行） |
| `scripts/lib/omos_contract_helpers.rb` | 改（+`require "digest"`；`derivation_binding_failures()` 下沉並擴充 tenant_id / normalized_digest / anchor identity binding） |
| `規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json` | 改（determinism.inputs +tenant_id ×2） |
| `規格/v0.1/fixtures/document-adapter-mapping-negative-fixtures.json` | 改（+3 負例：1 input_mutation tenant_id + 2 instance_mutation normalized_digest / anchor identity） |

---

## Repair 05（2026-09-10）— Repair 04 再 review NO_GO(P1=1, F-03-R04) 針對性修復

卡：`.work/CARD-DOC-ADAPTER-MAPPING-REPAIR-05-20260910.md`。`c2e184f` / `faddb8c` / `d2ee1d2` /
`df6b2ff` / `f2333e1` 皆不動；repair-05 delta = `f2333e1..<repair-05 SHA>`。只收 F-03-R04：
把 deterministic surface 一次定義乾淨（input / derived / run-scoped）+ machine comparison。

### 六個 declared input

`inputs = [content_digest, adapter_id, adapter_version, tenant_id, source_instance_id,
normalized_representation_digest]`。後兩者是前輪未宣告的隱藏依賴。

### run_scoped_paths 完整列舉

`DOC_MAP_RUN_SCOPED_PATHS`（YAML `run_scoped_paths` 逐字綁定）—— RawEvidence / SourceAnchor
所有 per-run 欄位（evidence/anchor id·ref、chronology、access、aliases、resolution、selectors、
profile_details、payload_ref/size_bytes、provenance/ingestion_mode + receipt/activity refs …）。

### reconstruct(kind, inputs) + machine comparison

新 `reconstruct_deterministic_projection(kind, inputs)`（共用 lib）：只由 6 個 input（+ schema
constant）重建 `{raw_evidence, source_anchor}` 的 deterministic 片段（source_identity 為兩份
instance 同一物件、source_version、digests、payload profile、provenance adapter+const、
idempotency_key、idempotency_basis、representation、profile、normalization_profile、
schema_version）。`deterministic_surface_mismatches()`：fixture 去掉 run_scoped_paths 後
`diff_paths` 逐鍵比對重建結果，任一不符（含未分類欄位）→ `DOC_MAP_NONDETERMINISTIC_IDENTITY`。
每個保留欄位都釘死到 6 個 input → 同 inputs 只可能對應唯一 deterministic identity surface，
paired drift 無立足點。PDF `char_representation_digest` 另加 targeted 綁定。

### 負例

- input mutation ×6（含新 `source_instance_id` / `normalized_representation_digest`）。
- paired drift ×2（reviewer 原案例）：`normalized_digest`+`representation_digest` 一起改、
  `source_instance_id` 兩份一起改 —— inputs 不動 → RED。
- unclassified field ×1（`idempotency_basis` 內加欄位）。
- 既有 6 個 derivation 負例在新機制下仍 RED。

### 修復後 gate

```
ruby validate_document_adapter_mapping_contract.rb           PASS
validate_document_adapter_mapping_instances.py (uv)          PASS (positive_instances=10, instance_negatives=3)
全 19 Ruby validators（含共用 lib 回歸）                      PASS
validate_std_schema_engine.py (uv)                           PASS (STD01 12/12, STD02 16/16, STD03 9/9)
validate_cc_cross_layer_contract.py (uv)                     PASS
enforcement parity（cp-based restore，5 項，含 reviewer bypass A/B）  全數 RED-on-tamper
git add -A && git diff --cached --check                      clean
```

### 交付物（Repair 05）

| 檔 | 動作 |
|---|---|
| `規格/v0.1/document-adapter-mapping.yaml` | 改（deterministic_derivation：inputs 6 個；run_scoped_paths 完整列舉；reconstructed_from_inputs；rule 改寫；移除逐欄 binding map） |
| `scripts/validate_document_adapter_mapping_contract.rb` | 改（DETERMINISM_INPUT_KEYS 由 lib 取；positive/negative 迴圈改用 deterministic_surface_mismatches；PDF char_representation_digest targeted 綁定；run_scoped_paths 結構斷言；394 行） |
| `scripts/lib/omos_contract_helpers.rb` | 改（+DOC_MAP_DETERMINISM_INPUTS / DOC_MAP_RUN_SCOPED_PATHS / reconstruct_deterministic_projection / deterministic_surface_mismatches / diff_paths；移除舊 derivation_binding_failures） |
| `規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json` | 改（determinism.inputs +source_instance_id +normalized_representation_digest ×2） |
| `規格/v0.1/fixtures/document-adapter-mapping-negative-fixtures.json` | 改（+5 負例：2 input mutation + 2 paired drift + 1 unclassified field） |

---

## Repair 06（2026-09-10）— Repair 05 再 review NO_GO(P1=1, F-03-R05) 針對性修復

卡：`.work/CARD-DOC-ADAPTER-MAPPING-REPAIR-06-20260910.md`。`c2e184f` / `faddb8c` / `d2ee1d2` /
`df6b2ff` / `f2333e1` / `9ef254f` 皆不動；repair-06 delta = `9ef254f..<repair-06 SHA>`。
只收 F-03-R05：blocks 未進 deterministic reconstruction。**hard stop：本輪再 NO_GO 就不做
repair-07，轉 Owner spec-freeze（T2）。**

### 第 7 個 declared input + block slice 納入 machine comparison

- `deterministic_derivation.inputs` +`normalized_document_digest`
  （`sha256(canonical_json(deterministic block surface))`）。
- `DOC_MAP_BLOCK_RUN_SCOPED_KEYS = [block_id, parent_id, source_anchor_refs, quality]`
  （YAML `block_run_scoped_keys` 綁定）。
- `deterministic_surface_mismatches(kind, inputs, raw, anchor, blocks)` 多收 `blocks`：
  - `normalized_document_digest(block_instances)`（每 block 去掉 run-scoped keys → canonical
    JSON list → SHA256）必須等於 `inputs.normalized_document_digest`。
  - 每個 block `content_sha256 == "sha256:" + SHA256(block.content)`。
  - PDF `profile_details.char_representation_digest` targeted 綁定移進本函式。
  任一 diff 非空 → `DOC_MAP_NONDETERMINISTIC_IDENTITY`。
- fixture 6 個 block `content_sha256` 校正為 `SHA256(content)`；`determinism.inputs` 補
  `normalized_document_digest`。

### 負例

- `DERIVATION_INPUT_NORMALIZED_DOC_DIGEST`（改 input、blocks 不動）→ RED。
- `DERIVATION_PAIRED_BLOCK_CONTENT_DRIFT`（reviewer 原案例：`content` + `content_sha256` 一起
  換成另一組合法一致對、7 inputs 固定）→ block-set digest 偏離 → RED。
- `DERIVATION_BLOCK_SHA_INCONSISTENT`（只改 content）→ RED。
- 定點：`PAIRED_DRIFT` → `["blocks/normalized_document_digest"]`；`SHA_INCONSISTENT` → 2 gaps；
  baseline → `[]`。

### 修復後 gate

```
ruby validate_document_adapter_mapping_contract.rb           PASS
validate_document_adapter_mapping_instances.py (uv)          PASS (positive_instances=10, instance_negatives=3)
全 19 Ruby validators（含共用 lib 回歸）                      PASS
validate_std_schema_engine.py (uv)                           PASS (STD01 12/12, STD02 16/16, STD03 9/9)
validate_cc_cross_layer_contract.py (uv)                     PASS
enforcement parity（cp-based restore，含 reviewer bypass）    全數 RED-on-tamper
git add -A && git diff --cached --check                      clean
```

### 交付物（Repair 06）

| 檔 | 動作 |
|---|---|
| `規格/v0.1/document-adapter-mapping.yaml` | 改（inputs 7；block_run_scoped_keys；block_surface_rule；derived +normalized_document_block_surface；rule 改寫涵蓋 3 slices） |
| `scripts/validate_document_adapter_mapping_contract.rb` | 改（deterministic_surface_mismatches 多傳 blocks；instance_mutation 支援 block_instances/N/ path；block_run_scoped_keys 結構斷言；397 行） |
| `scripts/lib/omos_contract_helpers.rb` | 改（+DOC_MAP_BLOCK_RUN_SCOPED_KEYS / deterministic_block_surface / normalized_document_digest；deterministic_surface_mismatches 擴充 block slice + char_representation_digest） |
| `規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json` | 改（6 個 block content_sha256 校正；determinism.inputs +normalized_document_digest ×2） |
| `規格/v0.1/fixtures/document-adapter-mapping-negative-fixtures.json` | 改（+3 負例：1 input mutation + 1 paired block drift + 1 content_sha256 不一致） |

---

## Determinism 收尾（2026-09-10）— 依 Owner spec-freeze FP-1..FP-5 實作

卡：`.work/CARD-DOC-ADAPTER-DETERMINISM-CLOSEOUT-20260910.md`（**非 repair-07**；repair-06 的
hard stop 已觸發，F-03 轉 T2 spec-freeze 並由 Owner 於 2026-09-10 簽定）。
`c2e184f` / `faddb8c` / `d2ee1d2` / `df6b2ff` / `f2333e1` / `9ef254f` / `e7505f8` 皆不動；
delta = `e7505f8..<closeout SHA>`。

### FP-1 只宣稱 evidence identity

YAML `deterministic_derivation.claim: EVIDENCE_IDENTITY_ONLY` + `claim_rule`；validator 斷言
逐字相符。不再宣稱整份 emitted projection 逐位元相同。

### FP-2 `deterministic_projection_digest`

刪除舊 `projection_digest()`（hash 整份 triple）。新
`deterministic_projection_digest(triple) = "sha256:" + SHA256(canonical_json(deterministic_surface(triple)))`
—— 與 reconstruction 用同一個 surface，run-scoped 欄位在構造上不可能改變它。

### FP-3 單一總分類（止血點）

`DOC_MAP_RUN_SCOPED_PATHS` 成為唯一權威分類，涵蓋三個 slice（新增 `blocks/*/block_id` /
`parent_id` / `source_anchor_refs` / `quality`）。刪除 `DETERMINISTIC_EXCLUDED_PATHS`、
`IDENTITY_BEARING_FIELDS`、`DOC_MAP_BLOCK_RUN_SCOPED_KEYS`。新 `run_scoped_path?()`（含子樹與
`*` 展開）。`deterministic_surface` / digest / `normalized_document_digest` /
`deterministic_surface_mismatches` 全由它推導。validator 斷言 YAML 不得再出現舊的三份清單 key。
path helper 升級支援 Array 索引與 `*`。

### FP-4 / FP-5

block `parent_id` / `source_anchor_refs` / `quality` 全部納入單一分類為 run-scoped；文件結構
由 `level` / `order` 承載於 deterministic surface。

### Carry-over P2

`PAIRED_BLOCK_CONTENT_DRIFT` 捏造的 `content_sha256` 校正為 `"Authorization boundary"` 的
實算值 `sha256:6553c606…`；該負例現在只證明 paired block drift 本身。

### F-03-R06 直接關閉（本地重現）

positive `runtime_only_patch` → `run_scoped_patch`，並加入 reviewer 原 mutation
`blocks/0/quality/extraction_confidence: 0.5`（另加 block_id / source_anchor_refs /
parent_id）。實測 patch 確實落地（`0.98 -> 0.5`、`base != patched` 為 true），但
`deterministic_projection_digest` 兩者相同（`sha256:3109701453fe5615…`）。

### 收尾後 gate

```
ruby validate_document_adapter_mapping_contract.rb           PASS
validate_document_adapter_mapping_instances.py (uv)          PASS (positive_instances=10, instance_negatives=3)
全 19 Ruby validators（含共用 lib 回歸）                      PASS
validate_std_schema_engine.py (uv)                           PASS (STD01 12/12, STD02 16/16, STD03 9/9)
validate_cc_cross_layer_contract.py (uv)                     PASS
enforcement parity（6 項，含「digest 改回 hash 整份 projection」）  全數 RED-on-tamper
git add -A && git diff --cached --check                      clean
validator 行數                                                369（< 400）
```

### 交付物（收尾）

| 檔 | 動作 |
|---|---|
| `規格/v0.1/document-adapter-mapping.yaml` | 改（`deterministic_derivation` 整段重寫：claim / claim_rule / 7 inputs / derived / 單一 run_scoped_paths（含 blocks/*）/ reconstructed_from_inputs / rule；移除 excluded_from_canonical_digest、identity_bearing_fields、block_run_scoped_keys、block_surface_rule） |
| `scripts/validate_document_adapter_mapping_contract.rb` | 改（移除三份舊清單常數與 projection_digest()；claim 斷言；FP-3 反向斷言；positive 改用 run_scoped_patch + digest 不變；負例改吃 triple 路徑；369 行） |
| `scripts/lib/omos_contract_helpers.rb` | 改（path helper 支援 Array 索引與 `*`；單一 DOC_MAP_RUN_SCOPED_PATHS；run_scoped_path?；deterministic_surface；deterministic_projection_digest；normalized_document_digest 改吃 triple；deterministic_surface_mismatches 改吃 triple） |
| `規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json` | 改（runtime_only_patch → run_scoped_patch，加入 block run-scoped 路徑含 reviewer 原 mutation） |
| `規格/v0.1/fixtures/document-adapter-mapping-negative-fixtures.json` | 改（instance_mutation 路徑改 triple 形式；carry-over hash 校正） |

---

## 最終 review 的兩個 finding（2026-09-10）— F-AUTH-01 / F-03-R06-P2

`9dbae75` 的再 review：**F-03-R06 實作層判定 CLOSED**（`quality` bypass、paired block drift、
捏造 hash 都確認修好），剩兩件：

### F-AUTH-01（P1）—— Owner-signed authority 不在 frozen tree

CC 的流程錯誤：`.work/CARD-DOC-ADAPTER-DETERMINISM-SPEC-FREEZE-20260910.md`（`OWNER_SIGNED`，
FP-1…FP-5）被 commit 到 **`main`**（`53b0ee4`），但這條 review line 的 frozen tree 是
**branch `cc/doc-adapter-mapping`**。因此 reviewer 在 `9dbae75` 的 tree 找不到它，只看得到
closeout card 自報「Owner signed」—— 等於允許實作者自稱 Owner 已同意收窄 contract。
這違反本 review line 一貫的「implementation evidence 不得冒充獨立 authority / acceptance」。

**修法**：把 `OWNER_SIGNED` 原件（含 FP-1…FP-5 原文與簽定表）以 docs commit 放進同一條 branch，
implementation SHA `9dbae75` / `230bcf0` 不重寫。

### F-03-R06-P2 —— 單一分類的最後一個例外（已修，commit `230bcf0`）

`source_anchor/profile_details` 原本整個 subtree 列 run-scoped，故 `run_scoped_path?` 把
`char_representation_digest` 判為 RUN_SCOPED；但 `deterministic_surface_mismatches` 又硬編一條
「必須等於 `inputs.normalized_representation_digest`」，等於同一欄位有兩個 authority ——
正是 FP-3 禁止的。

**修法（逐子欄位分類，取消特例）**：
- run-scoped 子欄位：`page` / `page_number_basis` / `bbox` / `block_id` / `char_range` /
  `char_representation_ref` / `codepoint_range` / `line_range` / `line_number_basis` /
  `heading_path` / `selected_text`。
- `char_representation_digest` 依同一條規則即為 DETERMINISTIC；硬編特例刪除。
- reconstruction 產出殘存 slice：PDF `{char_representation_digest: nrd}`、MARKDOWN `{}`。
- 新增窮盡性斷言：locked profile schema 的每個 `profile_details` 必填欄位都必須被分類涵蓋
  （run-scoped 或明列 deterministic），未涵蓋即 fail-closed。
- 新負例 `DOC_MAP_NEG_DERIVATION_CHAR_REPR_DIGEST_DRIFT`，由單一規則擋下（無特例）。

實測：

```
run_scoped_path?  char_representation_digest -> false   （DETERMINISTIC）
                  bbox / selected_text / heading_path -> true
殘存 profile_details  PDF: {"char_representation_digest"=>"sha256:bbbb…"}   MARKDOWN: {}
char digest drift -> ["source_anchor/profile_details/char_representation_digest (expected …, got …)"]
```

### gate（`230bcf0`）

```
ruby validate_document_adapter_mapping_contract.rb           PASS
validate_document_adapter_mapping_instances.py (uv)          PASS (positive_instances=10, instance_negatives=3)
全 19 Ruby validators                                        PASS
validate_std_schema_engine.py / validate_cc_cross_layer_contract.py   PASS
enforcement parity（5 項）                                   全數 RED-on-tamper：
  profile_details 改回整個 subtree run-scoped -> RED
  清單漏一個 profile_details 子欄位 -> RED
  YAML run_scoped_paths 少一條 -> RED
  reconstruction 拿掉 profile_details slice -> RED
  digest 改回 hash 整份 projection（R06 舊錯回歸鎖）-> RED
git diff --check                                             clean
validator 行數                                                379（< 400）
```
