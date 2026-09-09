#!/usr/bin/env ruby

# repo #2 / Document Adapter Mapping 契約 validator。
# 薄判斷：結構斷言（mapping table 的值必須是 STD-01/02/03 已鎖 schema 的合法欄位／enum）
# + 純函式 `document_mapping_failure(projection, target)` evaluator（PDF / Markdown 兩路）。
# 交叉讀 raw-evidence-envelope / source-anchor / normalized-document-block schema（pointer binding）。
# 沿用 scripts/lib/omos_contract_helpers.rb。

require "json"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/document-adapter-mapping.yaml")
RAW_EVIDENCE_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/raw-evidence-envelope.schema.json")
SOURCE_ANCHOR_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/source-anchor.schema.json")
BLOCK_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/normalized-document-block.schema.json")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/document-adapter-mapping-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/document-adapter-mapping-negative-fixtures.json")

EXPECTED_SOURCE_KINDS = %w[PDF MARKDOWN].freeze
EXPECTED_STRUCTURED_PROFILE_BY_KIND = { "PDF" => "BINARY", "MARKDOWN" => "TEXT" }.freeze
EXPECTED_ANCHOR_PROFILE_BY_KIND = { "PDF" => "PDF_REGION_V1", "MARKDOWN" => "MARKDOWN_TEXT_V1" }.freeze
EXPECTED_REQUIRED_SELECTOR_BY_KIND = { "PDF" => "PDF_REGION", "MARKDOWN" => "TEXT_POSITION" }.freeze
EXPECTED_INGESTION_MODES = %w[MANUAL_UPLOAD BULK_EXPORT].freeze
EXPECTED_PROFILE_DETAILS_SHAPE = {
  "PDF_REGION_V1" => %w[page bbox_normalized coordinate_origin],
  "MARKDOWN_TEXT_V1" => %w[codepoint_start codepoint_end line_start line_end]
}.freeze
EXPECTED_CONTENT_LAYER_BY_BLOCK_TYPE = {
  "title" => "TITLE", "section_header" => "TITLE", "paragraph" => "BODY", "list_item" => "BODY",
  "code" => "CODE", "table" => "TABLE", "image" => "IMAGE", "unknown" => "UNKNOWN"
}.freeze
EXPECTED_ATTR_REQUIRED_BY_BLOCK_TYPE = { "table" => "table", "image" => "asset" }.freeze

