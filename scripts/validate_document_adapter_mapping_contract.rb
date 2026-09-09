#!/usr/bin/env ruby

# repo #2 / Document Adapter Mapping 契約 validator（mapping 語意層）。
# 薄判斷：結構斷言（mapping table 的值必須是 STD-01/02/03 已鎖 schema 的合法欄位／enum，
# 且 profile_details_shape 必須逐字等於 locked profile-specific schema 的
# profile_details.required）+ 純函式 `document_mapping_failure(case)` evaluator（mapping
# 語意 + deterministic derivation）。
#
# 投影出的 RawEvidenceEnvelope / SourceAnchor / NormalizedDocumentBlock 是否為
# schema-valid instance，由 companion `scripts/validate_document_adapter_mapping_instances.py`
# 以 JSON Schema engine 驗（instance_validation gate）。
#
# 沿用 scripts/lib/omos_contract_helpers.rb。

require "json"
require "yaml"
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

EXPECTED_SOURCE_KINDS = %w[PDF MARKDOWN].freeze
EXPECTED_ANCHOR_PROFILE_BY_KIND = { "PDF" => "PDF_REGION_V1", "MARKDOWN" => "MARKDOWN_TEXT_V1" }.freeze
EXPECTED_REQUIRED_SELECTOR_BY_KIND = { "PDF" => "PDF_REGION", "MARKDOWN" => "TEXT_POSITION" }.freeze
EXPECTED_CONTENT_LAYER_BY_BLOCK_TYPE = {
  "title" => "TITLE", "section_header" => "TITLE", "paragraph" => "BODY", "list_item" => "BODY",
  "code" => "CODE", "table" => "TABLE", "image" => "IMAGE", "unknown" => "UNKNOWN"
}.freeze
EXPECTED_ATTR_REQUIRED_BY_BLOCK_TYPE = { "table" => "table", "image" => "asset" }.freeze

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

# 純函式:一份 mapping 語意 case -> nil 或精確 machine failure code。
# case 是自足 fixture 物件:source_kind / mapping{...} / determinism{two_runs:[...]} / error / ok。
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

  runs = test_case.dig("determinism", "two_runs").to_a
  if runs.length == 2
    return "DOC_MAP_NONDETERMINISTIC_IDENTITY" if runs[0]["inputs"] == runs[1]["inputs"] &&
                                                  runs[0]["projection_digest"] != runs[1]["projection_digest"]
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

def profile_details_required(profile_schema)
  profile_schema.fetch("allOf").each do |part|
    next unless part.is_a?(Hash)

    required = part.dig("properties", "profile_details", "required")
    return required.to_a if required
  end
  []
end

target = {
  structured_profile: raw_schema.dig("properties", "payload", "properties", "structured_profile", "enum").to_a,
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

sap = spec.fetch("source_anchor_projection", {})
assert(sap.fetch("profile_by_kind", {}) == EXPECTED_ANCHOR_PROFILE_BY_KIND, "source_anchor_projection.profile_by_kind 與鎖定對映不符", failures)
assert(sap.fetch("required_selector_type_by_kind", {}) == EXPECTED_REQUIRED_SELECTOR_BY_KIND, "required_selector_type_by_kind 與鎖定對映不符", failures)
assert(sap["normalization_profile"] == "OMOS_TEXT_NORM_V1", "normalization_profile 必須是 OMOS_TEXT_NORM_V1", failures)
# profile_details_shape 必須逐字等於 locked profile-specific schema 的 profile_details.required
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

positive = read_json(POSITIVE_FIXTURE_PATH)
negative = read_json(NEGATIVE_FIXTURE_PATH)

positive.fetch("document_mapping_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} doc-map positive 必須預期 allow", failures)
  actual = document_mapping_failure(test_case, target)
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

negative.fetch("document_mapping_negative_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} doc-map negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = document_mapping_failure(test_case, target)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

covered_labels = sorted_set(negative.fetch("document_mapping_negative_cases").map { |test_case| test_case.fetch("covers_doc_map_negative_fixture") })
missing_labels = sorted_set(EXPECTED_DOC_MAP_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "doc-map negative fixtures 未覆蓋：#{missing_labels.join(", ")}", failures)

if failures.empty?
  puts "PASS document adapter mapping contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
