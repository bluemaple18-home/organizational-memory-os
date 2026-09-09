#!/usr/bin/env ruby

# repo #2 / Document Adapter Mapping 契約 validator（mapping 語意層）。薄判斷：
#   1. 結構斷言：mapping table 的值是 STD-01/02/03 已鎖 schema 的合法欄位／enum；
#      profile_details_shape 逐字等於 locked profile schema 的 profile_details.required；
#      raw_evidence_projection 的 enum-valued 值是對應 raw-evidence schema enum 成員。
#   2. spec ↔ fixture 一致：每個 positive fixture 的 instance 必須與 mapping table
#      對該 source kind 的宣告一致（spec 與 fixture 不得脫鉤）。
#   3. 純函式 `document_mapping_failure(case)` evaluator：mapping 語意負例。
#   4. deterministic derivation：validator 自己 canonicalize + SHA256 兩份實際 projection
#      （fixture 不提供 digest）。schema-valid instance 由 companion
#      `scripts/validate_document_adapter_mapping_instances.py` 驗。
# 沿用 scripts/lib/omos_contract_helpers.rb（deep_dup / *_path / canonical_json 在該處）。

require "json"
require "yaml"
require "digest"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/document-adapter-mapping.yaml")
RAW_EVIDENCE_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/raw-evidence-envelope.schema.json")
SOURCE_ANCHOR_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/source-anchor.schema.json")
PDF_PROFILE_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/source-anchor-pdf-region-v1.schema.json")
MARKDOWN_PROFILE_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/source-anchor-markdown-text-v1.schema.json")
BLOCK_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/normalized-document-block.schema.json")
INSTANCE_ENGINE_PATH = File.join(ROOT, "scripts/validate_document_adapter_mapping_instances.py")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/document-adapter-mapping-negative-fixtures.json")
INSTANCE_NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/document-adapter-mapping-instance-negative-fixtures.json")

EXPECTED_SOURCE_KINDS = %w[PDF MARKDOWN].freeze
EXPECTED_ENTITY_TYPE_BY_KIND = { "PDF" => "PDF", "MARKDOWN" => "MARKDOWN" }.freeze
EXPECTED_STRUCTURED_PROFILE_BY_KIND = { "PDF" => "BINARY", "MARKDOWN" => "TEXT" }.freeze
EXPECTED_INGESTION_MODES = %w[MANUAL_UPLOAD BULK_EXPORT].freeze
EXPECTED_CANONICALIZATION_PROFILE = "NONE"
EXPECTED_SOURCE_VERSION_BASIS = "CONTENT_ONLY"
EXPECTED_SOURCE_VERSION_KIND = "CONTENT_DIGEST"
EXPECTED_ANCHOR_PROFILE_BY_KIND = { "PDF" => "PDF_REGION_V1", "MARKDOWN" => "MARKDOWN_TEXT_V1" }.freeze
EXPECTED_REQUIRED_SELECTOR_BY_KIND = { "PDF" => "PDF_REGION", "MARKDOWN" => "TEXT_POSITION" }.freeze
EXPECTED_CONTENT_LAYER_BY_BLOCK_TYPE = {
  "title" => "TITLE", "section_header" => "TITLE", "paragraph" => "BODY", "list_item" => "BODY",
  "code" => "CODE", "table" => "TABLE", "image" => "IMAGE", "unknown" => "UNKNOWN"
}.freeze
EXPECTED_ATTR_REQUIRED_BY_BLOCK_TYPE = { "table" => "table", "image" => "asset" }.freeze

# deterministic projection surface 定義（必須與 yaml deterministic_derivation 逐字一致）。
DETERMINISTIC_EXCLUDED_PATHS = %w[
  raw_evidence/chronology/observed_at
  raw_evidence/chronology/received_at
  raw_evidence/chronology/persisted_at
  raw_evidence/provenance/source_observation_receipt_ref
  raw_evidence/provenance/adapter_activity_ref
  raw_evidence/provenance/lineage_receipt_ref
  raw_evidence/activity_refs
  source_anchor/resolution/resolved_at
  source_anchor/resolution/resolver_version
].freeze
IDENTITY_BEARING_FIELDS = %w[
  raw_evidence/source_identity/native_id
  raw_evidence/source_version
  raw_evidence/digests
  raw_evidence/idempotency_key
  raw_evidence/payload/payload_ref
].freeze

