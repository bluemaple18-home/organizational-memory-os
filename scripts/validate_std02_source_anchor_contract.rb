#!/usr/bin/env ruby

require "json"
require "yaml"
require "time"

ROOT = File.expand_path("..", __dir__)
COMMON_VOCAB_PATH = File.join(ROOT, "規格/v0.1/common-vocabulary.yaml")
RAW_EVIDENCE_PATH = File.join(ROOT, "規格/v0.1/fixtures/std-01-raw-evidence-positive-fixtures.json")
SCHEMA_PATHS = %w[
  規格/v0.1/source-anchor.schema.json
  規格/v0.1/source-anchor-pdf-region-v1.schema.json
  規格/v0.1/source-anchor-markdown-text-v1.schema.json
  規格/v0.1/source-anchor-jira-cloud-entity-segment-v1.schema.json
].freeze
FIXTURE_PATHS = %w[
  規格/v0.1/fixtures/std-02-source-anchor-positive-fixtures.json
  規格/v0.1/fixtures/std-02-source-anchor-negative-fixtures.json
].freeze
REQUIRED_PATHS = (SCHEMA_PATHS + FIXTURE_PATHS).freeze
PROFILES = %w[PDF_REGION_V1 MARKDOWN_TEXT_V1 JIRA_CLOUD_ENTITY_SEGMENT_V1].freeze
POSITIVE_NAMES = %w[pdf-region-source-anchor markdown-text-source-anchor jira-cloud-entity-segment-source-anchor].freeze
NEGATIVE_NAMES = %w[
  pdf-bbox-out-of-range
  pdf-bbox-reversed
  pdf-page-zero
  pdf-missing-representation-digest
  pdf-profile-details-untrusted-extra
  selectors-not-array
  pdf-char-range-reversed
  markdown-line-only
  markdown-utf16-unit
  markdown-quote-mismatch
  markdown-relocation-without-robust-context
  jira-key-used-as-identity
  jira-missing-cloud-id
  jira-non-numeric-issue-id
  jira-data-center-mixed-into-cloud
  jira-invalid-json-pointer
  jira-field-id-pointer-mismatch
  acl-snapshot-reference-mismatch
  permission-reference-mismatch
  resolution-falsely-claims-revoked
  summary-used-as-quote
  source-evidence-reference-mismatch
].freeze
UUIDV7 = /\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/.freeze
SHA256 = /\Asha256:[0-9a-f]{64}\z/.freeze
COMMON_SCHEMA_URN = "urn:omos:schema:source-anchor:0.1.0"
SELECTOR_COMPOSITIONS = {
  "PDF_REGION_V1" => %w[PDF_REGION TEXT_QUOTE],
  "MARKDOWN_TEXT_V1" => %w[HEADING_PATH TEXT_POSITION TEXT_QUOTE],
  "JIRA_CLOUD_ENTITY_SEGMENT_V1" => %w[JSON_POINTER TEXT_POSITION TEXT_QUOTE]
}.freeze

def assert(condition, code, message, failures)
  failures << "#{code}: #{message}" unless condition
end

def read_json(path, failures)
  JSON.parse(File.read(path))
rescue JSON::ParserError => error
  failures << "JSON_PARSE: #{relative(path)} #{error.message}"
  nil
end

def read_yaml(path, failures)
  YAML.safe_load(File.read(path), permitted_classes: [], aliases: false)
rescue Psych::SyntaxError => error
  failures << "YAML_PARSE: #{relative(path)} #{error.message}"
  nil
end

def relative(path)
  path.sub("#{ROOT}/", "")
end

def dig(payload, path)
  path.split(".").reduce(payload) { |cursor, key| cursor.is_a?(Hash) ? cursor[key] : nil }
end

def deep_copy(value)
  JSON.parse(JSON.generate(value))
end

def valid_rfc3339?(value)
  value.is_a?(String) && value.end_with?("Z") && Time.iso8601(value)
rescue ArgumentError
  false
end

def changed_paths(left, right, prefix = "")
  if left.is_a?(Hash) && right.is_a?(Hash)
    (left.keys | right.keys).flat_map { |key| changed_paths(left[key], right[key], [prefix, key].reject(&:empty?).join(".")) }
  elsif left == right
    []
  else
    [prefix]
  end
end

def apply_mutation(anchor, mutation)
  keys = mutation.fetch("path").split(".")
  parent = keys[0...-1].reduce(anchor) { |cursor, key| cursor.fetch(key) }
  key = keys.last
  if mutation.fetch("op") == "delete"
    parent.delete(key)
  else
    parent[key] = mutation.fetch("value")
  end
end

def assert_required(schema, fields, code, label, failures)
  missing = fields - schema.fetch("required", [])
  assert(missing.empty?, code, "#{label} 缺 required #{missing.join(', ')}", failures)
end

