#!/usr/bin/env ruby

# repo #3 / Jira Adapter Mapping 契約 validator。
# 薄判斷：結構斷言（mapping table 的值必須是 STD-01 + Jira anchor profile schema 的合法欄位／
# enum）+ 純函式 `jira_mapping_failure(projection, target)` evaluator。
# 交叉讀 raw-evidence-envelope / source-anchor-jira-cloud-entity-segment-v1 schema（pointer binding）。
# 沿用 scripts/lib/omos_contract_helpers.rb。

require "json"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/jira-adapter-mapping.yaml")
RAW_EVIDENCE_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/raw-evidence-envelope.schema.json")
JIRA_PROFILE_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/source-anchor-jira-cloud-entity-segment-v1.schema.json")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/jira-adapter-mapping-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/jira-adapter-mapping-negative-fixtures.json")

EXPECTED_JIRA_FIELD_KINDS = %w[SUMMARY DESCRIPTION COMMENT_BODY ADF_TEXT_NODE].freeze
EXPECTED_INGESTION_MODES = %w[WEBHOOK POLL BULK_EXPORT].freeze
EXPECTED_TRANSPORT_KINDS = %w[WEBHOOK POLL].freeze
EXPECTED_FIELD_ID_BY_KIND = {
  "SUMMARY" => "summary", "DESCRIPTION" => "description",
  "COMMENT_BODY" => "comment", "ADF_TEXT_NODE" => "description"
}.freeze
ISSUE_ID_PATTERN = /\A[0-9]+\z/.freeze

EXPECTED_JIRA_MAP_NEGATIVE_LABELS = [
  "a field kind outside SUMMARY / DESCRIPTION / COMMENT_BODY / ADF_TEXT_NODE",
  "a projected field is not a property of the target schema",
  "source identity uses a non-native basis",
  "the payload is inline content instead of a reference",
  "the source version is not compound-observed with a secondary digest",
  "the source anchor profile is not the Jira cloud entity segment profile",
  "the JSON_POINTER selector is missing",
  "profile_details has the wrong key set",
  "reconciliation changes an existing evidence identity",
  "reconciliation drops a detected gap without emitting evidence",
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

# 純函式:一份 adapter 投影 -> nil 或精確 machine failure code。
def jira_mapping_failure(projection, target)
  kind = projection["field_kind"]
  return "JIRA_MAP_UNKNOWN_FIELD_KIND" unless EXPECTED_JIRA_FIELD_KINDS.include?(kind)
  return "FAIL_SILENT" if present?(projection["error"]) && projection["ok"] != false

  raw = projection["raw_evidence"] || {}
  return "JIRA_MAP_FIELD_NOT_IN_TARGET_SCHEMA" unless (raw["claimed_field_keys"].to_a - target[:raw_evidence_props]).empty?
  return "JIRA_MAP_NONDETERMINISTIC_IDENTITY" unless raw.dig("source_identity", "native_id_basis") == "JIRA_CLOUD_ID_PLUS_ISSUE_ID"

  payload = raw["payload"] || {}
  return "JIRA_MAP_PAYLOAD_INLINE" if present?(payload["inline_content"]) || !present?(payload["payload_ref"])

  version = raw["source_version"] || {}
  unless version["basis"] == "COMPOUND_OBSERVED" && target[:source_version_basis].include?("COMPOUND_OBSERVED") &&
         version["kind"] == "UPDATED_AT_DIGEST" && target[:source_version_kind].include?("UPDATED_AT_DIGEST") &&
         present?(version["secondary_digest"])
    return "JIRA_MAP_VERSION_NOT_COMPOUND"
  end

  anchor = projection["source_anchor"] || {}
  return "JIRA_MAP_PROFILE_MISMATCH" unless anchor["profile"] == "JIRA_CLOUD_ENTITY_SEGMENT_V1" &&
                                           anchor["profile"] == target[:jira_profile_const]

  selectors = anchor["selectors"].to_a
  return "JIRA_MAP_SELECTOR_MISSING" unless selectors.any? { |selector| selector["selector_type"] == "JSON_POINTER" }

  details = anchor["profile_details"]
  return "JIRA_MAP_PROFILE_DETAILS_MALFORMED" unless details.is_a?(Hash) &&
                                                    sorted_set(details.keys) == sorted_set(target[:jira_profile_details_shape])
  return "JIRA_MAP_PROFILE_DETAILS_MALFORMED" unless details["deployment_type"] == "CLOUD" && details["entity_type"] == "issue"
  return "JIRA_MAP_PROFILE_DETAILS_MALFORMED" unless details["issue_id"].is_a?(String) && ISSUE_ID_PATTERN.match?(details["issue_id"])

  text_selector = details["text_selector"] || {}
  return "JIRA_MAP_PROFILE_DETAILS_MALFORMED" unless text_selector["unit"] == "UNICODE_CODE_POINT" &&
                                                    text_selector["range_semantics"] == "START_INCLUSIVE_END_EXCLUSIVE"
  return "JIRA_MAP_PROFILE_DETAILS_MALFORMED" unless text_selector["start"].is_a?(Integer) && text_selector["end"].is_a?(Integer) &&
                                                    text_selector["end"] >= text_selector["start"] && text_selector["start"] >= 0
  return "JIRA_MAP_PROFILE_DETAILS_MALFORMED" unless anchor["normalization_profile"] == "OMOS_TEXT_NORM_V1"

  reconciliation = projection["reconciliation"]
  if reconciliation.is_a?(Hash)
    return "JIRA_MAP_RECONCILIATION_CHANGES_IDENTITY" if reconciliation["changed_identity"] == true
    if reconciliation["detected_gap"] == true && reconciliation["emitted_evidence_or_gap"] != true
      return "JIRA_MAP_RECONCILIATION_SILENT_GAP"
    end
  end

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)
raw_schema = read_json(RAW_EVIDENCE_SCHEMA_PATH)
jira_profile_schema = read_json(JIRA_PROFILE_SCHEMA_PATH)