EXPECTED_DOC_MAP_NEGATIVE_LABELS = [
  "a source kind outside PDF / MARKDOWN",
  "the source anchor profile does not match the source kind",
  "the required selector type is missing",
  "profile_details is not the locked profile-schema shape",
  "a block content_layer disagrees with its block type",
  "a table or image block is missing its attributes",
  "a block has no source anchor reference",
  "the payload is inline content instead of a reference",
  "source identity uses a non-content basis",
  "two runs with identical inputs produce a different projection",
  "error but the mapping still claims success"
].freeze

EXPECTED_INSTANCE_NEGATIVE_LABELS = [
  "a projected RawEvidenceEnvelope is missing a locked required field",
  "a projected SourceAnchor uses the old custom profile_details shape",
  "a projected block table attribute has the wrong nested shape"
].freeze

def read_json(path)
  JSON.parse(File.read(path), object_class: StrictJsonObject)
end

def read_yaml(path)
  text = File.read(path)
  assert_unique_yaml_mapping_keys(Psych.parse_stream(text))
  YAML.safe_load(text, permitted_classes: [], aliases: false)
end

def assert(condition, message, failures)
  failures << message unless condition
end

def sorted_set(values)
  values.to_a.sort
end

def triple_of(test_case)
  {
    "raw_evidence" => test_case["raw_evidence_instance"],
    "source_anchor" => test_case["source_anchor_instance"],
    "blocks" => test_case["block_instances"]
  }
end

def projection_digest(triple)
  scrubbed = deep_dup(triple)
  DETERMINISTIC_EXCLUDED_PATHS.each { |path| delete_path(scrubbed, path) }
  Digest::SHA256.hexdigest(canonical_json(scrubbed))
end

def profile_details_required(profile_schema)
  profile_schema.fetch("allOf").each do |part|
    next unless part.is_a?(Hash)

    required = part.dig("properties", "profile_details", "required")
    return required.to_a if required
  end
  []
end

# 純函式:一份 mapping 語意 case -> nil 或精確 machine failure code。
def document_mapping_failure(test_case, target)
  kind = test_case["source_kind"]
  return "DOC_MAP_UNKNOWN_SOURCE_KIND" unless EXPECTED_SOURCE_KINDS.include?(kind)
  return "FAIL_SILENT" if present?(test_case["error"]) && test_case["ok"] != false

  mapping = test_case["mapping"] || {}
  return "DOC_MAP_NONDETERMINISTIC_IDENTITY" unless mapping["native_id_basis"] == "CONTENT_SHA256"
  return "DOC_MAP_PAYLOAD_INLINE" if mapping["payload_inline"] == true || !present?(mapping["payload_ref"])

  expected_profile = EXPECTED_ANCHOR_PROFILE_BY_KIND.fetch(kind)
  return "DOC_MAP_PROFILE_MISMATCH" unless mapping["anchor_profile"] == expected_profile
  return "DOC_MAP_PROFILE_MISMATCH" unless target[:anchor_profile].include?(expected_profile)

  required_selector = EXPECTED_REQUIRED_SELECTOR_BY_KIND.fetch(kind)
  selector_types = mapping["selector_types"].to_a
  return "DOC_MAP_SELECTOR_MISSING" unless selector_types.include?(required_selector) &&
                                          target[:selector_type].include?(required_selector)

  locked_shape = target[:profile_details_shape].fetch(expected_profile)
  return "DOC_MAP_PROFILE_DETAILS_NOT_LOCKED_SHAPE" unless sorted_set(mapping["profile_details_keys"].to_a) == sorted_set(locked_shape)

  mapping["blocks"].to_a.each do |block|
    block_type = block["block_type"]
    return "DOC_MAP_BLOCK_TYPE_UNKNOWN" unless target[:block_type].include?(block_type)
    return "DOC_MAP_CONTENT_LAYER_MISMATCH" unless block["content_layer"] == EXPECTED_CONTENT_LAYER_BY_BLOCK_TYPE.fetch(block_type)
    required_attr = EXPECTED_ATTR_REQUIRED_BY_BLOCK_TYPE[block_type]
    return "DOC_MAP_TABLE_IMAGE_ATTR_MISSING" if required_attr && block["attribute_keys"].to_a.none? { |key| key == required_attr }
    return "DOC_MAP_BLOCK_NOT_ANCHORED" unless block["anchored"] == true
  end

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)
raw_schema = read_json(RAW_EVIDENCE_SCHEMA_PATH)
anchor_schema = read_json(SOURCE_ANCHOR_SCHEMA_PATH)
pdf_profile_schema = read_json(PDF_PROFILE_SCHEMA_PATH)
markdown_profile_schema = read_json(MARKDOWN_PROFILE_SCHEMA_PATH)
block_schema = read_json(BLOCK_SCHEMA_PATH)

