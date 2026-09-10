---
id: DOC-ADAPTER-MAPPING-REPAIR-01-20260910
parent: DOC-ADAPTER-MAPPING-20260909
status: REPAIRED_AWAITING_TARGETED_REREVIEW
type: repair
lane: A（repo 施工順序 #2 / EMEM-02 前置）
tier: T1
review_line: DOC-ADAPTER-MAPPING（同一條 review line）
frozen_review_sha: c2e184f
repair_delta: c2e184f..HEAD（cc/doc-adapter-mapping）
---

# Repair 01｜Document Adapter Mapping（repo #2）

針對大 review 的 **NO_GO（3×P1）**，在同一條 review line 上做**針對性**修復。
原 review SHA `c2e184f` 不動；本修復是 `cc/doc-adapter-mapping` 上的新 commit。

## 收到的裁決

- **F-01（P1）**：yaml 自創 `profile_details` shape（PDF `{page, bbox_normalized,
  coordinate_origin}`、Markdown `{codepoint_start/end, line_start/end}`），與 **LOCKED**
  `source-anchor-pdf-region-v1.schema.json` / `source-anchor-markdown-text-v1.schema.json`
  的 `profile_details.required` 衝突；validator 只讀了 base `source-anchor.schema.json`。
  等於重定義 STD profile → 觸「不重定義 STD」hard stop。
- **F-02（P1）**：evaluator 只做本地 mapping key 檢查；positive fixtures 不是 schema-valid
  的 STD instance（缺 STD-01/02/03 必填、`attributes` 用 `{rows,cols}` 而非 locked
  `columns[]/rows[]`、image 只有 `alt`、`source_anchor_refs` 非 UUIDv7）。
- **F-03（P1）**：determinism 只查 caller 自報的 `native_id_basis == CONTENT_SHA256`，
  沒有驗實際 derivation。

## 修復內容（逐條對應）

### F-01 — profile_details 逐字綁 locked profile-specific schema

- `規格/v0.1/document-adapter-mapping.yaml`
  `source_anchor_projection.profile_details_shape`：
  - `PDF_REGION_V1` = `[page, page_number_basis, bbox, block_id, char_range,
    char_representation_ref, char_representation_digest, selected_text]`
  - `MARKDOWN_TEXT_V1` = `[codepoint_range, line_range, line_number_basis, heading_path,
    selected_text]`
  兩者逐字等於對應 locked profile schema 的 `profile_details.required`。
- `scripts/validate_document_adapter_mapping_contract.rb`：新增讀
  `source-anchor-pdf-region-v1.schema.json` / `source-anchor-markdown-text-v1.schema.json`，
  `profile_details_required(profile_schema)` 從 `allOf[*].properties.profile_details.required`
  取；structural assert 要求 yaml 的 `profile_details_shape.<profile>` **逐字等於**
  locked schema 的 required（`規格` shape 漂移 → RED，已驗）。
- `cross_reference.must_match` 新增 `pdf_profile_details_shape_from` /
  `markdown_profile_details_shape_from` 指向那兩個 profile schema 的
  `profile_details.required`。
- 新負例 `DOC_MAP_NEG_PROFILE_DETAILS_NOT_LOCKED_SHAPE`：mapping 帶舊自創 key set
  `[page, bbox_normalized, coordinate_origin]` → `DOC_MAP_PROFILE_DETAILS_NOT_LOCKED_SHAPE`。
- instance-negative `DOC_MAP_INST_NEG_ANCHOR_OLD_CUSTOM_SHAPE`：一份 SourceAnchor instance
  用舊自創 `profile_details` shape，須被 locked `source-anchor-pdf-region-v1.schema.json` 拒。

### F-02 — positive fixtures 變成完整 STD instance + 加 JSON Schema instance gate

- `規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json` 重寫：兩個 case
  （`DOC_MAP_POS_PDF` / `DOC_MAP_POS_MARKDOWN`）各帶完整
  `raw_evidence_instance`（STD-01）、`source_anchor_instance`（STD-02 profile-specific）、
  `block_instances[3]`（STD-03，含 section_header/table/image 或 title/code/list_item），
  instances 依 STD-01/02/03 既有合法 fixture 例改寫。