def matches_type?(value, type)
  case type
  when :string then value.is_a?(String)
  when :integer then value.is_a?(Integer)
  when :number then value.is_a?(Numeric)
  when :object then value.is_a?(Hash)
  when :array then value.is_a?(Array)
  when :null then value.nil?
  end
end

def validate_closed_object(value, fields, label, failures)
  assert(value.is_a?(Hash), "#{label}_TYPE", "#{label} 必須是 object", failures)
  return unless value.is_a?(Hash)

  assert((fields.keys - value.keys).empty?, "#{label}_REQUIRED", "#{label} 缺 required #{(fields.keys - value.keys).join(', ')}", failures)
  assert((value.keys - fields.keys).empty?, "#{label}_CLOSED", "#{label} 不得含未知欄位 #{(value.keys - fields.keys).join(', ')}", failures)
  fields.each do |field, types|
    next unless value.key?(field)
    assert(types.any? { |type| matches_type?(value[field], type) }, "#{label}_TYPE", "#{label}.#{field} 型別不正確", failures)
  end
end

def validate_instance_structure(anchor, failures)
  validate_closed_object(anchor, {
    "schema_version" => [:string], "anchor_id" => [:string], "anchor_ref" => [:string], "evidence_ref" => [:string],
    "source_identity" => [:object], "source_version" => [:object], "representation" => [:object], "access" => [:object],
    "profile" => [:string], "selectors" => [:array], "profile_details" => [:object], "quote" => [:object],
    "normalization_profile" => [:string], "source_availability" => [:string], "resolution" => [:object]
  }, "COMMON_ROOT", failures)
  validate_closed_object(anchor["source_identity"], {
    "source_system" => [:string], "source_instance_id" => [:string], "entity_type" => [:string], "native_id" => [:string], "parent_native_id" => [:string, :null]
  }, "SOURCE_IDENTITY", failures)
  validate_closed_object(anchor["source_version"], {
    "basis" => [:string], "kind" => [:string], "value" => [:string, :null], "secondary_digest" => [:string, :null]
  }, "SOURCE_VERSION", failures)
  validate_closed_object(anchor["representation"], {
    "source_payload_ref" => [:string], "source_payload_digest" => [:string], "representation_ref" => [:string], "media_type" => [:string], "representation_digest" => [:string], "digest_basis" => [:string]
  }, "REPRESENTATION", failures)
  validate_closed_object(anchor["access"], {
    "acl_snapshot_ref" => [:string], "permission_decision_ref" => [:string, :null]
  }, "ACCESS", failures)
  validate_closed_object(anchor["quote"], {
    "exact" => [:string], "prefix" => [:string], "suffix" => [:string], "normalization_profile" => [:string]
  }, "QUOTE", failures)
  validate_closed_object(anchor["resolution"], {
    "status" => [:string], "resolved_at" => [:string], "resolver_version" => [:string]
  }, "RESOLUTION", failures)
  selectors = anchor["selectors"]
  return unless selectors.is_a?(Array)

  selectors.each_with_index do |selector, index|
    validate_closed_object(selector, { "selector_type" => [:string] }, "SELECTOR_#{index}", failures)
  end

  details = anchor["profile_details"]
  case anchor["profile"]
  when "PDF_REGION_V1"
    validate_closed_object(details, {
      "page" => [:integer], "page_number_basis" => [:string], "bbox" => [:object], "block_id" => [:string], "char_range" => [:object], "char_representation_ref" => [:string], "char_representation_digest" => [:string], "selected_text" => [:string]
    }, "PDF_REGION_V1_PROFILE_DETAILS", failures)
    validate_closed_object(details && details["bbox"], {
      "x_min" => [:number], "y_min" => [:number], "x_max" => [:number], "y_max" => [:number], "coordinate_space" => [:string], "origin" => [:string]
    }, "PDF_REGION_V1_BBOX", failures)
    validate_closed_object(details && details["char_range"], {
      "start" => [:integer], "end" => [:integer], "unit" => [:string], "range_semantics" => [:string]
    }, "PDF_REGION_V1_CHAR_RANGE", failures)
  when "MARKDOWN_TEXT_V1"
    validate_closed_object(details, {
      "codepoint_range" => [:object], "line_range" => [:object], "line_number_basis" => [:string], "heading_path" => [:array], "selected_text" => [:string]
    }, "MARKDOWN_TEXT_V1_PROFILE_DETAILS", failures)
    if details.is_a?(Hash) && details.key?("codepoint_range")
      validate_closed_object(details["codepoint_range"], {
        "start" => [:integer], "end" => [:integer], "unit" => [:string], "range_semantics" => [:string]
      }, "MARKDOWN_TEXT_V1_CODEPOINT_RANGE", failures)
    end
    validate_closed_object(details && details["line_range"], { "start" => [:integer], "end" => [:integer] }, "MARKDOWN_TEXT_V1_LINE_RANGE", failures) if details.is_a?(Hash) && details.key?("line_range")
    details.fetch("heading_path", []).each_with_index { |value, index| assert(value.is_a?(String), "MARKDOWN_TEXT_V1_HEADING_PATH_TYPE", "heading_path[#{index}] 必須是 string", failures) } if details.is_a?(Hash)
  when "JIRA_CLOUD_ENTITY_SEGMENT_V1"
    validate_closed_object(details, {
      "deployment_type" => [:string], "cloud_id" => [:string], "entity_type" => [:string], "issue_id" => [:string], "issue_key_alias" => [:string], "field_id" => [:string], "json_pointer" => [:string], "renderer_profile" => [:string], "renderer_version" => [:string], "text_selector" => [:object]
    }, "JIRA_CLOUD_ENTITY_SEGMENT_V1_PROFILE_DETAILS", failures)
    validate_closed_object(details && details["text_selector"], {
      "representation_ref" => [:string], "representation_digest" => [:string], "start" => [:integer], "end" => [:integer], "unit" => [:string], "range_semantics" => [:string], "exact" => [:string], "prefix" => [:string], "suffix" => [:string]
    }, "JIRA_CLOUD_ENTITY_SEGMENT_V1_TEXT_SELECTOR", failures)
  end