target = {
  structured_profile: raw_schema.dig("properties", "payload", "properties", "structured_profile", "enum").to_a,
  canonicalization_profile: raw_schema.dig("properties", "payload", "properties", "canonicalization_profile", "enum").to_a,
  ingestion_mode: raw_schema.dig("properties", "provenance", "properties", "ingestion_mode", "enum").to_a,
  source_version_basis: raw_schema.dig("properties", "source_version", "properties", "basis", "enum").to_a,
  source_version_kind: raw_schema.dig("properties", "source_version", "properties", "kind", "enum").to_a,
  anchor_profile: anchor_schema.dig("properties", "profile", "enum").to_a,
  selector_type: anchor_schema.dig("properties", "selectors", "items", "properties", "selector_type", "enum").to_a,
  block_type: block_schema.dig("properties", "block_type", "enum").to_a,
  content_layer: block_schema.dig("properties", "content_layer", "enum").to_a,
  profile_details_shape: {
    "PDF_REGION_V1" => profile_details_required(pdf_profile_schema),
    "MARKDOWN_TEXT_V1" => profile_details_required(markdown_profile_schema)
  }
}

schema = spec.fetch("schema", {})
assert(schema["schema_id"] == "urn:omos:schema:document-adapter-mapping:0.1.0", "schema_id 必須是 document-adapter-mapping:0.1.0", failures)
assert(schema["version"] == "0.1.0", "schema.version 必須是 0.1.0", failures)
assert(schema.fetch("traces_to", []).include?("DOC-ADAPTER-MAPPING"), "schema.traces_to 必須包含 DOC-ADAPTER-MAPPING", failures)
assert(spec.dig("purpose", "no_second_workflow_authority") == true, "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec["runtime_independence"] == true, "runtime_independence 必須為 true", failures)
assert(spec.fetch("source_kinds", []) == EXPECTED_SOURCE_KINDS, "source_kinds 必須剛好是 [PDF, MARKDOWN]", failures)

# --- raw_evidence_projection 結構綁定（值必須是 raw-evidence schema enum 成員） ---
rep = spec.fetch("raw_evidence_projection", {})
assert(rep["source_system"] == "document", "raw_evidence_projection.source_system 必須是 document", failures)
assert(rep["native_id_basis"] == "CONTENT_SHA256", "raw_evidence_projection.native_id_basis 必須是 CONTENT_SHA256", failures)
assert(rep.fetch("entity_type_by_kind", {}) == EXPECTED_ENTITY_TYPE_BY_KIND, "entity_type_by_kind 與鎖定對映不符", failures)
assert(rep.dig("source_version", "basis") == EXPECTED_SOURCE_VERSION_BASIS && target[:source_version_basis].include?(EXPECTED_SOURCE_VERSION_BASIS),
       "source_version.basis 必須是 CONTENT_ONLY 且為 raw-evidence source_version.basis enum 成員", failures)
assert(rep.dig("source_version", "kind") == EXPECTED_SOURCE_VERSION_KIND && target[:source_version_kind].include?(EXPECTED_SOURCE_VERSION_KIND),
       "source_version.kind 必須是 CONTENT_DIGEST 且為 raw-evidence source_version.kind enum 成員", failures)
structured_by_kind = rep.dig("payload", "structured_profile_by_kind") || {}
assert(structured_by_kind == EXPECTED_STRUCTURED_PROFILE_BY_KIND, "payload.structured_profile_by_kind 與鎖定對映不符", failures)
assert((structured_by_kind.values - target[:structured_profile]).empty?,
       "payload.structured_profile_by_kind 值必須是 raw-evidence payload.structured_profile enum 成員", failures)
assert(rep.dig("payload", "canonicalization_profile") == EXPECTED_CANONICALIZATION_PROFILE && target[:canonicalization_profile].include?(EXPECTED_CANONICALIZATION_PROFILE),
       "payload.canonicalization_profile 必須是 NONE 且為 raw-evidence payload.canonicalization_profile enum 成員", failures)
ingestion_modes = rep.dig("provenance", "allowed_ingestion_modes").to_a
assert(ingestion_modes == EXPECTED_INGESTION_MODES, "provenance.allowed_ingestion_modes 必須是 [MANUAL_UPLOAD, BULK_EXPORT]", failures)
assert((ingestion_modes - target[:ingestion_mode]).empty?,
       "provenance.allowed_ingestion_modes 必須是 raw-evidence provenance.ingestion_mode enum 子集", failures)

sap = spec.fetch("source_anchor_projection", {})
assert(sap.fetch("profile_by_kind", {}) == EXPECTED_ANCHOR_PROFILE_BY_KIND, "source_anchor_projection.profile_by_kind 與鎖定對映不符", failures)
assert(sap.fetch("required_selector_type_by_kind", {}) == EXPECTED_REQUIRED_SELECTOR_BY_KIND, "required_selector_type_by_kind 與鎖定對映不符", failures)
assert(sap["normalization_profile"] == "OMOS_TEXT_NORM_V1", "normalization_profile 必須是 OMOS_TEXT_NORM_V1", failures)
%w[PDF_REGION_V1 MARKDOWN_TEXT_V1].each do |profile|
  assert(
    sorted_set(sap.dig("profile_details_shape", profile).to_a) == sorted_set(target[:profile_details_shape].fetch(profile)),
    "source_anchor_projection.profile_details_shape.#{profile} 必須逐字等於 locked profile schema 的 profile_details.required",
    failures
  )
end

ndp = spec.fetch("normalized_document_projection", {})
assert(sorted_set(ndp.fetch("allowed_block_types", [])) == sorted_set(target[:block_type]), "allowed_block_types 必須剛好等於 normalized-document-block schema 的 block_type enum", failures)
assert(ndp.fetch("content_layer_by_block_type", {}) == EXPECTED_CONTENT_LAYER_BY_BLOCK_TYPE, "content_layer_by_block_type 與鎖定對映不符", failures)
assert(ndp.fetch("attribute_required_by_block_type", {}) == EXPECTED_ATTR_REQUIRED_BY_BLOCK_TYPE, "attribute_required_by_block_type 與鎖定對映不符", failures)

derivation = spec.fetch("deterministic_derivation", {})
assert(sorted_set(derivation.fetch("inputs", [])) == sorted_set(%w[content_digest adapter_id adapter_version]), "deterministic_derivation.inputs 與鎖定清單不符", failures)
assert(derivation.fetch("derived", []).include?("projection_digest"), "deterministic_derivation.derived 必須含 projection_digest", failures)
assert(derivation.fetch("excluded_from_canonical_digest", []) == DETERMINISTIC_EXCLUDED_PATHS,
       "deterministic_derivation.excluded_from_canonical_digest 必須逐字等於 validator 的 DETERMINISTIC_EXCLUDED_PATHS", failures)
assert(derivation.fetch("identity_bearing_fields", []) == IDENTITY_BEARING_FIELDS,
       "deterministic_derivation.identity_bearing_fields 必須逐字等於 validator 的 IDENTITY_BEARING_FIELDS", failures)

assert(spec.dig("instance_validation", "engine") == "scripts/validate_document_adapter_mapping_instances.py", "instance_validation.engine 必須指向 companion", failures)
assert(File.exist?(INSTANCE_ENGINE_PATH), "companion JSON Schema engine 檔案必須存在", failures)

must_match = spec.dig("cross_reference", "must_match") || {}
{
  "payload_structured_profile_from" => "raw-evidence-envelope.properties.payload.structured_profile.enum",
  "pdf_profile_details_shape_from" => "source-anchor-pdf-region-v1.profile_details.required",
  "markdown_profile_details_shape_from" => "source-anchor-markdown-text-v1.profile_details.required",
  "selector_type_from" => "source-anchor.properties.selectors.items.selector_type.enum",
  "block_type_from" => "normalized-document-block.properties.block_type.enum",
  "content_layer_from" => "normalized-document-block.properties.content_layer.enum"
}.each do |pointer_key, expected_path|
  assert(must_match[pointer_key] == expected_path, "cross_reference.must_match.#{pointer_key} 必須是 #{expected_path}", failures)
end
assert(present?(target[:profile_details_shape]["PDF_REGION_V1"]) && target[:profile_details_shape]["PDF_REGION_V1"].include?("bbox"), "locked PDF profile_details.required 必須存在且含 bbox", failures)
assert(present?(target[:profile_details_shape]["MARKDOWN_TEXT_V1"]) && target[:profile_details_shape]["MARKDOWN_TEXT_V1"].include?("codepoint_range"), "locked Markdown profile_details.required 必須存在且含 codepoint_range", failures)

assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_DOC_MAP_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定 label 清單不符",
  failures
)
assert(
  sorted_set(spec.fetch("required_instance_negative_fixtures", [])) == sorted_set(EXPECTED_INSTANCE_NEGATIVE_LABELS),
  "required_instance_negative_fixtures 與鎖定 label 清單不符",
  failures
)

