#!/usr/bin/env ruby

# repo #3 / Jira Adapter Mapping 契約 validator（mapping 語意層）。
# 薄判斷：結構斷言（mapping table 的值必須是 STD-01 + base SourceAnchor + Jira anchor profile
# schema 的合法欄位／enum／required）+ 純函式 `jira_mapping_failure(projection, target)`
# evaluator（含 compound version、reconciliation identity、field_kind -> field_id/json_pointer
# binding）。
#
# 投影出的 RawEvidenceEnvelope / Jira SourceAnchor 是否為 schema-valid instance，由 companion
# `scripts/validate_jira_adapter_mapping_instances.py` 以 JSON Schema engine 驗（instance_validation gate）。
#
# 沿用 scripts/lib/omos_contract_helpers.rb。

require "json"
require "yaml"
require "time"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/jira-adapter-mapping.yaml")
RAW_EVIDENCE_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/raw-evidence-envelope.schema.json")
BASE_ANCHOR_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/source-anchor.schema.json")
JIRA_PROFILE_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/source-anchor-jira-cloud-entity-segment-v1.schema.json")
INSTANCE_ENGINE_PATH = File.join(ROOT, "scripts/validate_jira_adapter_mapping_instances.py")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/jira-adapter-mapping-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/jira-adapter-mapping-negative-fixtures.json")
INSTANCE_NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/jira-adapter-mapping-instance-negative-fixtures.json")

EXPECTED_JIRA_FIELD_KINDS = %w[SUMMARY DESCRIPTION COMMENT_BODY ADF_TEXT_NODE].freeze
EXPECTED_INGESTION_MODES = %w[WEBHOOK POLL BULK_EXPORT].freeze
EXPECTED_TRANSPORT_KINDS = %w[WEBHOOK POLL].freeze
EXPECTED_FIELD_ID_BY_KIND = {
  "SUMMARY" => "summary", "DESCRIPTION" => "description",
  "COMMENT_BODY" => "comment", "ADF_TEXT_NODE" => "description"
}.freeze
# json_pointer 前綴（不帶尾斜線）；實際 pointer 必須 == prefix 或以 "prefix/" 開頭
# （純 start_with?(prefix) 會讓 /fields/description_extra 這種 prefix bypass 過關）。
EXPECTED_JSON_POINTER_PREFIX_BY_KIND = {
  "SUMMARY" => "/fields/summary", "DESCRIPTION" => "/fields/description",
  "COMMENT_BODY" => "/fields/comment/comments", "ADF_TEXT_NODE" => "/fields/description"
}.freeze
ISSUE_ID_PATTERN = /\A[0-9]+\z/.freeze
SHA256_PATTERN = /\Asha256:[0-9a-f]{64}\z/.freeze

# RFC3339 timestamp -> Time，parse 失敗回 nil。用真正 parse 比較，不用字串比較
# （字串比較下 "2026-09-05T12:00:00.1Z" < "2026-09-05T12:00:00Z"，fractional 秒會判錯）。
def parse_instant(value)
  return nil unless value.is_a?(String)

  Time.iso8601(value)
rescue ArgumentError
  nil
end

# pointer 是否真正定址到該 field：== prefix 或位於 prefix 之下。
def json_pointer_addresses_field?(pointer, prefix)
  pointer.is_a?(String) && (pointer == prefix || pointer.start_with?("#{prefix}/"))
end

# identity 需 cloud_id / issue_id 皆非空。
def identity_complete?(identity)
  identity.is_a?(Hash) && present?(identity["cloud_id"]) && present?(identity["issue_id"])
end

EXPECTED_JIRA_MAP_NEGATIVE_LABELS = [
  "a field kind outside SUMMARY / DESCRIPTION / COMMENT_BODY / ADF_TEXT_NODE",
  "a projected field is not a property of the target schema",
  "source identity uses a non-native basis",
  "the payload is inline content instead of a reference",
  "the source version is not compound-observed with a secondary digest",
  "the compound source version secondary digest is not a locked sha256",
  "the compound source version has no observed updated timestamp",
  "the source anchor profile is not the Jira cloud entity segment profile",
  "the JSON_POINTER selector is missing",
  "profile_details has the wrong key set",
  "the anchor field id does not match the field kind",
  "the anchor json pointer does not address the mapped field",
  "the anchor json pointer only shares a prefix with the mapped field",
  "reconciliation changes an existing evidence identity",
  "reconciliation omits the before or after evidence identity",
  "reconciliation before and after evidence identity differ",
  "the reconciliation current identity does not match the projected identity",
  "an issue key rename is not recorded as a source alias",
  "reconciliation version decision disagrees with the observed version order",
  "a fractional-second newer version is still ordered as newer",
  "reconciliation drops a detected gap without emitting evidence",
  "error but the mapping still claims success"
].freeze