end

def validate_schema_documents(schemas, failures)
  common = schemas.fetch("source-anchor.schema.json")
  assert(common["$schema"] == "https://json-schema.org/draft/2020-12/schema", "SCHEMA_DIALECT", "Common SourceAnchor 必須宣告 JSON Schema 2020-12", failures)
  assert(common["$id"] == COMMON_SCHEMA_URN, "SCHEMA_ID", "Common SourceAnchor 必須使用 canonical schema URN", failures)
  assert(common["title"] == "Common SourceAnchor v0.1", "SCHEMA_TITLE", "Common SourceAnchor title 不正確", failures)
  assert(common["type"] == "object", "SCHEMA_TYPE", "Common SourceAnchor root 必須是 object", failures)
  assert(common["additionalProperties"] == false, "SCHEMA_CLOSED", "Common SourceAnchor root 必須 closed", failures)
  assert_required(common, %w[schema_version anchor_id anchor_ref evidence_ref source_identity source_version representation access profile selectors profile_details quote normalization_profile source_availability resolution], "SCHEMA_REQUIRED", "Common SourceAnchor", failures)
  assert(common.dig("$defs", "quote", "properties", "exact", "minLength") == 1, "SCHEMA_QUOTE", "quote.exact 必須是非空原文", failures)
  assert(common.dig("properties", "profile", "enum") == PROFILES, "SCHEMA_PROFILES", "Common SourceAnchor profile 必須精確對齊 LOCKED vocabulary", failures)
  assert(common.dig("properties", "representation", "additionalProperties") == false, "SCHEMA_REPRESENTATION_CLOSED", "representation 必須 closed", failures)
  assert_required(common.dig("properties", "representation") || {}, %w[source_payload_ref source_payload_digest representation_ref media_type representation_digest digest_basis], "SCHEMA_REPRESENTATION_REQUIRED", "representation", failures)
  assert(common.dig("properties", "representation", "properties", "source_payload_ref", "type") == "string" && common.dig("properties", "representation", "properties", "representation_ref", "type") == "string" && common.dig("properties", "representation", "properties", "source_payload_digest", "$ref") == "#/$defs/sha256" && common.dig("properties", "representation", "properties", "representation_digest", "$ref") == "#/$defs/sha256", "SCHEMA_REPRESENTATION_TYPES", "representation ref/digest 必須有精確型別", failures)
  assert(common.dig("properties", "representation", "properties", "media_type", "pattern") == "^[a-z]+/[a-z0-9.+-]+$", "SCHEMA_MEDIA_TYPE", "representation.media_type 必須是 IANA media type", failures)
  assert(common.dig("properties", "access", "additionalProperties") == false, "SCHEMA_ACCESS_CLOSED", "access 必須 closed", failures)
  assert_required(common.dig("properties", "access") || {}, %w[acl_snapshot_ref permission_decision_ref], "SCHEMA_ACCESS_REQUIRED", "access", failures)
  assert(common.dig("properties", "selectors", "items", "additionalProperties") == false, "SCHEMA_SELECTOR_CLOSED", "selector item 必須 closed", failures)
  assert(common.dig("properties", "selectors", "items", "properties", "selector_type", "enum").to_a.sort == SELECTOR_COMPOSITIONS.values.flatten.uniq.sort, "SCHEMA_SELECTOR_ENUM", "selector_type 必須限制為 Phase-1 enum", failures)
  %w[source_identity source_version quote resolution].each do |name|
    assert(common.dig("$defs", name, "additionalProperties") == false, "SCHEMA_COMMON_NESTED_CLOSED", "#{name} 必須 closed", failures)
  end
  assert(common.dig("$defs", "resolution", "properties", "resolved_at", "type") == "string" && common.dig("$defs", "resolution", "properties", "resolved_at", "format") == "date-time", "SCHEMA_RFC3339", "resolution.resolved_at 必須是 RFC3339 date-time", failures)

  {
    "source-anchor-pdf-region-v1.schema.json" => "PDF_REGION_V1",
    "source-anchor-markdown-text-v1.schema.json" => "MARKDOWN_TEXT_V1",
    "source-anchor-jira-cloud-entity-segment-v1.schema.json" => "JIRA_CLOUD_ENTITY_SEGMENT_V1"
  }.each do |filename, profile|
    schema = schemas.fetch(filename)
    assert(schema["$schema"] == "https://json-schema.org/draft/2020-12/schema", "SCHEMA_DIALECT", "#{filename} 必須宣告 JSON Schema 2020-12", failures)
    assert(schema.dig("allOf", 0, "$ref") == COMMON_SCHEMA_URN, "SCHEMA_COMMON_REF", "#{filename} 必須以 canonical common schema URN 引用", failures)
    assert(schema.dig("allOf", 1, "properties", "profile", "const") == profile, "SCHEMA_PROFILE_CONST", "#{filename} 必須鎖定 #{profile}", failures)
    assert_required(schema.dig("allOf", 1) || {}, %w[profile profile_details], "SCHEMA_PROFILE_REQUIRED", "#{filename}", failures)
    details = schema.dig("allOf", 1, "properties", "profile_details") || {}
    assert(details["type"] == "object" && details["additionalProperties"] == false, "SCHEMA_PROFILE_CLOSED", "#{filename} profile_details 必須是 closed object", failures)
  end
  pdf = schemas.fetch("source-anchor-pdf-region-v1.schema.json").dig("allOf", 1, "properties", "profile_details") || {}
  assert_required(pdf, %w[page page_number_basis bbox block_id char_range char_representation_ref char_representation_digest selected_text], "SCHEMA_PDF_REQUIRED", "PDF profile_details", failures)
  assert(pdf.dig("properties", "bbox", "additionalProperties") == false && pdf.dig("properties", "char_range", "additionalProperties") == false, "SCHEMA_PDF_NESTED_CLOSED", "PDF bbox 與 char_range 必須 closed", failures)
  assert(pdf.dig("properties", "page", "type") == "integer" && pdf.dig("properties", "bbox", "properties", "x_min", "type") == "number" && pdf.dig("properties", "char_range", "properties", "start", "type") == "integer", "SCHEMA_PDF_TYPES", "PDF selector 欄位必須有精確型別", failures)
  markdown = schemas.fetch("source-anchor-markdown-text-v1.schema.json").dig("allOf", 1, "properties", "profile_details") || {}
  assert_required(markdown, %w[codepoint_range line_range line_number_basis heading_path selected_text], "SCHEMA_MARKDOWN_REQUIRED", "Markdown profile_details", failures)
  assert(markdown.dig("properties", "codepoint_range", "additionalProperties") == false && markdown.dig("properties", "line_range", "additionalProperties") == false, "SCHEMA_MARKDOWN_NESTED_CLOSED", "Markdown ranges 必須 closed", failures)
  assert(markdown.dig("properties", "codepoint_range", "properties", "start", "type") == "integer" && markdown.dig("properties", "line_range", "properties", "start", "type") == "integer", "SCHEMA_MARKDOWN_TYPES", "Markdown range 欄位必須有精確型別", failures)
  jira = schemas.fetch("source-anchor-jira-cloud-entity-segment-v1.schema.json").dig("allOf", 1, "properties", "profile_details") || {}
  assert_required(jira, %w[deployment_type cloud_id entity_type issue_id issue_key_alias field_id json_pointer renderer_profile renderer_version text_selector], "SCHEMA_JIRA_REQUIRED", "Jira profile_details", failures)
  assert(jira.dig("properties", "json_pointer", "pattern") == "^(?:/(?:[^~/]|~[01])*)*$", "SCHEMA_RFC6901", "Jira json_pointer 必須使用 RFC6901 pattern", failures)
  assert(jira.dig("properties", "text_selector", "additionalProperties") == false, "SCHEMA_JIRA_SELECTOR_CLOSED", "Jira text_selector 必須 closed", failures)
  assert_required(jira.dig("properties", "text_selector") || {}, %w[representation_ref representation_digest start end unit range_semantics exact prefix suffix], "SCHEMA_JIRA_SELECTOR_REQUIRED", "Jira text_selector", failures)
  assert(jira.dig("properties", "issue_id", "type") == "string" && jira.dig("properties", "text_selector", "properties", "start", "type") == "integer" && jira.dig("properties", "text_selector", "properties", "representation_digest", "type") == "string", "SCHEMA_JIRA_TYPES", "Jira identity/text selector 欄位必須有精確型別", failures)
