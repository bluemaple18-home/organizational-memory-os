#!/usr/bin/env ruby

require "json"
require "time"
require "yaml"

ROOT = File.expand_path("..", __dir__)
COMMON_VOCAB_PATH = File.join(ROOT, "規格/v0.1/common-vocabulary.yaml")
SCHEMA_PATH = File.join(ROOT, "規格/v0.1/raw-evidence-envelope.schema.json")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/std-01-raw-evidence-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/std-01-raw-evidence-negative-fixtures.json")

UUIDV7_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/.freeze
SHA256_PATTERN = /\Asha256:[0-9a-f]{64}\z/.freeze
EXPECTED_POSITIVE_NAMES = %w[
  pdf-manual-upload-raw-evidence
  git-markdown-sop-raw-evidence
  jira-cloud-issue-description-raw-evidence
].freeze
EXPECTED_NEGATIVE_NAMES = %w[
  evidence-id-equals-delivery-id
  same-cloudevent-redelivery-creates-second-evidence
  redelivery-payload-mismatch-without-finding
  same-source-new-revision-reuses-evidence-id
  same-source-new-revision-reuses-idempotency-key
  same-payload-different-sources-merged
  source-event-without-native-event-id-missing-fallback
  four-clocks-collapsed-or-reordered
  single-jira-404-marked-source-deleted
  permission-revoked-classified-as-deleted
  project-deletion-webhook-only-confirmation
  non-i-json-canonical-digest-claimed
  missing-raw-digest
  missing-acl-snapshot
  missing-provenance
  openlineage-complete-treated-as-verified
  entity-snapshot-idempotency-missing-source-version
  source-event-idempotency-missing-native-event-id
  canonicalization-none-with-canonical-digest
  jcs-with-non-i-json-profile
  unknown-quality-gap-code
].freeze

def assert(condition, code, message, failures)
  failures << "#{code}: #{message}" unless condition
end

def read_json(path, failures)
  unless File.exist?(path)
    failures << "MISSING_FILE: #{relative_path(path)}"
    return nil
  end

  JSON.parse(File.read(path))
rescue JSON::ParserError => error
  failures << "JSON_PARSE: #{path} #{error.message}"
  nil
end

def read_yaml(path, failures)
  unless File.exist?(path)
    failures << "MISSING_FILE: #{relative_path(path)}"
    return nil
  end

  YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
rescue Psych::SyntaxError => error
  failures << "YAML_PARSE: #{path} #{error.message}"
  nil
end

def relative_path(path)
  path.sub("#{ROOT}/", "")
end

def present?(value)
  !value.nil? && !(value.respond_to?(:empty?) && value.empty?)
end

def path_value(payload, path)
  path.split(".").reduce(payload) do |cursor, key|
    return nil unless cursor.is_a?(Hash)

    cursor[key]
  end
end

def valid_rfc3339?(value)
  return false unless value.is_a?(String)

  Time.iso8601(value)
  value.end_with?("Z")
rescue ArgumentError
  false
end

def parse_time(value)
  return nil unless valid_rfc3339?(value)

  Time.iso8601(value)
end

def array_intersects?(values, expected)
  values.to_a.any? { |value| expected.include?(value) }
end