positive = read_json(POSITIVE_FIXTURE_PATH)
negative = read_json(NEGATIVE_FIXTURE_PATH)
instance_negative = read_json(INSTANCE_NEGATIVE_FIXTURE_PATH)

positive_cases = positive.fetch("document_mapping_cases")
positive_by_id = positive_cases.each_with_object({}) { |test_case, acc| acc[test_case.fetch("case_id")] = test_case }

positive_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  kind = test_case.fetch("source_kind")
  assert(test_case.fetch("expected") == "allow", "#{case_id} doc-map positive 必須預期 allow", failures)
  actual = document_mapping_failure(test_case, target)
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)

  # --- spec ↔ fixture 一致：raw_evidence_instance 必須符合 mapping table ---
  raw_instance = test_case.fetch("raw_evidence_instance")
  assert(raw_instance.dig("source_identity", "source_system") == rep["source_system"], "#{case_id} raw instance source_system 與 mapping 不一致", failures)
  assert(raw_instance.dig("source_identity", "entity_type") == EXPECTED_ENTITY_TYPE_BY_KIND[kind], "#{case_id} raw instance entity_type 與 mapping 不一致", failures)
  assert(raw_instance.dig("payload", "structured_profile") == EXPECTED_STRUCTURED_PROFILE_BY_KIND[kind], "#{case_id} raw instance payload.structured_profile 與 mapping 不一致", failures)
  assert(raw_instance.dig("payload", "canonicalization_profile") == EXPECTED_CANONICALIZATION_PROFILE, "#{case_id} raw instance payload.canonicalization_profile 與 mapping 不一致", failures)
  assert(EXPECTED_INGESTION_MODES.include?(raw_instance.dig("provenance", "ingestion_mode")), "#{case_id} raw instance provenance.ingestion_mode 不在 allowed_ingestion_modes 內", failures)
  assert(raw_instance.dig("source_version", "basis") == EXPECTED_SOURCE_VERSION_BASIS, "#{case_id} raw instance source_version.basis 與 mapping 不一致", failures)
  assert(raw_instance.dig("source_version", "kind") == EXPECTED_SOURCE_VERSION_KIND, "#{case_id} raw instance source_version.kind 與 mapping 不一致", failures)

  # --- spec ↔ fixture 一致：source_anchor_instance / block_instances ---
  anchor_instance = test_case.fetch("source_anchor_instance")
  assert(anchor_instance["profile"] == EXPECTED_ANCHOR_PROFILE_BY_KIND[kind], "#{case_id} anchor instance profile 與 mapping 不一致", failures)
  assert(anchor_instance["selectors"].to_a.any? { |sel| sel["selector_type"] == EXPECTED_REQUIRED_SELECTOR_BY_KIND[kind] }, "#{case_id} anchor instance 缺 required selector", failures)
  assert(anchor_instance["normalization_profile"] == "OMOS_TEXT_NORM_V1", "#{case_id} anchor instance normalization_profile 與 mapping 不一致", failures)
  test_case.fetch("block_instances").each_with_index do |block, index|
    expected_layer = EXPECTED_CONTENT_LAYER_BY_BLOCK_TYPE[block["block_type"]]
    assert(block["content_layer"] == expected_layer, "#{case_id} block[#{index}] (#{block["block_type"]}) content_layer 與 mapping 不一致", failures)
  end

  # --- deterministic derivation：validator 自算 canonical projection digest ---
  base_triple = triple_of(test_case)
  runtime_patch = test_case.dig("determinism", "runtime_only_patch") || {}
  assert(!runtime_patch.empty?, "#{case_id} 必須帶 determinism.runtime_only_patch（證明 runtime 欄位不影響 digest）", failures)
  assert(runtime_patch.keys.all? { |path| DETERMINISTIC_EXCLUDED_PATHS.include?(path) },
         "#{case_id} determinism.runtime_only_patch 只能改 excluded_from_canonical_digest 內的 path", failures)
  assert(!test_case.dig("determinism", "two_runs"), "#{case_id} 不得再自報 determinism.two_runs / projection_digest（改由 validator 計算）", failures)
  patched_triple = deep_dup(base_triple)
  runtime_patch.each { |path, value| set_path(patched_triple, path, value) }
  assert(projection_digest(base_triple) == projection_digest(patched_triple),
         "#{case_id} 只改 runtime 欄位卻改變了 canonical projection digest（determinism 破損）", failures)
  IDENTITY_BEARING_FIELDS.each do |path|
    assert(read_path(base_triple, path) == read_path(patched_triple, path),
           "#{case_id} identity-bearing 欄位 #{path} 在 runtime-only patch 後改變", failures)
  end