end

def availability_resolution_valid?(availability, status)
  {
    "AVAILABLE" => %w[EXACT_MATCH RELOCATED CONTENT_CHANGED MISSING AMBIGUOUS],
    "ACCESS_REVOKED" => ["ACCESS_REVOKED"],
    "REPRESENTATION_UNAVAILABLE" => ["REPRESENTATION_UNAVAILABLE"]
  }.fetch(availability, []).include?(status)
end

def validate_common(anchor, evidence_by_ref, common_vocab, failures)
  assert(anchor["schema_version"] == "omos.source-anchor.v0.1", "ANCHOR_SCHEMA_VERSION", "schema_version 不正確", failures)
  assert(anchor["anchor_id"].is_a?(String) && anchor["anchor_id"].match?(UUIDV7), "ANCHOR_ID", "anchor_id 必須是 UUIDv7", failures)
  assert(anchor["anchor_ref"] == "urn:omos:source-anchor:#{anchor["anchor_id"]}", "ANCHOR_REF", "anchor_ref 必須由 anchor_id 組成", failures)
  assert(PROFILES.include?(anchor["profile"]), "ANCHOR_PROFILE", "profile 不在 Phase-1 LOCKED vocabulary", failures)
  assert(anchor["selectors"].is_a?(Array) && !anchor["selectors"].empty?, "SELECTORS", "必須至少有一個 selector", failures)
  assert(anchor["normalization_profile"] == "OMOS_TEXT_NORM_V1" && anchor.dig("quote", "normalization_profile") == "OMOS_TEXT_NORM_V1", "NORMALIZATION_PROFILE", "anchor 與 quote 必須使用 OMOS_TEXT_NORM_V1", failures)

  evidence = evidence_by_ref[anchor["evidence_ref"]]
  unless evidence
    failures << "EVIDENCE_REF: evidence_ref 無法解析到 STD-01 RawEvidence"
    return nil
  end
  assert(anchor["source_identity"] == evidence["source_identity"], "SOURCE_IDENTITY_CROSS_REF", "source_identity 必須與 RawEvidence 相同", failures)
  assert(anchor["source_version"] == evidence["source_version"], "SOURCE_VERSION_CROSS_REF", "source_version 必須與 RawEvidence 相同", failures)

  representation = anchor["representation"] || {}
  representation_digest = representation["representation_digest"]
  assert(representation_digest.is_a?(String) && representation_digest.match?(SHA256), "REPRESENTATION_DIGEST", "representation_digest 必須是 sha256", failures) if representation.key?("representation_digest")
  assert(representation["source_payload_ref"] == evidence.dig("payload", "payload_ref"), "SOURCE_PAYLOAD_REF_CROSS_REF", "source_payload_ref 必須對齊 RawEvidence payload_ref", failures)
  assert(representation["source_payload_digest"] == evidence.dig("digests", "raw_digest"), "SOURCE_PAYLOAD_DIGEST_CROSS_REF", "source_payload_digest 必須對齊 RawEvidence raw_digest", failures)
  assert(representation["media_type"].is_a?(String) && representation["media_type"].match?(/\A[a-z]+\/[a-z0-9.+-]+\z/), "MEDIA_TYPE", "representation.media_type 必須是 IANA media type", failures)
  expected_basis = common_vocab.dig("source_anchor_profiles", "digest_basis", anchor["profile"], "representation_digest_basis")
  assert(representation["digest_basis"] == expected_basis, "REPRESENTATION_DIGEST_BASIS", "digest_basis 必須對齊 LOCKED vocabulary", failures)

  access = anchor["access"] || {}
  assert(access["acl_snapshot_ref"] == evidence.dig("access", "acl_snapshot_ref"), "ACL_SNAPSHOT_CROSS_REF", "acl_snapshot_ref 必須對齊 RawEvidence", failures)
  assert(access["permission_decision_ref"] == evidence["permission_decision_ref"], "PERMISSION_REF_CROSS_REF", "permission_decision_ref 必須對齊 RawEvidence", failures)
  assert(anchor["source_availability"] == evidence["source_availability"], "SOURCE_AVAILABILITY_CROSS_REF", "source_availability 必須對齊 RawEvidence", failures)

  status = anchor.dig("resolution", "status")
  assert(%w[EXACT_MATCH RELOCATED CONTENT_CHANGED MISSING ACCESS_REVOKED REPRESENTATION_UNAVAILABLE AMBIGUOUS].include?(status), "RESOLUTION_STATUS", "resolution.status 不合法", failures)
  assert(valid_rfc3339?(anchor.dig("resolution", "resolved_at")), "RESOLUTION_TIMESTAMP", "resolution.resolved_at 必須是 UTC RFC3339", failures)
  assert(availability_resolution_valid?(anchor["source_availability"], status), "RESOLUTION_AVAILABILITY_MISMATCH", "availability 與 resolution 必須符合 truth table", failures)
  if status == "RELOCATED"
    assert(!anchor.dig("quote", "prefix").to_s.empty? || !anchor.dig("quote", "suffix").to_s.empty?, "RELOCATED_CONTEXT", "RELOCATED 必須保留 prefix 或 suffix", failures)
  end
  evidence