EXPECTED_DOC_MAP_NEGATIVE_LABELS = [
  "a source kind outside PDF / MARKDOWN",
  "a projected field is not a property of the target schema",
  "source identity uses a non-content basis",
  "the payload is inline content instead of a reference",
  "the source anchor profile does not match the source kind",
  "the required selector type is missing",
  "profile_details has the wrong key set",
  "a block uses an unknown block type",
  "a block content_layer disagrees with its block type",
  "a table or image block is missing its attributes",
  "a block has no source anchor reference",
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

def numeric_in_unit_interval?(value)
  value.is_a?(Numeric) && value >= 0 && value <= 1
end

# 純函式:一份 adapter 投影 -> nil 或精確 machine failure code。
# projection 是自足 fixture 物件:source_kind / raw_evidence / source_anchor /
# normalized_blocks / error / ok。target 是由 STD schema 抽出的 enum / property 集合。
def document_mapping_failure(projection, target)
  kind = projection["source_kind"]
  return "DOC_MAP_UNKNOWN_SOURCE_KIND" unless EXPECTED_SOURCE_KINDS.include?(kind)
  return "FAIL_SILENT" if present?(projection["error"]) && projection["ok"] != false

  raw = projection["raw_evidence"] || {}
  claimed_fields = raw["claimed_field_keys"].to_a
  return "DOC_MAP_FIELD_NOT_IN_TARGET_SCHEMA" unless (claimed_fields - target[:raw_evidence_props]).empty?
  return "DOC_MAP_NONDETERMINISTIC_IDENTITY" unless raw.dig("source_identity", "native_id_basis") == "CONTENT_SHA256"

  payload = raw["payload"] || {}
  return "DOC_MAP_PAYLOAD_INLINE" if present?(payload["inline_content"]) || !present?(payload["payload_ref"])
  expected_sp = EXPECTED_STRUCTURED_PROFILE_BY_KIND.fetch(kind)
  return "DOC_MAP_PROFILE_MISMATCH" unless payload["structured_profile"] == expected_sp && target[:structured_profile].include?(expected_sp)
  return "DOC_MAP_PROFILE_MISMATCH" unless EXPECTED_INGESTION_MODES.include?(raw.dig("provenance", "ingestion_mode"))

  anchor = projection["source_anchor"] || {}
  expected_profile = EXPECTED_ANCHOR_PROFILE_BY_KIND.fetch(kind)
  return "DOC_MAP_PROFILE_MISMATCH" unless anchor["profile"] == expected_profile && target[:anchor_profile].include?(expected_profile)

  required_selector = EXPECTED_REQUIRED_SELECTOR_BY_KIND.fetch(kind)
  selectors = anchor["selectors"].to_a
  unless selectors.any? { |selector| selector["selector_type"] == required_selector } && target[:selector_type].include?(required_selector)
    return "DOC_MAP_SELECTOR_MISSING"
  end

  details = anchor["profile_details"]
  return "DOC_MAP_PROFILE_DETAILS_MALFORMED" unless details.is_a?(Hash) &&
                                                   sorted_set(details.keys) == sorted_set(EXPECTED_PROFILE_DETAILS_SHAPE.fetch(expected_profile))
  if expected_profile == "PDF_REGION_V1"
    return "DOC_MAP_PROFILE_DETAILS_MALFORMED" unless details["page"].is_a?(Integer) && details["page"].positive?
    bbox = details["bbox_normalized"]
    return "DOC_MAP_PROFILE_DETAILS_MALFORMED" unless bbox.is_a?(Array) && bbox.length == 4 && bbox.all? { |value| numeric_in_unit_interval?(value) }
  else
    points = [details["codepoint_start"], details["codepoint_end"], details["line_start"], details["line_end"]]
    return "DOC_MAP_PROFILE_DETAILS_MALFORMED" unless points.all? { |value| value.is_a?(Integer) }
    return "DOC_MAP_PROFILE_DETAILS_MALFORMED" unless details["codepoint_end"] > details["codepoint_start"] &&
                                                     details["codepoint_start"] >= 0 &&
                                                     details["line_end"] >= details["line_start"] &&
                                                     details["line_start"] >= 1
  end
  return "DOC_MAP_PROFILE_DETAILS_MALFORMED" unless anchor["normalization_profile"] == "OMOS_TEXT_NORM_V1"

  projection["normalized_blocks"].to_a.each do |block|
    block_type = block["block_type"]
    return "DOC_MAP_BLOCK_TYPE_UNKNOWN" unless target[:block_type].include?(block_type)
    return "DOC_MAP_CONTENT_LAYER_MISMATCH" unless block["content_layer"] == EXPECTED_CONTENT_LAYER_BY_BLOCK_TYPE.fetch(block_type)
    required_attr = EXPECTED_ATTR_REQUIRED_BY_BLOCK_TYPE[block_type]
    return "DOC_MAP_TABLE_IMAGE_ATTR_MISSING" if required_attr && !block["attributes"].to_h.key?(required_attr)
    return "DOC_MAP_BLOCK_NOT_ANCHORED" unless block["source_anchor_refs"].is_a?(Array) && !block["source_anchor_refs"].empty?
  end

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)
raw_schema = read_json(RAW_EVIDENCE_SCHEMA_PATH)
anchor_schema = read_json(SOURCE_ANCHOR_SCHEMA_PATH)
block_schema = read_json(BLOCK_SCHEMA_PATH)

target = {
  raw_evidence_props: raw_schema.fetch("properties").keys,
  structured_profile: raw_schema.dig("properties", "payload", "properties", "structured_profile", "enum").to_a,
  anchor_profile: anchor_schema.dig("properties", "profile", "enum").to_a,
  selector_type: anchor_schema.dig("properties", "selectors", "items", "properties", "selector_type", "enum").to_a,
  block_type: block_schema.dig("properties", "block_type", "enum").to_a,
  content_layer: block_schema.dig("properties", "content_layer", "enum").to_a
}