- 新 companion `scripts/validate_document_adapter_mapping_instances.py`（PEP 723，
  `jsonschema==4.25.1` + `rfc3339-validator==0.1.4`，`uv run --no-project --script`）：
  以 Draft 2020-12 `Registry`（keyed by 各 schema `$id`）驗每個 positive 的 3 類 instance
  對 locked target schema 合法；再驗每個 `instance_negative_cases` 確實被拒。
- yaml 新增 `instance_validation.engine` 指向 companion；Ruby validator assert 該 engine
  檔案存在。
- 新 `規格/v0.1/fixtures/document-adapter-mapping-instance-negative-fixtures.json`：3 case
  —— RawEvidence 缺 locked 必填、SourceAnchor 舊自創 shape、block table 錯 nested shape
  （`{rows:4, cols:3}` 而非 locked `columns[]/rows[]`）。
- 修復過程 companion 抓出並修正 3 個 fixture 撰寫錯：`idempotency_basis` shape
  （`{profile, includes, excludes}`）、digest 66→64 hex、`canonicalization_profile == NONE`
  時 `canonical_digest` 必須 `null`。

### F-03 — deterministic derivation machine-verifiable

- yaml 新增 `deterministic_derivation`：`inputs: [content_digest, adapter_id,
  adapter_version]`；`derived: [native_id, source_version, digests, idempotency_key,
  projection_digest]`；規則：同 inputs 兩次執行必須產出 byte-identical `projection_digest`。
- positive fixture 每個 case 帶 `determinism.two_runs`（2 次相同 inputs → 相同
  `projection_digest`）→ allow。
- 負例 `DOC_MAP_NEG_NONDETERMINISTIC_TWO_RUNS`：`two_runs` inputs 相同但
  `projection_digest` 不同 → `DOC_MAP_NONDETERMINISTIC_IDENTITY`。
- evaluator：`runs[0].inputs == runs[1].inputs && runs[0].projection_digest !=
  runs[1].projection_digest` → `DOC_MAP_NONDETERMINISTIC_IDENTITY`；`native_id_basis`
  非 `CONTENT_SHA256` 仍另判同 code（`DOC_MAP_NEG_NONDETERMINISTIC_IDENTITY_BASIS`）。

## 驗證（session evidence）

- `ruby scripts/validate_document_adapter_mapping_contract.rb` → `PASS`
- `uv run --no-project --script scripts/validate_document_adapter_mapping_instances.py` →
  `PASS (positive_instances=10, instance_negatives=3)`
- 全 Ruby validator（含 STD-00~03 / cross-layer / personal-memory aggregator regression）
  → 全 PASS
- `uv run --no-project --script scripts/validate_std_schema_engine.py` → `PASS`
  （STD01 12/12、STD02 16/16、STD03 9/9）
- `uv run --no-project --script scripts/validate_cc_cross_layer_contract.py` → `PASS`
- enforcement parity：逐一 neutralize `document_mapping_failure` 的 11 個 `return "<CODE>"`
  → 每次 exit 1（RED），還原後 PASS
- structural-assert parity：`規格` 的 `profile_details_shape.PDF_REGION_V1` 拿掉一個 key
  → validator exit 1（RED），還原後 PASS
- instance-gate parity：把 `DOC_MAP_INST_NEG_ANCHOR_OLD_CUSTOM_SHAPE` 改成合法 locked
  shape → companion exit 1（該負例不再被拒 → gate 轉紅），還原後 PASS
- `git add -A && git diff --cached --check` → clean

## 未擴張的範圍

- 沒動任何 `LOCKED_OWNER_ACCEPTED` schema（`git diff --name-status ba518a0..HEAD` 僅
  新增 companion + instance-negative fixture + 卡 + evidence，其餘為 mapping yaml /
  validator / mapping fixture）。
- 沒新增 registry / FSM / package / runtime；companion 是純 JSON Schema 驗證器。
- connector / PDF·Markdown parser / ingestion runtime 仍不在本卡。

## 交付

- branch `cc/doc-adapter-mapping`，repair commit 在 `c2e184f`（原 review SHA，不動）之後。
- 針對性再 review 範圍：`c2e184f..<repair SHA>`。