end

def validate_selector_composition(anchor, failures)
  actual = anchor.fetch("selectors", []).map { |selector| selector.is_a?(Hash) ? selector["selector_type"] : nil }.compact.sort
  assert(actual == SELECTOR_COMPOSITIONS[anchor["profile"]], "SELECTOR_COMPOSITION", "#{anchor["profile"]} selector 組合不合法", failures)
end

def validate_pdf(anchor, evidence, failures)
  details = anchor["profile_details"] || {}
  bbox = details["bbox"] || {}
  assert(details["page"].is_a?(Integer) && details["page"] >= 1 && details["page_number_basis"] == "ONE_BASED", "PDF_PAGE", "PDF page 必須 1-based 且 >= 1", failures)
  %w[x_min y_min x_max y_max].each { |field| assert(bbox[field].is_a?(Numeric) && bbox[field].between?(0, 1), "PDF_BBOX_RANGE", "PDF bbox 必須在 [0,1]", failures) }
  assert(bbox["x_min"] < bbox["x_max"] && bbox["y_min"] < bbox["y_max"], "PDF_BBOX_ORDER", "PDF bbox min 必須小於 max", failures) if bbox.values_at("x_min", "x_max", "y_min", "y_max").all? { |value| value.is_a?(Numeric) }
  char_range = details["char_range"] || {}
  assert(char_range["start"].is_a?(Integer) && char_range["end"].is_a?(Integer) && char_range["start"] < char_range["end"] && char_range["unit"] == "UNICODE_CODE_POINT" && char_range["range_semantics"] == "START_INCLUSIVE_END_EXCLUSIVE", "PDF_CHAR_RANGE", "PDF char range 必須為 half-open Unicode code point", failures)
  assert(anchor.dig("representation", "media_type") == "text/plain", "PDF_MEDIA_TYPE", "PDF normalized page-text representation 必須是 text/plain", failures)
  if anchor.dig("representation", "representation_digest").is_a?(String)
    assert(details["char_representation_ref"] == anchor.dig("representation", "representation_ref") && details["char_representation_digest"] == anchor.dig("representation", "representation_digest"), "PDF_CHAR_REPRESENTATION_BINDING", "PDF char selector 必須綁定 representation ref 與 digest", failures)
  end
  assert(anchor.dig("representation", "representation_digest") != evidence.dig("digests", "raw_digest"), "PDF_RENDERED_DIGEST_SEPARATION", "PDF normalized page text digest 不得冒充 source payload digest", failures)
  assert(anchor.dig("quote", "exact") == details["selected_text"], "QUOTE_SELECTED_TEXT", "quote.exact 必須是實際選取原文，不得為摘要", failures)