end

# mapping 語意負例（evaluator 驅動）。determinism 負例（帶 base_case_ref）另段處理。
negative.fetch("document_mapping_negative_cases").each do |test_case|
  next if test_case.key?("base_case_ref")

  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} doc-map negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = document_mapping_failure(test_case, target)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

# determinism 負例：對 stable 欄位做變更，validator 自算的 canonical projection digest 必須改變。
determinism_negatives = negative.fetch("document_mapping_negative_cases").select { |test_case| test_case.key?("base_case_ref") }
assert(!determinism_negatives.empty?, "至少要有一個 determinism 負例（base_case_ref + stable_field_mutation）", failures)
determinism_negatives.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} determinism 負例必須預期 deny", failures)
  assert(test_case.fetch("expected_failure_code") == "DOC_MAP_NONDETERMINISTIC_IDENTITY", "#{case_id} expected_failure_code 必須是 DOC_MAP_NONDETERMINISTIC_IDENTITY", failures)
  base_case = positive_by_id.fetch(test_case.fetch("base_case_ref"))
  base_triple = triple_of(base_case)
  mutated_triple = deep_dup(base_triple)
  mutation = test_case.fetch("stable_field_mutation")
  assert(!mutation.empty?, "#{case_id} stable_field_mutation 不得為空", failures)
  assert(mutation.keys.none? { |path| DETERMINISTIC_EXCLUDED_PATHS.include?(path) },
         "#{case_id} stable_field_mutation 不能只改 excluded path（那不是 stable 欄位）", failures)
  mutation.each { |path, value| set_path(mutated_triple, path, value) }
  assert(projection_digest(base_triple) != projection_digest(mutated_triple),
         "#{case_id}: 對 stable 欄位變更後 canonical projection digest 未變 —— determinism gate 失效", failures)