def validate_schema_document(schema, failures)
  return if schema.nil?

  required = %w[
    schema_version
    evidence_id
    evidence_ref
    tenant_id
    source_identity
    source_version
    chronology
    digests
    payload
    access
    provenance
    source_availability
    payload_retention_state
  ]

  assert(schema["$schema"] == "https://json-schema.org/draft/2020-12/schema", "SCHEMA_DIALECT", "schema 必須宣告 JSON Schema 2020-12", failures)
  assert(schema["title"] == "RawEvidenceEnvelope v0.1", "SCHEMA_TITLE", "schema title 必須是 RawEvidenceEnvelope v0.1", failures)
  assert(schema["type"] == "object", "SCHEMA_TYPE", "schema root 必須是 object", failures)
  required.each do |field|
    assert(schema.fetch("required", []).include?(field), "SCHEMA_REQUIRED", "schema required 必須包含 #{field}", failures)
  end

  assert(schema["additionalProperties"] == false, "SCHEMA_ROOT_CLOSED", "schema root 必須 additionalProperties=false", failures)
  %w[source_identity source_version chronology digests payload access provenance quality_gaps].each do |field|
    property = schema.dig("properties", field)
    assert(property.is_a?(Hash), "SCHEMA_PROPERTY", "schema properties 必須包含 #{field}", failures)
  end
  %w[source_identity source_version chronology digests payload access provenance].each do |field|
    assert(schema.dig("properties", field, "additionalProperties") == false, "SCHEMA_NESTED_CLOSED", "#{field} 必須 additionalProperties=false", failures)
  end
  {
    "source_identity" => %w[source_system source_instance_id entity_type native_id],
    "source_version" => %w[basis kind value secondary_digest],
    "chronology" => %w[occurred_at occurred_at_basis observed_at received_at persisted_at],
    "digests" => %w[raw_digest canonical_digest],
    "payload" => %w[media_type payload_ref size_bytes structured_profile canonicalization_profile retention_tier],
    "access" => %w[acl_snapshot_ref permission_basis visibility_scope_refs],
    "provenance" => %w[adapter_id adapter_version ingestion_mode source_observation_receipt_ref]
  }.each do |field, expected_required|
    actual_required = schema.dig("properties", field, "required").to_a
    assert((expected_required - actual_required).empty?, "SCHEMA_NESTED_REQUIRED", "#{field}.required 缺 #{(expected_required - actual_required).join(', ')}", failures)
  end
  assert(schema.dig("properties", "evidence_ref", "pattern").to_s.start_with?("^urn:omos:evidence:"), "SCHEMA_EVIDENCE_REF_PATTERN", "evidence_ref 必須有 URN pattern", failures)
  assert(schema.dig("properties", "quality_gaps", "items", "properties", "code", "enum").is_a?(Array), "SCHEMA_GAP_ENUM", "quality_gaps.code 必須綁定 LOCKED enum", failures)
  assert(schema.dig("$defs", "idempotency_basis", "properties", "includes", "uniqueItems") == true, "SCHEMA_IDEMPOTENCY_UNIQUE", "idempotency includes 必須 uniqueItems", failures)

  idempotency_conditions = schema.dig("$defs", "idempotency_basis", "allOf")
  assert(idempotency_conditions.is_a?(Array) && idempotency_conditions.length == 2, "SCHEMA_IDEMPOTENCY_CONDITIONS", "idempotency profile 必須有兩個 conditional branches", failures)
  root_conditions = schema["allOf"]
  assert(root_conditions.is_a?(Array) && root_conditions.length >= 4, "SCHEMA_ROOT_CONDITIONS", "schema 必須封住 canonicalization 與 event identity conditional semantics", failures)
  none_branch = root_conditions.to_a.find { |branch| branch.dig("if", "properties", "payload", "properties", "canonicalization_profile", "const") == "NONE" }
  jcs_branch = root_conditions.to_a.find { |branch| branch.dig("if", "properties", "payload", "properties", "canonicalization_profile", "const") == "RFC8785_JCS" }
  fallback_branch = root_conditions.to_a.find { |branch| branch.dig("then", "properties", "source_event", "properties", "identity_basis", "const") == "FALLBACK_DERIVED" }
  native_branch = root_conditions.to_a.find { |branch| branch.dig("then", "properties", "source_event", "properties", "identity_basis", "const") == "NATIVE" }
  assert(none_branch&.dig("then", "properties", "digests", "properties", "canonical_digest", "type") == "null", "SCHEMA_NONE_CANONICAL_NULL", "NONE conditional 必須令 canonical_digest 為 null", failures)
  assert(jcs_branch&.dig("then", "properties", "payload", "properties", "structured_profile", "const") == "I_JSON", "SCHEMA_JCS_I_JSON", "JCS conditional 必須要求 I_JSON", failures)
  assert(jcs_branch&.dig("then", "properties", "digests", "properties", "canonical_digest", "$ref") == "#/$defs/sha256", "SCHEMA_JCS_DIGEST", "JCS conditional 必須要求 canonical digest", failures)
  assert(fallback_branch && JSON.generate(fallback_branch).include?("raw_digest"), "SCHEMA_EVENT_FALLBACK", "fallback event conditional 必須有 deterministic raw digest basis", failures)
  assert(native_branch && JSON.generate(native_branch).include?("native_event_id"), "SCHEMA_EVENT_NATIVE", "native event conditional 必須包含 native_event_id", failures)
