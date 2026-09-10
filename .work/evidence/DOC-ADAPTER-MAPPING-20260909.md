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