end

def validate_markdown(anchor, failures)
  details = anchor["profile_details"] || {}
  range = details["codepoint_range"]
  if details.key?("codepoint_range")
    assert(range.is_a?(Hash), "MARKDOWN_CODEPOINT_RANGE", "Markdown 不得只靠 line range", failures)
  end
  if range.is_a?(Hash)
    assert(range["start"].is_a?(Integer) && range["end"].is_a?(Integer) && range["start"] < range["end"] && range["range_semantics"] == "START_INCLUSIVE_END_EXCLUSIVE", "MARKDOWN_CODEPOINT_RANGE", "Markdown codepoint range 必須為 half-open", failures)
    assert(range["unit"] == "UNICODE_CODE_POINT", "MARKDOWN_CODEPOINT_UNIT", "Markdown 不得把 UTF-16 code unit 標成 codepoint", failures)
  end
  line = details["line_range"] || {}
  assert(line["start"].is_a?(Integer) && line["end"].is_a?(Integer) && line["start"] <= line["end"] && details["line_number_basis"] == "ONE_BASED_END_INCLUSIVE", "MARKDOWN_LINE_RANGE", "Markdown line range 必須 1-based inclusive", failures)
  assert(anchor.dig("quote", "exact") == details["selected_text"], "QUOTE_SELECTED_TEXT", "quote.exact 必須是實際選取原文，不得為摘要", failures)
end

def json_pointer_tokens(value)
  return nil unless value.is_a?(String) && value.match?(/\A(?:\/(?:[^~\/]|~[01])*)*\z/)

  value.empty? ? [] : value.split("/").drop(1).map { |token| token.gsub("~1", "/").gsub("~0", "~") }
end