end

def validate_envelope(common_vocab, envelope)
  failures = []
  source_version_basis = common_vocab.dig("source_version", "basis").to_a
  source_version_kind = common_vocab.dig("source_version", "kind").to_a
  alias_kinds = common_vocab.dig("identifiers", "alias_kinds").to_a
  source_availability = common_vocab.dig("common_enums", "source_availability").to_a
  payload_retention = common_vocab.dig("common_enums", "payload_retention_state").to_a
  activity_status = common_vocab.dig("common_enums", "activity_status").to_a
  verification_status = common_vocab.dig("common_enums", "verification_status").to_a

  assert(envelope["schema_version"] == "omos.evidence.raw.v0.1", "SCHEMA_VERSION", "schema_version 必須是 omos.evidence.raw.v0.1", failures)
  assert(envelope["evidence_id"].is_a?(String) && envelope["evidence_id"].match?(UUIDV7_PATTERN), "EVIDENCE_ID", "evidence_id 必須是 bare UUIDv7", failures)
  assert(envelope["evidence_ref"] == "urn:omos:evidence:#{envelope["evidence_id"]}", "EVIDENCE_REF", "evidence_ref 必須由 evidence_id 組成", failures)
  assert(envelope["tenant_id"].is_a?(String) && envelope["tenant_id"].match?(UUIDV7_PATTERN), "TENANT_ID", "tenant_id 必須是 UUIDv7", failures)

  delivery_ids = [
    path_value(envelope, "transport_delivery.id"),
    path_value(envelope, "source_event.delivery_id"),
    path_value(envelope, "source_event.native_event_id")
  ].compact
  assert(!delivery_ids.include?(envelope["evidence_id"]), "EVIDENCE_ID_DELIVERY_ID", "evidence_id 不得等於 delivery 或 source event id", failures)

  source_identity = envelope["source_identity"]
  assert(source_identity.is_a?(Hash), "SOURCE_IDENTITY", "source_identity 必須存在", failures)
  %w[source_system source_instance_id entity_type native_id].each do |field|
    assert(present?(source_identity && source_identity[field]), "SOURCE_IDENTITY_FIELD", "source_identity.#{field} 必填", failures)
  end

  envelope.fetch("source_aliases", []).each do |alias_record|
    assert(alias_record.is_a?(Hash) && alias_kinds.include?(alias_record["kind"]), "ALIAS_KIND", "source_aliases.kind 必須使用 STD-00 alias kind", failures)
    assert(present?(alias_record["value"]), "ALIAS_VALUE", "source_aliases.value 必填", failures)
  end

  source_version = envelope["source_version"]
  assert(source_version.is_a?(Hash), "SOURCE_VERSION", "source_version 必須存在", failures)
  assert(source_version_basis.include?(source_version && source_version["basis"]), "SOURCE_VERSION_BASIS", "source_version.basis 不合法", failures)
  assert(source_version_kind.include?(source_version && source_version["kind"]), "SOURCE_VERSION_KIND", "source_version.kind 不合法", failures)
  if source_version && source_version["basis"] == "UNKNOWN"
    assert(source_version["kind"] == "NONE", "SOURCE_VERSION_UNKNOWN_KIND", "source_version UNKNOWN 時 kind 必須是 NONE", failures)
    assert(source_version["value"].nil?, "SOURCE_VERSION_UNKNOWN_VALUE", "source_version UNKNOWN 時 value 必須是 null", failures)
  else
    assert(present?(source_version && source_version["value"]), "SOURCE_VERSION_VALUE", "source_version.value 必填", failures)
  end
  secondary_digest = source_version && source_version["secondary_digest"]
  assert(secondary_digest.nil? || secondary_digest.match?(SHA256_PATTERN), "SOURCE_VERSION_SECONDARY_DIGEST", "source_version.secondary_digest 必須是 sha256 或 null", failures)

  chronology = envelope["chronology"]
  assert(chronology.is_a?(Hash), "CHRONOLOGY", "chronology 必須存在", failures)
  %w[observed_at received_at persisted_at].each do |field|
    assert(valid_rfc3339?(chronology && chronology[field]), "CHRONOLOGY_TIMESTAMP", "chronology.#{field} 必須是 UTC RFC3339", failures)
  end
  occurred_at = chronology && chronology["occurred_at"]
  assert(occurred_at.nil? || valid_rfc3339?(occurred_at), "CHRONOLOGY_OCCURRED_AT", "chronology.occurred_at 必須是 null 或 UTC RFC3339", failures)
  assert(common_vocab.dig("chronology", "occurred_at_basis").to_a.include?(chronology && chronology["occurred_at_basis"]), "CHRONOLOGY_BASIS", "occurred_at_basis 不合法", failures)
  assert(occurred_at.nil? == ((chronology && chronology["occurred_at_basis"]) == "UNKNOWN"), "CHRONOLOGY_BASIS_MATCH", "occurred_at null 必須搭配 UNKNOWN，非 null 不得是 UNKNOWN", failures)

  observed_at = parse_time(chronology && chronology["observed_at"])
  received_at = parse_time(chronology && chronology["received_at"])
  persisted_at = parse_time(chronology && chronology["persisted_at"])
  if observed_at && received_at && persisted_at
    assert(observed_at <= received_at && received_at <= persisted_at, "FOUR_CLOCK_ORDER", "observed_at <= received_at <= persisted_at 必須成立", failures)
    assert([occurred_at, chronology["observed_at"], chronology["received_at"], chronology["persisted_at"]].compact.uniq.length > 1, "FOUR_CLOCKS_COLLAPSED", "four clocks 不得全部相等", failures)
  end

  digests = envelope["digests"]
  assert(digests.is_a?(Hash), "DIGESTS", "digests 必須存在", failures)
  assert(digests && digests["raw_digest"].is_a?(String) && digests["raw_digest"].match?(SHA256_PATTERN), "RAW_DIGEST", "raw_digest 必填且必須是 sha256", failures)
  canonical_digest = digests && digests["canonical_digest"]
  assert(canonical_digest.nil? || canonical_digest.match?(SHA256_PATTERN), "CANONICAL_DIGEST", "canonical_digest 必須是 sha256 或 null", failures)

  quality_gap_codes = envelope.fetch("quality_gaps", []).map { |gap| gap.is_a?(Hash) ? gap["code"] : gap }
  canonicalization_profile = path_value(envelope, "payload.canonicalization_profile")
  structured_profile = path_value(envelope, "payload.structured_profile")
  if structured_profile == "NON_I_JSON"
    assert(canonical_digest.nil?, "NON_I_JSON_CANONICAL_DIGEST", "NON_I_JSON payload 不得宣稱 canonical_digest", failures)
    assert(quality_gap_codes.include?("CANONICALIZATION_UNAVAILABLE"), "NON_I_JSON_GAP", "NON_I_JSON payload 必須留下 CANONICALIZATION_UNAVAILABLE", failures)
  end
  if canonicalization_profile == "NONE"
    assert(canonical_digest.nil?, "CANONICALIZATION_NONE_DIGEST", "canonicalization_profile NONE 時 canonical_digest 必須是 null", failures)
  elsif canonicalization_profile == "RFC8785_JCS"
    assert(structured_profile == "I_JSON", "JCS_REQUIRES_I_JSON", "RFC8785_JCS 必須搭配 I_JSON", failures)
    assert(canonical_digest.is_a?(String), "JCS_CANONICAL_DIGEST", "RFC8785_JCS payload 必須有 canonical_digest", failures)
  end

  payload = envelope["payload"]
  assert(payload.is_a?(Hash), "PAYLOAD", "payload 必須存在", failures)
  assert(present?(payload && payload["payload_ref"]), "PAYLOAD_REF", "payload.payload_ref 必填", failures)
  assert(present?(payload && payload["media_type"]), "PAYLOAD_MEDIA_TYPE", "payload.media_type 必填", failures)
  assert((payload && payload["size_bytes"]).is_a?(Integer) && payload["size_bytes"] >= 0, "PAYLOAD_SIZE", "payload.size_bytes 必須是非負整數", failures)
  assert(payload_retention.include?(envelope["payload_retention_state"]), "PAYLOAD_RETENTION", "payload_retention_state 不合法", failures)

  access = envelope["access"]
  assert(access.is_a?(Hash), "ACCESS", "access 必須存在", failures)
  assert((access && access["acl_snapshot_ref"]).is_a?(String) && access["acl_snapshot_ref"].start_with?("urn:omos:acl-snapshot:"), "ACL_SNAPSHOT", "access.acl_snapshot_ref 必須存在", failures)

  provenance = envelope["provenance"]
  assert(provenance.is_a?(Hash), "PROVENANCE", "provenance 必須存在", failures)
  %w[adapter_id adapter_version ingestion_mode source_observation_receipt_ref].each do |field|
    assert(present?(provenance && provenance[field]), "PROVENANCE_FIELD", "provenance.#{field} 必填", failures)
  end
  provenance_status = provenance && provenance["lineage_activity_status"]
  assert(provenance_status.nil? || activity_status.include?(provenance_status), "ACTIVITY_STATUS", "lineage_activity_status 不合法", failures)
  verification_status_value = provenance && provenance["verification_status"]
  assert(verification_status_value.nil? || verification_status.include?(verification_status_value), "VERIFICATION_STATUS", "verification_status 不合法", failures)
  if provenance && provenance["verification_inferred_from_activity"] == true
    assert(false, "COMPLETE_NE_VERIFIED", "activity COMPLETE 不得推導 verification PASS", failures)
  end

  assert(source_availability.include?(envelope["source_availability"]), "SOURCE_AVAILABILITY", "source_availability 不合法", failures)
  if envelope["source_availability"] == "SOURCE_DELETED"
    confirmation_ref = envelope["deletion_confirmation_ref"]
    assert(present?(confirmation_ref), "SOURCE_DELETED_CONFIRMATION", "SOURCE_DELETED 必須有 deletion_confirmation_ref", failures)
    assert(!confirmation_ref.to_s.include?("webhook-only"), "SOURCE_DELETED_WEBHOOK_ONLY", "SOURCE_DELETED 不得只靠 webhook-only confirmation", failures)
  end
  if envelope["source_availability"] == "ACCESS_REVOKED"
    assert(present?(envelope["permission_decision_ref"]), "ACCESS_REVOKED_PERMISSION", "ACCESS_REVOKED 必須有 permission_decision_ref", failures)
  end

  source_event = envelope["source_event"]
  if source_event
    assert(present?(source_event["event_type"]), "SOURCE_EVENT_TYPE", "source_event.event_type 必填", failures)
    event_basis = source_event["idempotency_basis"]
    assert(event_basis.is_a?(Hash) && event_basis["profile"] == "OMOS_SOURCE_EVENT_IDEMPOTENCY_V1", "SOURCE_EVENT_IDEMPOTENCY_PROFILE", "source_event 必須使用 OMOS_SOURCE_EVENT_IDEMPOTENCY_V1", failures)
    event_includes = event_basis.is_a?(Hash) ? event_basis.fetch("includes", []) : []
    event_excludes = event_basis.is_a?(Hash) ? event_basis.fetch("excludes", []) : []
    assert(event_includes.is_a?(Array) && event_includes.uniq == event_includes, "SOURCE_EVENT_INCLUDES_UNIQUE", "source_event idempotency includes 必須為無重複 array", failures)
    assert(event_excludes.is_a?(Array), "SOURCE_EVENT_EXCLUDES_TYPE", "source_event idempotency excludes 必須為 array", failures)
    assert((event_includes.to_a & %w[transport_delivery.id received_at persisted_at ingestion_mode]).empty?, "SOURCE_EVENT_FORBIDDEN_INCLUDE", "source_event idempotency 不得含 delivery 或 ingestion clocks", failures)
    if source_event["native_event_id"].nil?
      assert(source_event["identity_basis"] == "FALLBACK_DERIVED", "SOURCE_EVENT_FALLBACK", "缺 native_event_id 時必須使用 FALLBACK_DERIVED", failures)
      includes = source_event.dig("idempotency_basis", "includes").to_a
      assert(%w[tenant_id stable_source_identity event_type occurred_at raw_digest].all? { |field| includes.include?(field) }, "SOURCE_EVENT_FALLBACK_BASIS", "fallback idempotency basis 必須包含 tenant_id、stable source identity、event_type、occurred_at、raw_digest", failures)
      assert(quality_gap_codes.include?("IDENTITY_FALLBACK_DERIVED"), "SOURCE_EVENT_FALLBACK_GAP", "fallback event identity 必須留下 IDENTITY_FALLBACK_DERIVED", failures)
    else
      assert(source_event["identity_basis"] == "NATIVE", "SOURCE_EVENT_NATIVE_IDENTITY", "有 native_event_id 時 identity_basis 必須是 NATIVE", failures)
      includes = source_event.dig("idempotency_basis", "includes").to_a
      assert(%w[tenant_id stable_source_identity event_type native_event_id].all? { |field| includes.include?(field) }, "SOURCE_EVENT_NATIVE_BASIS", "native event idempotency basis 必須包含 tenant_id、stable_source_identity、event_type、native_event_id", failures)
    end
  end

  idempotency_basis = envelope["idempotency_basis"]
  assert(idempotency_basis.is_a?(Hash), "IDEMPOTENCY_BASIS", "idempotency_basis 必須存在", failures)
  assert(present?(envelope["idempotency_key"]), "IDEMPOTENCY_KEY", "idempotency_key 必須存在", failures)
  excludes = idempotency_basis ? idempotency_basis.fetch("excludes", []) : []
  assert(!array_intersects?(excludes, []), "IDEMPOTENCY_EXCLUDES_TYPE", "idempotency_basis.excludes 必須是 array", failures) unless excludes.is_a?(Array)
  forbidden_includes = %w[transport_delivery.id received_at persisted_at ingestion_mode]
  includes = idempotency_basis ? idempotency_basis.fetch("includes", []) : []
  assert((includes & forbidden_includes).empty?, "IDEMPOTENCY_FORBIDDEN_INCLUDE", "idempotency basis 不得包含 delivery id、received_at、persisted_at 或 ingestion_mode", failures)
  profile = idempotency_basis && idempotency_basis["profile"]
  required_includes = case profile
                      when "OMOS_ENTITY_SNAPSHOT_IDEMPOTENCY_V1"
                        %w[tenant_id stable_source_identity source_version]
                      when "OMOS_SOURCE_EVENT_IDEMPOTENCY_V1"
                        if source_event && source_event["native_event_id"].nil?
                          %w[tenant_id stable_source_identity event_type occurred_at raw_digest]
                        else
                          %w[tenant_id stable_source_identity event_type native_event_id]
                        end
                      else
                        []
                      end
  assert(!required_includes.empty?, "IDEMPOTENCY_PROFILE", "idempotency_basis.profile 不合法", failures)
  assert(required_includes.all? { |field| includes.include?(field) }, "IDEMPOTENCY_PROFILE_INCLUDES", "#{profile} includes 缺必要 identity components", failures) unless required_includes.empty?
  assert(includes.uniq == includes, "IDEMPOTENCY_INCLUDES_UNIQUE", "idempotency_basis.includes 不得重複", failures)

  locked_gap_codes = common_vocab.dig("common_enums", "quality_gap_code").to_a
  quality_gap_codes.each do |code|
    assert(locked_gap_codes.include?(code), "QUALITY_GAP_CODE", "quality gap #{code} 不在 LOCKED vocabulary", failures)
  end

  failures