EXPECTED_INSTANCE_NEGATIVE_LABELS = [
  "a projected RawEvidenceEnvelope is missing a locked required field",
  "a projected Jira SourceAnchor is missing a base SourceAnchor required field",
  "a projected Jira SourceAnchor text_selector has a wrong nested shape"
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

def identity_pair(node)
  return nil unless node.is_a?(Hash)

  { "cloud_id" => node["cloud_id"], "issue_id" => node["issue_id"] }
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
  return "JIRA_MAP_SECONDARY_DIGEST_MALFORMED" unless version["secondary_digest"].is_a?(String) &&
                                                     SHA256_PATTERN.match?(version["secondary_digest"])
  version_instant = parse_instant(version["value"])
  return "JIRA_MAP_VERSION_VALUE_INVALID" if version_instant.nil?

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

  return "JIRA_MAP_FIELD_ID_KIND_MISMATCH" unless details["field_id"] == EXPECTED_FIELD_ID_BY_KIND.fetch(kind)
  return "JIRA_MAP_JSON_POINTER_FIELD_MISMATCH" unless json_pointer_addresses_field?(
    details["json_pointer"], EXPECTED_JSON_POINTER_PREFIX_BY_KIND.fetch(kind)
  )

  # 當輪實際 projected identity（來自 anchor profile_details，不是 caller 自報的 flag）。
  projected_identity = { "cloud_id" => details["cloud_id"], "issue_id" => details["issue_id"] }

  reconciliation = projection["reconciliation"]
  if reconciliation.is_a?(Hash)
    return "JIRA_MAP_RECONCILIATION_CHANGES_IDENTITY" if reconciliation["changed_identity"] == true

    previous_identity = identity_pair(reconciliation["previous_identity"])
    current_identity = identity_pair(reconciliation["current_identity"])
    # identity 為 reconciliation 必填，且 cloud_id / issue_id 皆不得為空。
    unless identity_complete?(previous_identity) && identity_complete?(current_identity)
      return "JIRA_MAP_RECONCILIATION_IDENTITY_INCOMPLETE"
    end
    return "JIRA_MAP_RECONCILIATION_IDENTITY_DRIFT" unless previous_identity == current_identity
    # current_identity 必須等於當輪實際 projected identity。
    return "JIRA_MAP_RECONCILIATION_IDENTITY_DRIFT" unless current_identity == projected_identity

    key_change = reconciliation["issue_key_change"]
    if key_change.is_a?(Hash)
      alias_values = raw["source_aliases"].to_a.map { |entry| entry.is_a?(Hash) ? entry["value"] : entry }
      return "JIRA_MAP_ISSUE_KEY_RENAME_NOT_ALIASED" unless alias_values.include?(key_change["to"])
    end

    decision = reconciliation["decision"]
    if present?(decision)
      previous_instant = parse_instant(reconciliation.dig("previous_version", "value"))
      current_instant = parse_instant(reconciliation.dig("current_version", "value")) || version_instant
      if previous_instant && current_instant
        ordered_new = current_instant > previous_instant
        mismatch = (decision == "NEW_EVIDENCE" && !ordered_new) || (decision == "NOOP" && ordered_new)
        return "JIRA_MAP_RECONCILIATION_VERSION_DECISION_MISMATCH" if mismatch
      end
    end

    if reconciliation["detected_gap"] == true && reconciliation["emitted_evidence_or_gap"] != true
      return "JIRA_MAP_RECONCILIATION_SILENT_GAP"
    end
  end

  nil
end

# F-01 regression 修補：compact projection 與完整 STD instance 不得是兩套脫鉤測資。
# 逐項綁定 mapping-critical 欄位（identity / source_version / profile / field_id /
# json_pointer / payload / provenance），確保「schema-valid instance」確實是「依這份
# mapping 產生的」。
def projection_instance_consistency(test_case)
  problems = []
  projection = test_case.fetch("projection")
  raw_instance = test_case.fetch("raw_evidence_instance")
  anchor_instance = test_case.fetch("source_anchor_instance")
  proj_details = projection.dig("source_anchor", "profile_details") || {}
  inst_details = anchor_instance["profile_details"] || {}

  problems << "source_anchor.profile" unless projection.dig("source_anchor", "profile") == anchor_instance["profile"]
  %w[field_id json_pointer cloud_id issue_id].each do |key|
    problems << "profile_details.#{key}" unless proj_details[key] == inst_details[key]
  end

  proj_version = projection.dig("raw_evidence", "source_version") || {}
  inst_version = raw_instance["source_version"] || {}
  %w[basis kind value secondary_digest].each do |key|
    problems << "source_version.#{key}" unless proj_version[key] == inst_version[key]
  end

  proj_payload = projection.dig("raw_evidence", "payload") || {}
  inst_payload = raw_instance["payload"] || {}
  %w[structured_profile canonicalization_profile payload_ref].each do |key|
    problems << "payload.#{key}" unless proj_payload[key] == inst_payload[key]
  end

  problems << "provenance.ingestion_mode" unless projection.dig("raw_evidence", "provenance", "ingestion_mode") ==
                                                raw_instance.dig("provenance", "ingestion_mode")
  problems << "raw_evidence_instance.source_system" unless raw_instance.dig("source_identity", "source_system") == "jira-cloud"
  problems << "projected native_id_basis" unless projection.dig("raw_evidence", "source_identity", "native_id_basis") == "JIRA_CLOUD_ID_PLUS_ISSUE_ID"
  # Jira 的 evidence identity = (cloud_id, issue_id)；native_id 即 issue_id。
  problems << "raw_evidence_instance.native_id == issue_id" unless raw_instance.dig("source_identity", "native_id") == inst_details["issue_id"]
  problems << "source_anchor_instance.native_id == issue_id" unless anchor_instance.dig("source_identity", "native_id") == inst_details["issue_id"]

  reconciliation = projection["reconciliation"]
  if reconciliation.is_a?(Hash) && reconciliation["current_identity"].is_a?(Hash)
    current = reconciliation["current_identity"]
    unless current["cloud_id"] == inst_details["cloud_id"] && current["issue_id"] == inst_details["issue_id"]
      problems << "reconciliation.current_identity == instance identity"
    end
  end

  problems
end

failures = []
spec = read_yaml(SPEC_PATH)
raw_schema = read_json(RAW_EVIDENCE_SCHEMA_PATH)
base_anchor_schema = read_json(BASE_ANCHOR_SCHEMA_PATH)
jira_profile_schema = read_json(JIRA_PROFILE_SCHEMA_PATH)

jira_profile_body = jira_profile_schema.fetch("allOf").find { |part| part.is_a?(Hash) && part["type"] == "object" } || {}
target = {
  raw_evidence_props: raw_schema.fetch("properties").keys,
  raw_evidence_required: raw_schema.fetch("required").to_a,
  base_anchor_required: base_anchor_schema.fetch("required").to_a,
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
assert(rep.dig("source_identity", "identity_components") == %w[cloud_id issue_id], "source_identity.identity_components 必須是 [cloud_id, issue_id]", failures)
assert(rep.dig("source_version", "basis") == "COMPOUND_OBSERVED", "source_version.basis 必須是 COMPOUND_OBSERVED", failures)
assert(rep.dig("source_version", "kind") == "UPDATED_AT_DIGEST", "source_version.kind 必須是 UPDATED_AT_DIGEST", failures)
assert(rep.dig("source_version", "value_format") == "RFC3339_TIMESTAMP", "source_version.value_format 必須是 RFC3339_TIMESTAMP", failures)
assert(rep.dig("source_version", "secondary_digest_format") == "SHA256_LOWER_HEX_64", "source_version.secondary_digest_format 必須是 SHA256_LOWER_HEX_64", failures)
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
assert(sap.fetch("json_pointer_prefix_by_kind", {}) == EXPECTED_JSON_POINTER_PREFIX_BY_KIND, "json_pointer_prefix_by_kind 與鎖定對映不符", failures)

reconciliation = spec.fetch("reconciliation", {})
assert(sorted_set(reconciliation.fetch("triggers", [])) == sorted_set(%w[WEBHOOK_GAP PERIODIC_SWEEP]), "reconciliation.triggers 必須是 [WEBHOOK_GAP, PERIODIC_SWEEP]", failures)
assert(reconciliation.fetch("identity_components", []) == %w[cloud_id issue_id], "reconciliation.identity_components 必須是 [cloud_id, issue_id]", failures)
assert(sorted_set(reconciliation.fetch("version_decisions", [])) == sorted_set(%w[NEW_EVIDENCE NOOP]), "reconciliation.version_decisions 必須是 [NEW_EVIDENCE, NOOP]", failures)

assert(spec.dig("instance_validation", "engine") == "scripts/validate_jira_adapter_mapping_instances.py", "instance_validation.engine 必須指向 companion", failures)
assert(File.exist?(INSTANCE_ENGINE_PATH), "companion JSON Schema engine 檔案必須存在", failures)

must_match = spec.dig("cross_reference", "must_match") || {}
{
  "source_version_basis_from" => "raw-evidence-envelope.properties.source_version.basis.enum",
  "source_version_kind_from" => "raw-evidence-envelope.properties.source_version.kind.enum",
  "ingestion_mode_from" => "raw-evidence-envelope.properties.provenance.ingestion_mode.enum",
  "raw_evidence_required_from" => "raw-evidence-envelope.required",
  "base_source_anchor_required_from" => "source-anchor.required",
  "jira_profile_const_from" => "source-anchor-jira-cloud-entity-segment-v1.profile.const",
  "jira_profile_details_shape_from" => "source-anchor-jira-cloud-entity-segment-v1.profile_details.required"
}.each do |pointer_key, expected_path|
  assert(must_match[pointer_key] == expected_path, "cross_reference.must_match.#{pointer_key} 必須是 #{expected_path}", failures)
end
assert(present?(target[:jira_profile_const]) && target[:jira_profile_const] == "JIRA_CLOUD_ENTITY_SEGMENT_V1", "Jira anchor profile schema 的 profile const 必須是 JIRA_CLOUD_ENTITY_SEGMENT_V1", failures)
assert(present?(target[:jira_profile_details_shape]) && target[:jira_profile_details_shape].include?("text_selector"), "Jira anchor profile_details.required 必須存在且含 text_selector", failures)
assert(target[:raw_evidence_required].include?("idempotency_basis"), "raw-evidence required 必須含 idempotency_basis（cross_reference 綁定檢查）", failures)
assert(target[:base_anchor_required].include?("quote"), "base source-anchor required 必須含 quote（cross_reference 綁定檢查）", failures)

assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_JIRA_MAP_NEGATIVE_LABELS),
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

positive.fetch("jira_mapping_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "allow", "#{case_id} jira-map positive 必須預期 allow", failures)
  actual = jira_mapping_failure(test_case.fetch("projection"), target)
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
  assert(test_case.key?("raw_evidence_instance"), "#{case_id} 必須帶完整 raw_evidence_instance（instance gate 用）", failures)
  assert(test_case.key?("source_anchor_instance"), "#{case_id} 必須帶完整 source_anchor_instance（instance gate 用）", failures)
  mismatches = projection_instance_consistency(test_case)
  assert(mismatches.empty?, "#{case_id} projection 與完整 STD instance 不一致：#{mismatches.join(", ")}", failures)
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

covered_instance_labels = sorted_set(instance_negative.fetch("instance_negative_cases").map { |test_case| test_case.fetch("covers") })
missing_instance_labels = sorted_set(EXPECTED_INSTANCE_NEGATIVE_LABELS) - covered_instance_labels
assert(missing_instance_labels.empty?, "instance negative fixtures 未覆蓋：#{missing_instance_labels.join(", ")}", failures)

if failures.empty?
  puts "PASS jira adapter mapping contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