def validate_jira(anchor, evidence, failures)
  details = anchor["profile_details"] || {}
  assert(anchor.dig("source_identity", "source_system") == "jira-cloud" && details["deployment_type"] == "CLOUD", "JIRA_CLOUD_ONLY", "Jira Cloud profile 不得混入 Data Center", failures)
  assert(details["cloud_id"].is_a?(String) && !details["cloud_id"].empty? && details["cloud_id"] == anchor.dig("source_identity", "source_instance_id"), "JIRA_CLOUD_ID", "cloud_id 必填且必須等於 source_instance_id", failures)
  issue_id = details["issue_id"]
  assert(issue_id.is_a?(String) && issue_id.match?(/\A[0-9]+\z/) && issue_id == anchor.dig("source_identity", "native_id") && issue_id != details["issue_key_alias"], "JIRA_ISSUE_IDENTITY", "issue_id 必須是 numeric native identity；issue key 僅可為 alias", failures)
  pointer_tokens = json_pointer_tokens(details["json_pointer"])
  assert(!pointer_tokens.nil?, "JIRA_JSON_POINTER", "Jira JSON Pointer 必須為有效 RFC6901 pointer", failures)
  assert(pointer_tokens.first == "fields" && pointer_tokens[1] == details["field_id"], "JIRA_FIELD_POINTER_BINDING", "Jira field_id 必須與 JSON Pointer 綁定", failures) if pointer_tokens
  text = details["text_selector"] || {}
  assert(text["start"].is_a?(Integer) && text["end"].is_a?(Integer) && text["start"] < text["end"] && text["unit"] == "UNICODE_CODE_POINT" && text["range_semantics"] == "START_INCLUSIVE_END_EXCLUSIVE", "JIRA_TEXT_RANGE", "Jira text selector 必須為 half-open Unicode code point", failures)
  assert(anchor.dig("representation", "media_type") == "text/plain", "JIRA_MEDIA_TYPE", "Jira rendered ADF representation 必須是 text/plain", failures)
  assert(details["renderer_profile"].is_a?(String) && !details["renderer_profile"].empty? && details["renderer_version"].is_a?(String) && !details["renderer_version"].empty?, "JIRA_RENDERER", "Jira rendered ADF 必須聲明 renderer profile 與 version", failures)
  assert(text["representation_ref"] == anchor.dig("representation", "representation_ref") && text["representation_digest"] == anchor.dig("representation", "representation_digest"), "JIRA_TEXT_REPRESENTATION_BINDING", "Jira text selector 必須綁定 rendered representation ref 與 digest", failures)
  evidence_digests = [evidence.dig("digests", "raw_digest"), evidence.dig("digests", "canonical_digest"), evidence.dig("digests", "normalized_digest"), evidence.dig("source_version", "secondary_digest")].compact
  assert(!evidence_digests.include?(anchor.dig("representation", "representation_digest")), "JIRA_RENDERED_DIGEST_SEPARATION", "Jira rendered ADF digest 不得冒充 raw、canonical 或 selected payload digest", failures)
  assert(anchor.dig("quote", "exact") == text["exact"], "QUOTE_SELECTED_TEXT", "quote.exact 必須是實際選取原文，不得為摘要", failures)
end

def validate_anchor(anchor, evidence_by_ref, common_vocab)
  failures = []
  validate_instance_structure(anchor, failures)
  return failures unless anchor["selectors"].is_a?(Array)

  evidence = validate_common(anchor, evidence_by_ref, common_vocab, failures)
  validate_selector_composition(anchor, failures)
  case anchor["profile"]
  when "PDF_REGION_V1" then validate_pdf(anchor, evidence, failures) if evidence
  when "MARKDOWN_TEXT_V1" then validate_markdown(anchor, failures)
  when "JIRA_CLOUD_ENTITY_SEGMENT_V1" then validate_jira(anchor, evidence, failures) if evidence
  end
  failures
end

def validate_positive(positive, evidence_by_ref, common_vocab, failures)
  assert(positive["fixture_set"] == "std-02-source-anchor-positive-v0.1", "POSITIVE_FIXTURE_SET", "fixture_set 不正確", failures)
  names = positive.fetch("fixtures", []).map { |fixture| fixture["name"] }
  assert(names == POSITIVE_NAMES, "POSITIVE_FIXTURE_NAMES", "positive fixtures 必須精確覆蓋三 profile", failures)
  positive.fetch("fixtures", []).each do |fixture|
    validate_anchor(fixture["anchor"], evidence_by_ref, common_vocab).each { |failure| failures << "#{fixture["name"]}: #{failure}" }
  end
end