end

def source_identity_key(envelope)
  source_identity = envelope["source_identity"] || {}
  %w[tenant_id source_system source_instance_id entity_type native_id].map do |field|
    field == "tenant_id" ? envelope["tenant_id"] : source_identity[field]
  end.join("|")
end

def source_version_key(envelope)
  version = envelope["source_version"] || {}
  [version["basis"], version["kind"], version["value"], version["secondary_digest"]].join("|")
end

def transport_key(envelope)
  delivery = envelope["transport_delivery"] || {}
  return nil unless present?(delivery["source"]) && present?(delivery["id"])

  [delivery["source"], delivery["id"]].join("|")
end

def validate_cross_event_semantics(envelopes)
  failures = []

  envelopes.combination(2) do |left, right|
    same_transport = transport_key(left) && transport_key(left) == transport_key(right)
    same_raw_digest = path_value(left, "digests.raw_digest") == path_value(right, "digests.raw_digest")
    same_source = source_identity_key(left) == source_identity_key(right)
    same_version = source_version_key(left) == source_version_key(right)
    same_evidence_id = left["evidence_id"] == right["evidence_id"]
    same_idempotency_key = left["idempotency_key"] == right["idempotency_key"]

    if same_transport && same_raw_digest
      assert(same_evidence_id && same_idempotency_key, "REDELIVERY_DUPLICATE_EVIDENCE", "同一 CloudEvent redelivery 同 raw digest 不得建立第二筆 Evidence", failures)
    end

    if same_transport && !same_raw_digest
      combined_gaps = left.fetch("quality_gaps", []) + right.fetch("quality_gaps", [])
      codes = combined_gaps.map { |gap| gap.is_a?(Hash) ? gap["code"] : gap }
      assert(codes.include?("REDELIVERY_PAYLOAD_MISMATCH"), "REDELIVERY_PAYLOAD_MISMATCH_UNFLAGGED", "同一 delivery 不同 raw digest 必須標記 REDELIVERY_PAYLOAD_MISMATCH", failures)
    end

    if same_source && !same_version && same_evidence_id
      assert(false, "REVISION_REUSED_EVIDENCE_ID", "同一 source identity 的新 version 必須產生新 Evidence", failures)
    end

    if same_source && !same_version && same_idempotency_key
      assert(false, "REVISION_REUSED_IDEMPOTENCY_KEY", "同一 stable source identity 的新 version 必須使用新 idempotency_key", failures)
    end

    if !same_source && same_raw_digest
      assert(!same_evidence_id && !same_idempotency_key, "CROSS_SOURCE_DIGEST_MERGE", "相同 payload bytes 不得合併不同 source identity", failures)
    end
  end

  failures