jira_profile_body = jira_profile_schema.fetch("allOf").find { |part| part.is_a?(Hash) && part["type"] == "object" } || {}
target = {
  raw_evidence_props: raw_schema.fetch("properties").keys,
  source_version_basis: raw_schema.dig("properties", "source_version", "properties", "basis", "enum").to_a,
  source_version_kind: raw_schema.dig("properties", "source_version", "properties", "kind", "enum").to_a,
  ingestion_mode: raw_schema.dig("properties", "provenance", "properties", "ingestion_mode", "enum").to_a,
  jira_profile_const: jira_profile_body.dig("properties", "profile", "const"),
  jira_profile_details_shape: jira_profile_body.dig("properties", "profile_details", "required").to_a
}

schema = spec.fetch("schema", {})
assert(schema["schema_id"] == "urn:omos:schema:jira-adapter-mapping:0.1.0", "schema_id 必須是 jira-adapter-mapping:0.1.0", failures)
assert(schema["version"] == "0.1.0", "schema.version 必須是 0.1.0", failures)
assert(schema.fetch("traces_to", []).include?("JIRA-ADAPTER-MAPPING"), "schema.traces_to 必須包含 JIRA-ADAPTER-MAPPING", failures)
assert(spec.dig("purpose", "no_second_workflow_authority") == true, "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec["runtime_independence"] == true, "runtime_independence 必須為 true", failures)
assert(spec.fetch("jira_field_kinds", []) == EXPECTED_JIRA_FIELD_KINDS, "jira_field_kinds 與鎖定清單不符", failures)

rep = spec.fetch("raw_evidence_projection", {})
assert(rep["source_system"] == "jira-cloud", "raw_evidence_projection.source_system 必須是 jira-cloud", failures)
assert(rep["entity_type"] == "issue", "raw_evidence_projection.entity_type 必須是 issue", failures)
assert(rep.dig("source_version", "basis") == "COMPOUND_OBSERVED", "source_version.basis 必須是 COMPOUND_OBSERVED", failures)
assert(rep.dig("source_version", "kind") == "UPDATED_AT_DIGEST", "source_version.kind 必須是 UPDATED_AT_DIGEST", failures)
assert(target[:source_version_basis].include?("COMPOUND_OBSERVED"), "COMPOUND_OBSERVED 必須是 raw-evidence source_version.basis enum 成員", failures)
assert(target[:source_version_kind].include?("UPDATED_AT_DIGEST"), "UPDATED_AT_DIGEST 必須是 raw-evidence source_version.kind enum 成員", failures)
assert(rep.dig("payload", "structured_profile") == "I_JSON", "payload.structured_profile 必須是 I_JSON", failures)
assert(sorted_set(rep.dig("provenance", "allowed_ingestion_modes").to_a) == sorted_set(EXPECTED_INGESTION_MODES), "allowed_ingestion_modes 與鎖定清單不符", failures)
assert((EXPECTED_INGESTION_MODES - target[:ingestion_mode]).empty?, "allowed_ingestion_modes 必須是 raw-evidence provenance.ingestion_mode enum 子集", failures)
assert(sorted_set(rep.fetch("transport_delivery_kinds", [])) == sorted_set(EXPECTED_TRANSPORT_KINDS), "transport_delivery_kinds 必須是 [WEBHOOK, POLL]", failures)

sap = spec.fetch("source_anchor_projection", {})
assert(sap["profile"] == "JIRA_CLOUD_ENTITY_SEGMENT_V1", "source_anchor_projection.profile 必須是 JIRA_CLOUD_ENTITY_SEGMENT_V1", failures)
assert(sap["profile"] == target[:jira_profile_const], "source_anchor_projection.profile 必須等於 Jira anchor profile schema 的 profile const", failures)
assert(sap["required_selector_type"] == "JSON_POINTER", "required_selector_type 必須是 JSON_POINTER", failures)
assert(sap["normalization_profile"] == "OMOS_TEXT_NORM_V1", "normalization_profile 必須是 OMOS_TEXT_NORM_V1", failures)
assert(
  sorted_set(sap.fetch("profile_details_shape", [])) == sorted_set(target[:jira_profile_details_shape]),
  "source_anchor_projection.profile_details_shape 必須剛好等於 Jira anchor profile schema 的 profile_details.required",
  failures
)
assert(sap.fetch("field_id_by_kind", {}) == EXPECTED_FIELD_ID_BY_KIND, "field_id_by_kind 與鎖定對映不符", failures)

reconciliation = spec.fetch("reconciliation", {})
assert(sorted_set(reconciliation.fetch("triggers", [])) == sorted_set(%w[WEBHOOK_GAP PERIODIC_SWEEP]), "reconciliation.triggers 必須是 [WEBHOOK_GAP, PERIODIC_SWEEP]", failures)

must_match = spec.dig("cross_reference", "must_match") || {}
{
  "source_version_basis_from" => "raw-evidence-envelope.properties.source_version.basis.enum",
  "source_version_kind_from" => "raw-evidence-envelope.properties.source_version.kind.enum",
  "ingestion_mode_from" => "raw-evidence-envelope.properties.provenance.ingestion_mode.enum",
  "jira_profile_const_from" => "source-anchor-jira-cloud-entity-segment-v1.profile.const",
  "jira_profile_details_shape_from" => "source-anchor-jira-cloud-entity-segment-v1.profile_details.required"
}.each do |pointer_key, expected_path|
  assert(must_match[pointer_key] == expected_path, "cross_reference.must_match.#{pointer_key} 必須是 #{expected_path}", failures)
end
assert(present?(target[:jira_profile_const]) && target[:jira_profile_const] == "JIRA_CLOUD_ENTITY_SEGMENT_V1", "Jira anchor profile schema 的 profile const 必須是 JIRA_CLOUD_ENTITY_SEGMENT_V1", failures)
assert(present?(target[:jira_profile_details_shape]) && target[:jira_profile_details_shape].include?("text_selector"), "Jira anchor profile_details.required 必須存在且含 text_selector", failures)

assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_JIRA_MAP_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定 label 清單不符",
  failures
)

positive = read_json(POSITIVE_FIXTURE_PATH)
negative = read_json(NEGATIVE_FIXTURE_PATH)

positive.fetch("jira_mapping_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} jira-map positive 必須預期 allow", failures)
  actual = jira_mapping_failure(test_case.fetch("projection"), target)
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

negative.fetch("jira_mapping_negative_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} jira-map negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = jira_mapping_failure(test_case.fetch("projection"), target)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

covered_labels = sorted_set(negative.fetch("jira_mapping_negative_cases").map { |test_case| test_case.fetch("covers_jira_map_negative_fixture") })
missing_labels = sorted_set(EXPECTED_JIRA_MAP_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "jira-map negative fixtures 未覆蓋：#{missing_labels.join(", ")}", failures)

if failures.empty?
  puts "PASS jira adapter mapping contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