def validate_negative(negative, positive, evidence_by_ref, common_vocab, failures)
  assert(negative["fixture_set"] == "std-02-source-anchor-negative-v0.1", "NEGATIVE_FIXTURE_SET", "fixture_set 不正確", failures)
  names = negative.fetch("cases", []).map { |test_case| test_case["name"] }
  assert(names == NEGATIVE_NAMES, "NEGATIVE_FIXTURE_NAMES", "negative fixtures 必須精確覆蓋 STD-02 required cases", failures)
  bases = positive.fetch("fixtures", []).to_h { |fixture| [fixture["name"], fixture["anchor"]] }
  negative.fetch("cases", []).each do |test_case|
    authority = test_case["validation_authority"]
    assert(%w[JSON_SCHEMA RUBY_SEMANTIC].include?(authority), "NEGATIVE_AUTHORITY", "#{test_case["name"]} 必須明示 validation_authority", failures)
    assert(test_case["expected_result"] == "REJECT", "NEGATIVE_EXPECTED_RESULT", "#{test_case["name"]} 必須明示 expected_result=REJECT", failures)
    base = bases[test_case["base_fixture"]]
    assert(!base.nil?, "NEGATIVE_BASE", "#{test_case["name"]} 缺有效完整正向 base fixture", failures)
    next unless base
    mutated = deep_copy(base)
    begin
      test_case.fetch("mutations").each { |mutation| apply_mutation(mutated, mutation) }
    rescue KeyError
      failures << "NEGATIVE_MUTATION_PATH: #{test_case["name"]} mutation path 不可解析"
      next
    end
    declared_paths = test_case.fetch("mutations").map { |mutation| mutation["path"] }.sort
    assert(changed_paths(base, mutated).sort == declared_paths, "NEGATIVE_MINIMAL_MUTATION", "#{test_case["name"]} 必須只改 declared mutation paths", failures)
    if authority == "RUBY_SEMANTIC"
      actual_codes = validate_anchor(mutated, evidence_by_ref, common_vocab).map { |failure| failure.split(":").first }.uniq.sort
      expected_codes = test_case.fetch("expected_failure_codes").sort
      assert(actual_codes == expected_codes, "NEGATIVE_FAILURE_ISOLATION", "#{test_case["name"]} expected #{expected_codes.join(', ')}，實際 #{actual_codes.join(', ')}", failures)
    end
  end
end

def validate_availability_truth_table(failures)
  cases = [
    ["AVAILABLE", "EXACT_MATCH", true],
    ["AVAILABLE", "RELOCATED", true],
    ["AVAILABLE", "ACCESS_REVOKED", false],
    ["ACCESS_REVOKED", "ACCESS_REVOKED", true],
    ["ACCESS_REVOKED", "EXACT_MATCH", false],
    ["REPRESENTATION_UNAVAILABLE", "REPRESENTATION_UNAVAILABLE", true],
    ["REPRESENTATION_UNAVAILABLE", "EXACT_MATCH", false],
    ["REPRESENTATION_UNAVAILABLE", "ACCESS_REVOKED", false]
  ]
  cases.each do |availability, status, expected|
    assert(availability_resolution_valid?(availability, status) == expected, "AVAILABILITY_TRUTH_TABLE", "#{availability} / #{status} truth table 不正確", failures)
  end
end

def finish(failures)
  if failures.empty?
    puts "STD-02 SourceAnchor validator PASS"
    exit 0
  end
  warn "STD-02 SourceAnchor validator FAIL"
  failures.each { |failure| warn "- #{failure}" }
  exit 1
end

missing = REQUIRED_PATHS.reject { |path| File.exist?(File.join(ROOT, path)) }
finish(missing.map { |path| "MISSING_FILE: #{path}" }) unless missing.empty?

failures = []
common_vocab = read_yaml(COMMON_VOCAB_PATH, failures)
raw_evidence = read_json(RAW_EVIDENCE_PATH, failures)
schemas = SCHEMA_PATHS.to_h { |path| [File.basename(path), read_json(File.join(ROOT, path), failures)] }
positive = read_json(File.join(ROOT, FIXTURE_PATHS[0]), failures)
negative = read_json(File.join(ROOT, FIXTURE_PATHS[1]), failures)
finish(failures) if [common_vocab, raw_evidence, positive, negative, *schemas.values].any?(&:nil?)

assert(common_vocab.dig("schema", "status") == "LOCKED", "VOCABULARY_LOCK", "STD-02 必須使用 LOCKED common vocabulary", failures)
assert(common_vocab.dig("source_anchor_profiles", "phase_1") == PROFILES, "VOCABULARY_PROFILES", "Phase-1 profiles 必須對齊 common vocabulary", failures)
validate_schema_documents(schemas, failures)
validate_availability_truth_table(failures)
evidence_by_ref = raw_evidence.fetch("fixtures", []).to_h { |fixture| [fixture.dig("envelope", "evidence_ref"), fixture["envelope"]] }
validate_positive(positive, evidence_by_ref, common_vocab, failures)
validate_negative(negative, positive, evidence_by_ref, common_vocab, failures)
finish(failures)