end

def validate_positive_fixtures(common_vocab, payload, failures)
  return if payload.nil?

  assert(payload["fixture_set"] == "std-01-raw-evidence-positive-v0.1", "POSITIVE_FIXTURE_SET", "positive fixture_set 不正確", failures)
  names = payload.fetch("fixtures", []).map { |fixture| fixture["name"] }
  assert(names == EXPECTED_POSITIVE_NAMES, "POSITIVE_FIXTURE_NAMES", "positive fixtures 必須精確覆蓋 PDF／Markdown／Jira", failures)

  payload.fetch("fixtures", []).each do |fixture|
    envelope = fixture["envelope"]
    assert(envelope.is_a?(Hash), "POSITIVE_ENVELOPE", "#{fixture["name"]} 必須有 envelope", failures)
    next unless envelope.is_a?(Hash)

    validate_envelope(common_vocab, envelope).each do |failure|
      failures << "#{fixture["name"]}: #{failure}"
    end
  end
end

def changed_paths(left, right, prefix = "")
  if left.is_a?(Hash) && right.is_a?(Hash)
    (left.keys | right.keys).flat_map do |key|
      changed_paths(left[key], right[key], [prefix, key].reject(&:empty?).join("."))
    end
  elsif left == right
    []
  else
    [prefix]
  end