schema = spec.fetch("schema", {})
assert(schema["schema_id"] == "urn:omos:schema:document-adapter-mapping:0.1.0", "schema_id 必須是 document-adapter-mapping:0.1.0", failures)
assert(schema["version"] == "0.1.0", "schema.version 必須是 0.1.0", failures)
assert(schema.fetch("traces_to", []).include?("DOC-ADAPTER-MAPPING"), "schema.traces_to 必須包含 DOC-ADAPTER-MAPPING", failures)
assert(spec.dig("purpose", "no_second_workflow_authority") == true, "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec["runtime_independence"] == true, "runtime_independence 必須為 true", failures)
assert(spec.fetch("source_kinds", []) == EXPECTED_SOURCE_KINDS, "source_kinds 必須剛好是 [PDF, MARKDOWN]", failures)

rep = spec.fetch("raw_evidence_projection", {})
assert(rep["source_system"] == "document", "raw_evidence_projection.source_system 必須是 document", failures)
assert(rep.dig("payload", "structured_profile_by_kind") == EXPECTED_STRUCTURED_PROFILE_BY_KIND, "structured_profile_by_kind 與鎖定對映不符", failures)
EXPECTED_STRUCTURED_PROFILE_BY_KIND.each_value do |value|
  assert(target[:structured_profile].include?(value), "structured_profile #{value} 必須是 raw-evidence-envelope schema enum 成員", failures)
end
assert(sorted_set(rep.dig("provenance", "allowed_ingestion_modes").to_a) == sorted_set(EXPECTED_INGESTION_MODES), "allowed_ingestion_modes 與鎖定清單不符", failures)
raw_enum_modes = raw_schema.dig("properties", "provenance", "properties", "ingestion_mode", "enum").to_a
assert((EXPECTED_INGESTION_MODES - raw_enum_modes).empty?, "allowed_ingestion_modes 必須是 raw-evidence provenance.ingestion_mode enum 子集", failures)

sap = spec.fetch("source_anchor_projection", {})
assert(sap.fetch("profile_by_kind", {}) == EXPECTED_ANCHOR_PROFILE_BY_KIND, "source_anchor_projection.profile_by_kind 與鎖定對映不符", failures)
EXPECTED_ANCHOR_PROFILE_BY_KIND.each_value do |value|
  assert(target[:anchor_profile].include?(value), "anchor profile #{value} 必須是 source-anchor schema enum 成員", failures)
end
assert(sap.fetch("required_selector_type_by_kind", {}) == EXPECTED_REQUIRED_SELECTOR_BY_KIND, "required_selector_type_by_kind 與鎖定對映不符", failures)
EXPECTED_REQUIRED_SELECTOR_BY_KIND.each_value do |value|
  assert(target[:selector_type].include?(value), "selector_type #{value} 必須是 source-anchor selectors enum 成員", failures)
end
assert(sap["normalization_profile"] == "OMOS_TEXT_NORM_V1", "source_anchor_projection.normalization_profile 必須是 OMOS_TEXT_NORM_V1", failures)
assert(sap.fetch("profile_details_shape", {}) == EXPECTED_PROFILE_DETAILS_SHAPE, "profile_details_shape 與鎖定不符", failures)

ndp = spec.fetch("normalized_document_projection", {})
assert(sorted_set(ndp.fetch("allowed_block_types", [])) == sorted_set(target[:block_type]), "normalized_document_projection.allowed_block_types 必須剛好等於 normalized-document-block schema 的 block_type enum", failures)
assert(ndp.fetch("content_layer_by_block_type", {}) == EXPECTED_CONTENT_LAYER_BY_BLOCK_TYPE, "content_layer_by_block_type 與鎖定對映不符", failures)
EXPECTED_CONTENT_LAYER_BY_BLOCK_TYPE.each_value do |value|
  assert(target[:content_layer].include?(value), "content_layer #{value} 必須是 normalized-document-block schema enum 成員", failures)
end
assert(ndp.fetch("attribute_required_by_block_type", {}) == EXPECTED_ATTR_REQUIRED_BY_BLOCK_TYPE, "attribute_required_by_block_type 與鎖定對映不符", failures)

must_match = spec.dig("cross_reference", "must_match") || {}
{
  "payload_structured_profile_from" => "raw-evidence-envelope.properties.payload.structured_profile.enum",
  "source_anchor_profile_from" => "source-anchor.properties.profile.enum",
  "selector_type_from" => "source-anchor.properties.selectors.items.selector_type.enum",
  "block_type_from" => "normalized-document-block.properties.block_type.enum",
  "content_layer_from" => "normalized-document-block.properties.content_layer.enum"
}.each do |pointer_key, expected_path|
  assert(must_match[pointer_key] == expected_path, "cross_reference.must_match.#{pointer_key} 必須是 #{expected_path}", failures)
end
assert(present?(target[:raw_evidence_props]) && target[:raw_evidence_props].include?("payload"), "raw-evidence-envelope schema properties 必須存在且含 payload", failures)

assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_DOC_MAP_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定 label 清單不符",
  failures
)

positive = read_json(POSITIVE_FIXTURE_PATH)
negative = read_json(NEGATIVE_FIXTURE_PATH)

positive.fetch("document_mapping_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} doc-map positive 必須預期 allow", failures)
  actual = document_mapping_failure(test_case.fetch("projection"), target)
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

negative.fetch("document_mapping_negative_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} doc-map negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = document_mapping_failure(test_case.fetch("projection"), target)
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