end

covered_labels = sorted_set(negative.fetch("document_mapping_negative_cases").map { |test_case| test_case.fetch("covers_doc_map_negative_fixture") })
missing_labels = sorted_set(EXPECTED_DOC_MAP_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "doc-map negative fixtures 未覆蓋：#{missing_labels.join(", ")}", failures)

# --- P2：instance-negative fixtures 是活契約，不能被刪 ---
instance_negative_cases = instance_negative.fetch("instance_negative_cases")
instance_covered = sorted_set(instance_negative_cases.map { |test_case| test_case.fetch("covers") })
assert(instance_covered == sorted_set(EXPECTED_INSTANCE_NEGATIVE_LABELS),
       "instance_negative_cases.covers 必須剛好等於 required_instance_negative_fixtures：實際 #{instance_covered.inspect}", failures)
instance_ids = instance_negative_cases.map { |test_case| test_case.fetch("case_id") }
assert(instance_ids.uniq.length == instance_ids.length, "instance_negative_cases.case_id 必須唯一", failures)
instance_negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(present?(test_case["target_schema"]), "#{case_id} 必須帶 target_schema", failures)
  assert(test_case["expected_result"] == "REJECT", "#{case_id} expected_result 必須是 REJECT", failures)
  assert(test_case.key?("instance"), "#{case_id} 必須帶 instance", failures)
end

if failures.empty?
  puts "PASS document adapter mapping contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