end

def validate_negative_fixtures(common_vocab, positive_payload, payload, failures)
  return if payload.nil?

  assert(payload["fixture_set"] == "std-01-raw-evidence-negative-v0.1", "NEGATIVE_FIXTURE_SET", "negative fixture_set 不正確", failures)
  names = payload.fetch("cases", []).map { |test_case| test_case["name"] }
  assert(names == EXPECTED_NEGATIVE_NAMES, "NEGATIVE_FIXTURE_NAMES", "negative fixtures 必須精確覆蓋 STD-01 required cases", failures)

  payload.fetch("cases", []).each do |test_case|
    authority = test_case["validation_authority"]
    assert(%w[JSON_SCHEMA RUBY_SEMANTIC].include?(authority), "NEGATIVE_AUTHORITY", "#{test_case["name"]} 必須明示 validation_authority", failures)
    assert(test_case["expected_result"] == "REJECT", "NEGATIVE_EXPECTED_RESULT", "#{test_case["name"]} 必須明示 expected_result=REJECT", failures)
    validation_failures = []
    if test_case["invalid_envelope"]
      base = positive_payload.fetch("fixtures", []).find { |fixture| fixture["name"] == test_case["base_fixture"] }
      assert(base, "NEGATIVE_BASE", "#{test_case["name"]} 缺有效 base_fixture", failures)
      assert(test_case["invalid_envelope"].keys.sort == base["envelope"].keys.sort, "NEGATIVE_COMPLETE_ENVELOPE", "#{test_case["name"]} 必須是完整 envelope", failures) if base
      allowed_paths = test_case.fetch("allowed_mutation_paths", [])
      actual_paths = base ? changed_paths(base["envelope"], test_case["invalid_envelope"]) : []
      assert(actual_paths.all? { |path| allowed_paths.include?(path) }, "NEGATIVE_MINIMAL_MUTATION", "#{test_case["name"]} 有未宣告 mutation: #{(actual_paths - allowed_paths).join(', ')}", failures)
      validation_failures.concat(validate_envelope(common_vocab, test_case["invalid_envelope"]))
    end
    if test_case["scenario"]
      envelopes = test_case.dig("scenario", "envelopes").to_a
      expected_indexes = (0...envelopes.length).to_a
      actual_indexes = test_case.fetch("instance_expectations", []).map { |item| item["instance_index"] }
      assert(actual_indexes == expected_indexes, "SCENARIO_INSTANCE_EXPECTATIONS", "#{test_case["name"]} 必須逐 instance 明示索引", failures)
      assert(test_case.fetch("instance_expectations", []).all? { |item| item["expected_result"] == "ALLOW" }, "SCENARIO_INSTANCE_EXPECTED_RESULT", "#{test_case["name"]} instance 必須明示 expected_result=ALLOW", failures)
      positive_keys = positive_payload.fetch("fixtures", []).first.fetch("envelope").keys.sort
      envelopes.each do |envelope|
        assert(envelope.keys.sort == positive_keys, "NEGATIVE_COMPLETE_SCENARIO_ENVELOPE", "#{test_case["name"]} scenario 必須使用完整 envelope", failures)
      end
      envelopes.each { |envelope| validation_failures.concat(validate_envelope(common_vocab, envelope)) }
      validation_failures.concat(validate_cross_event_semantics(envelopes))
    end

    if authority == "RUBY_SEMANTIC"
      codes = validation_failures.map { |failure| failure.split(":").first }
      expected_codes = test_case.fetch("expected_failure_codes")
      expected_codes.each do |expected_code|
        assert(codes.include?(expected_code), "NEGATIVE_EXPECTED_FAILURE", "#{test_case["name"]} 未觸發 #{expected_code}", failures)
      end
      unexpected_codes = codes.uniq - expected_codes
      assert(unexpected_codes.empty?, "NEGATIVE_UNRELATED_FAILURE", "#{test_case["name"]} 另觸發 unrelated failures: #{unexpected_codes.join(', ')}", failures)
    end
  end
end

def main
  failures = []
  common_vocab = read_yaml(COMMON_VOCAB_PATH, failures)
  schema = read_json(SCHEMA_PATH, failures)
  positive = read_json(POSITIVE_FIXTURE_PATH, failures)
  negative = read_json(NEGATIVE_FIXTURE_PATH, failures)

  return finish(failures) if common_vocab.nil?

  validate_schema_document(schema, failures)
  validate_positive_fixtures(common_vocab, positive, failures)
  validate_negative_fixtures(common_vocab, positive, negative, failures)

  finish(failures)
end

def finish(failures)
  if failures.empty?
    puts "STD-01 RawEvidenceEnvelope validator PASS"
    exit 0
  end

  warn "STD-01 RawEvidenceEnvelope validator FAIL"
  failures.each { |failure| warn "- #{failure}" }
  exit 1
end

main if $PROGRAM_NAME == __FILE__
