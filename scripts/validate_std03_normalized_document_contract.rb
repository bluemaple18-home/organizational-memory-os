#!/usr/bin/env ruby

require "digest"
require "json"
require "set"
require "yaml"

ROOT = File.expand_path("..", __dir__)
COMMON_VOCAB_PATH = File.join(ROOT, "規格/v0.1/common-vocabulary.yaml")
ROOT_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/normalized-document.schema.json")
BLOCK_SCHEMA_PATH = File.join(ROOT, "規格/v0.1/normalized-document-block.schema.json")
RAW_EVIDENCE_PATH = File.join(ROOT, "規格/v0.1/fixtures/std-01-raw-evidence-positive-fixtures.json")
SOURCE_ANCHOR_PATH = File.join(ROOT, "規格/v0.1/fixtures/std-02-source-anchor-positive-fixtures.json")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/std-03-normalized-document-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/std-03-normalized-document-negative-fixtures.json")
REQUIRED_PATHS = [
  COMMON_VOCAB_PATH,
  ROOT_SCHEMA_PATH,
  BLOCK_SCHEMA_PATH,
  RAW_EVIDENCE_PATH,
  SOURCE_ANCHOR_PATH,
  POSITIVE_FIXTURE_PATH,
  NEGATIVE_FIXTURE_PATH
].freeze

PHASE_1_BLOCK_TYPES = %w[title section_header paragraph list_item code table image unknown].freeze
POSITIVE_NAMES = %w[pdf-normalized-document markdown-normalized-document jira-normalized-document].freeze
NEGATIVE_NAMES = %w[
  root-untrusted-extra
  block-untrusted-extra
  root-empty-parser-receipt
  block-empty-content
  non-phase-one-block-type
  unresolved-evidence-ref
  unresolved-source-anchor-ref
  anchor-evidence-mismatch
  source-content-digest-mismatch
  block-content-digest-mismatch
  normalized-digest-mismatch
  duplicate-block-id
  duplicate-block-order
  missing-block-ref
  missing-parent
  parent-cycle
  table-missing-structured-cells
  image-missing-asset-ref
].freeze

SHA256 = /\Asha256:[0-9a-f]{64}\z/.freeze
NORMALIZED_DOCUMENT_REF = /\Aurn:omos:normalized-document:[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/.freeze
DOCUMENT_BLOCK_REF = /\Aurn:omos:document-block:[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/.freeze
RECEIPT_REF = /\Aurn:omos:receipt:[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/.freeze
SOURCE_ANCHOR_REF = /\Aurn:omos:source-anchor:[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/.freeze
LANGUAGE = /\A(?:[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*|und|mul)\z/.freeze

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

def deep_copy(value)
  JSON.parse(JSON.generate(value))
end

def present?(value)
  !value.nil? && !(value.respond_to?(:empty?) && value.empty?)
end

def dig_path(payload, path)
  path.split(".").reduce(payload) do |cursor, key|
    return nil if cursor.nil?

    cursor.is_a?(Array) ? cursor[Integer(key, exception: false)] : cursor[key]
  end
end

def apply_mutation(payload, mutation)
  keys = mutation.fetch("path").split(".")
  parent = keys[0...-1].reduce(payload) do |cursor, key|
    cursor.is_a?(Array) ? cursor.fetch(Integer(key)) : cursor.fetch(key)
  end
  key = keys.last
  if mutation.fetch("op") == "delete"
    parent.is_a?(Array) ? parent.delete_at(Integer(key)) : parent.delete(key)
  else
    parent.is_a?(Array) ? parent[Integer(key)] = mutation.fetch("value") : parent[key] = mutation.fetch("value")
  end
end

def changed_paths(left, right, prefix = "")
  if left.is_a?(Hash) && right.is_a?(Hash)
    (left.keys | right.keys).flat_map { |key| changed_paths(left[key], right[key], [prefix, key].reject(&:empty?).join(".")) }
  elsif left.is_a?(Array) && right.is_a?(Array)
    (0...[left.length, right.length].max).flat_map { |index| changed_paths(left[index], right[index], [prefix, index].reject { |part| part.to_s.empty? }.join(".")) }
  elsif left == right
    []
  else
    [prefix]
  end
end

def canonical_json(value)
  case value
  when Hash
    "{" + value.keys.sort.map { |key| JSON.generate(key) + ":" + canonical_json(value[key]) }.join(",") + "}"
  when Array
    "[" + value.map { |item| canonical_json(item) }.join(",") + "]"
  else
    JSON.generate(value)
  end
end

def sha256_for_text(text)
  "sha256:#{Digest::SHA256.hexdigest(text.encode("UTF-8"))}"
end

def normalized_digest(root, blocks)
  digest_root = deep_copy(root)
  digest_root.delete("normalized_digest")
  ordered_blocks = root.fetch("block_refs", []).map do |block_id|
    blocks.find { |block| block["block_id"] == block_id }
  end
  "sha256:#{Digest::SHA256.hexdigest(canonical_json({ "root" => digest_root, "blocks" => ordered_blocks }))}"
end

def validate_schema_documents(root_schema, block_schema, common_vocab, failures)
  assert(root_schema["$schema"] == "https://json-schema.org/draft/2020-12/schema", "ROOT_SCHEMA_DIALECT", "Root schema 必須宣告 JSON Schema 2020-12", failures)
  assert(root_schema["$id"] == "urn:omos:schema:normalized-document:0.1.0", "ROOT_SCHEMA_ID", "Root schema 必須使用 canonical schema URN", failures)
  assert(root_schema["additionalProperties"] == false, "ROOT_SCHEMA_CLOSED", "Root schema 必須 closed", failures)
  %w[schema_version normalized_document_id source_evidence_ref source_content_sha256 normalized_digest parser_receipt_ref document quality_gaps block_refs].each do |field|
    assert(root_schema.fetch("required", []).include?(field), "ROOT_SCHEMA_REQUIRED", "Root schema required 缺 #{field}", failures)
  end
  assert(root_schema.dig("properties", "document", "additionalProperties") == false, "ROOT_DOCUMENT_CLOSED", "document 必須 closed", failures)
  quality_gap_schema = root_schema.dig("properties", "quality_gaps", "items")
  quality_gap_schema = root_schema.dig("$defs", "quality_gap") if quality_gap_schema == { "$ref" => "#/$defs/quality_gap" }
  assert(quality_gap_schema&.dig("additionalProperties") == false, "ROOT_QUALITY_GAP_CLOSED", "quality gap item 必須 closed", failures)
  assert(root_schema.dig("properties", "block_refs", "uniqueItems") == true, "ROOT_BLOCK_REFS_UNIQUE", "block_refs 必須 uniqueItems", failures)

  assert(block_schema["$schema"] == "https://json-schema.org/draft/2020-12/schema", "BLOCK_SCHEMA_DIALECT", "Block schema 必須宣告 JSON Schema 2020-12", failures)
  assert(block_schema["$id"] == "urn:omos:schema:normalized-document-block:0.1.0", "BLOCK_SCHEMA_ID", "Block schema 必須使用 canonical schema URN", failures)
  assert(block_schema["additionalProperties"] == false, "BLOCK_SCHEMA_CLOSED", "Block schema 必須 closed", failures)
  %w[block_id block_type parent_id order level content content_sha256 language content_layer source_anchor_refs attributes quality].each do |field|
    assert(block_schema.fetch("required", []).include?(field), "BLOCK_SCHEMA_REQUIRED", "Block schema required 缺 #{field}", failures)
  end
  assert(block_schema.dig("properties", "block_type", "enum") == PHASE_1_BLOCK_TYPES, "BLOCK_TYPE_PHASE_1", "block_type 必須精確鎖定 Phase-1 子集", failures)
  assert(!block_schema.dig("properties", "block_type", "enum").include?("image_ref"), "BLOCK_TYPE_NO_IMAGE_REF", "STD-03 kickoff 已裁決不使用 image_ref", failures)
  assert(block_schema.dig("properties", "attributes", "additionalProperties") == false, "BLOCK_ATTRIBUTES_CLOSED", "attributes 必須 closed", failures)
  assert(JSON.generate(block_schema).include?("table_attributes"), "BLOCK_TABLE_SCHEMA", "table 必須有 structured cells schema", failures)
  assert(JSON.generate(block_schema).include?("image_asset"), "BLOCK_IMAGE_SCHEMA", "image 必須有 asset/caption/bbox schema", failures)

  locked_types = common_vocab.dig("common_enums", "block_type").to_a
  assert((PHASE_1_BLOCK_TYPES - locked_types).empty?, "VOCABULARY_BLOCK_TYPES", "Phase-1 block type 必須是 STD-00 LOCKED vocabulary 子集", failures)
end

def validate_root(root, raw_by_ref, failures)
  assert(root["schema_version"] == "omos.normalized-document.v0.1", "ROOT_SCHEMA_VERSION", "schema_version 不正確", failures)
  assert(root["normalized_document_id"].is_a?(String) && root["normalized_document_id"].match?(NORMALIZED_DOCUMENT_REF), "NORMALIZED_DOCUMENT_ID", "normalized_document_id 必須是 urn:omos:normalized-document UUIDv7", failures)
  assert(root["parser_receipt_ref"].is_a?(String) && root["parser_receipt_ref"].match?(RECEIPT_REF), "PARSER_RECEIPT_REF", "parser_receipt_ref 必須是 receipt URN", failures)
  assert(root["normalized_digest"].is_a?(String) && root["normalized_digest"].match?(SHA256), "NORMALIZED_DIGEST_SHAPE", "normalized_digest 必須是 sha256", failures)
  assert(root["block_refs"].is_a?(Array) && root["block_refs"].all? { |ref| ref.is_a?(String) && ref.match?(DOCUMENT_BLOCK_REF) }, "BLOCK_REFS", "block_refs 必須是 document-block URN array", failures)
  document = root["document"]
  assert(document.is_a?(Hash), "DOCUMENT", "document 必須存在", failures)
  if document.is_a?(Hash)
    %w[name media_type language page_count].each { |field| assert(document.key?(field), "DOCUMENT_REQUIRED", "document.#{field} 必填", failures) }
    assert(present?(document["name"]), "DOCUMENT_NAME", "document.name 不得為空", failures)
    assert(document["language"].is_a?(String) && document["language"].match?(LANGUAGE), "DOCUMENT_LANGUAGE", "document.language 必須是 BCP47 或 und/mul", failures)
  end
  evidence = raw_by_ref[root["source_evidence_ref"]]
  unless evidence
    failures << "EVIDENCE_REF: source_evidence_ref 無法解析到 STD-01 RawEvidence"
    return nil
  end
  assert(root["source_content_sha256"] == evidence.dig("digests", "raw_digest"), "SOURCE_CONTENT_DIGEST", "source_content_sha256 必須對齊 RawEvidence raw digest", failures)
  evidence
end

def validate_table(block, failures)
  table = block.dig("attributes", "table")
  unless table.is_a?(Hash)
    failures << "TABLE_STRUCTURE: table block 必須有 attributes.table"
    return
  end
  assert(table["columns"].is_a?(Array) && !table["columns"].empty?, "TABLE_STRUCTURE", "table 必須有 columns", failures)
  rows = table["rows"]
  assert(rows.is_a?(Array) && !rows.empty?, "TABLE_STRUCTURE", "table 必須有 rows", failures)
  rows.to_a.each_with_index do |row, index|
    assert(row["cells"].is_a?(Array) && !row["cells"].empty?, "TABLE_STRUCTURE", "table row #{index} 必須有 structured cells", failures)
  end
end

def validate_image(block, failures)
  asset = block.dig("attributes", "asset")
  unless asset.is_a?(Hash)
    failures << "IMAGE_ASSET: image block 必須有 attributes.asset"
    return
  end
  assert(asset["asset_ref"].is_a?(String) && asset["asset_ref"].start_with?("urn:omos:asset:"), "IMAGE_ASSET", "image 必須有 asset_ref", failures)
  assert(present?(asset["caption"]), "IMAGE_ASSET", "image 必須有 caption", failures)
  bbox = asset["bbox"]
  assert(bbox.is_a?(Hash) && %w[x_min y_min x_max y_max coordinate_space origin].all? { |field| bbox.key?(field) }, "IMAGE_ASSET", "image 必須有 bbox", failures)
end

def validate_blocks(root, blocks, anchor_by_ref, failures)
  ids = blocks.map { |block| block["block_id"] }
  orders = blocks.map { |block| block["order"] }
  duplicate_ids = ids.group_by(&:itself).select { |_id, values| values.length > 1 }.keys
  duplicate_orders = orders.group_by(&:itself).select { |_order, values| values.length > 1 }.keys
  assert(duplicate_ids.empty?, "DUPLICATE_BLOCK_ID", "block_id 不得重複", failures)
  assert(duplicate_orders.empty?, "DUPLICATE_BLOCK_ORDER", "order 不得重複", failures)

  if duplicate_ids.empty?
    assert(root["block_refs"] == ids, "BLOCK_REF_SET", "block_refs 必須與 blocks block_id 一對一且同序", failures)
  end

  id_set = ids.to_set
  blocks.each do |block|
    assert(PHASE_1_BLOCK_TYPES.include?(block["block_type"]), "BLOCK_TYPE", "block_type 不在 Phase-1 子集", failures)
    assert(present?(block["content"]), "BLOCK_CONTENT", "content 不得為空", failures)
    assert(block["content_sha256"] == sha256_for_text(block["content"].to_s), "BLOCK_CONTENT_DIGEST", "content_sha256 必須由 UTF-8 content 重算", failures)
    assert(block["language"].is_a?(String) && block["language"].match?(LANGUAGE), "BLOCK_LANGUAGE", "language 必須是 BCP47 或 und/mul", failures)
    parent_id = block["parent_id"]
    assert(parent_id.nil? || id_set.include?(parent_id), "PARENT_REF", "parent_id 必須存在於同 bundle blocks", failures)
    anchor_refs = block["source_anchor_refs"]
    assert(anchor_refs.is_a?(Array) && !anchor_refs.empty? && anchor_refs.all? { |ref| ref.is_a?(String) && ref.match?(SOURCE_ANCHOR_REF) }, "SOURCE_ANCHOR_REF_SHAPE", "source_anchor_refs 必須是 source-anchor URN array", failures)
    anchor_refs.to_a.each do |anchor_ref|
      anchor = anchor_by_ref[anchor_ref]
      if anchor.nil?
        failures << "SOURCE_ANCHOR_REF: source_anchor_ref 無法解析到 STD-02 SourceAnchor"
      else
        assert(anchor["evidence_ref"] == root["source_evidence_ref"], "ANCHOR_EVIDENCE_MISMATCH", "SourceAnchor evidence_ref 必須與 root source_evidence_ref 相同", failures)
      end
    end
    validate_table(block, failures) if block["block_type"] == "table"
    validate_image(block, failures) if block["block_type"] == "image"
  end

  blocks.each do |block|
    seen = Set.new
    cursor = block
    loop do
      parent_id = cursor["parent_id"]
      break if parent_id.nil?
      if seen.include?(parent_id) || parent_id == block["block_id"]
        failures << "PARENT_CYCLE: block hierarchy 不得成環"
        break
      end
      seen.add(parent_id)
      cursor = blocks.find { |candidate| candidate["block_id"] == parent_id }
      break if cursor.nil?
    end
  end
end

def validate_bundle(bundle, raw_by_ref, anchor_by_ref)
  failures = []
  root = bundle["root"]
  blocks = bundle["blocks"]
  unless root.is_a?(Hash) && blocks.is_a?(Array)
    failures << "BUNDLE_SHAPE: fixture 必須包含 root object 與 blocks array"
    return failures
  end

  validate_root(root, raw_by_ref, failures)
  validate_blocks(root, blocks, anchor_by_ref, failures)
  if failures.none? { |failure| failure.start_with?("DUPLICATE_BLOCK_ID", "BLOCK_REF_SET") }
    assert(root["normalized_digest"] == normalized_digest(root, blocks), "NORMALIZED_DIGEST", "normalized_digest 必須由 root/blocks deterministic representation 重算", failures)
  end
  failures
end

def primary_failure_codes(failures)
  codes = failures.map { |failure| failure.split(":").first }.uniq
  codes -= ["NORMALIZED_DIGEST"] unless codes == ["NORMALIZED_DIGEST"]
  codes -= ["ANCHOR_EVIDENCE_MISMATCH"] if codes.include?("EVIDENCE_REF")
  codes -= ["PARENT_CYCLE"] if codes.include?("DUPLICATE_BLOCK_ID")
  codes.sort
end

def validate_positive(positive, raw_by_ref, anchor_by_ref, failures)
  assert(positive["fixture_set"] == "std-03-normalized-document-positive-v0.1", "POSITIVE_FIXTURE_SET", "fixture_set 不正確", failures)
  names = positive.fetch("fixtures", []).map { |fixture| fixture["name"] }
  assert(names == POSITIVE_NAMES, "POSITIVE_FIXTURE_NAMES", "positive fixtures 必須精確覆蓋 PDF／Markdown／Jira", failures)
  positive.fetch("fixtures", []).each do |fixture|
    validate_bundle(fixture, raw_by_ref, anchor_by_ref).each { |failure| failures << "#{fixture["name"]}: #{failure}" }
  end
end

def validate_negative(negative, positive, raw_by_ref, anchor_by_ref, failures)
  assert(negative["fixture_set"] == "std-03-normalized-document-negative-v0.1", "NEGATIVE_FIXTURE_SET", "fixture_set 不正確", failures)
  names = negative.fetch("cases", []).map { |test_case| test_case["name"] }
  assert(names == NEGATIVE_NAMES, "NEGATIVE_FIXTURE_NAMES", "negative fixtures 必須精確覆蓋 STD-03 required cases", failures)
  bases = positive.fetch("fixtures", []).to_h { |fixture| [fixture["name"], fixture] }

  negative.fetch("cases", []).each do |test_case|
    authority = test_case["validation_authority"]
    assert(%w[JSON_SCHEMA RUBY_SEMANTIC].include?(authority), "NEGATIVE_AUTHORITY", "#{test_case["name"]} 必須明示 validation_authority", failures)
    assert(test_case["expected_result"] == "REJECT", "NEGATIVE_EXPECTED_RESULT", "#{test_case["name"]} 必須明示 expected_result=REJECT", failures)
    if authority == "RUBY_SEMANTIC"
      assert(test_case["schema_expected_result"] == "ALLOW", "NEGATIVE_SCHEMA_EXPECTED_RESULT", "#{test_case["name"]} schema_expected_result 必須是 ALLOW", failures)
    else
      assert(test_case["expected_schema_errors"].is_a?(Array) && !test_case["expected_schema_errors"].empty?, "NEGATIVE_SCHEMA_ERRORS", "#{test_case["name"]} 必須聲明 expected_schema_errors", failures)
    end

    base = bases[test_case["base_fixture"]]
    assert(!base.nil?, "NEGATIVE_BASE", "#{test_case["name"]} 缺有效完整正向 base fixture", failures)
    next unless base

    mutated = deep_copy(base)
    begin
      test_case.fetch("mutations").each do |mutation|
        target = mutation.fetch("target")
        if target == "root"
          apply_mutation(mutated["root"], mutation)
        elsif target == "block"
          apply_mutation(mutated.fetch("blocks").fetch(mutation.fetch("index")), mutation)
        else
          raise KeyError, target
        end
      end
    rescue KeyError, IndexError
      failures << "NEGATIVE_MUTATION_PATH: #{test_case["name"]} mutation path 不可解析"
      next
    end

    actual_paths = changed_paths(base, mutated)
    declared_paths = test_case.fetch("mutations").map do |mutation|
      prefix = mutation["target"] == "root" ? "root" : "blocks.#{mutation["index"]}"
      [prefix, mutation["path"]].join(".")
    end
    assert(actual_paths.sort == declared_paths.sort, "NEGATIVE_MINIMAL_MUTATION", "#{test_case["name"]} 必須只改 declared mutation paths", failures)

    next unless authority == "RUBY_SEMANTIC"

    actual_codes = primary_failure_codes(validate_bundle(mutated, raw_by_ref, anchor_by_ref))
    expected_codes = test_case.fetch("expected_failure_codes").sort
    assert(actual_codes == expected_codes, "NEGATIVE_FAILURE_ISOLATION", "#{test_case["name"]} expected #{expected_codes.join(', ')}，實際 #{actual_codes.join(', ')}", failures)
  end
end

def finish(failures)
  if failures.empty?
    puts "STD-03 NormalizedDocument validator PASS"
    exit 0
  end
  warn "STD-03 NormalizedDocument validator FAIL"
  failures.each { |failure| warn "- #{failure}" }
  exit 1
end

missing = REQUIRED_PATHS.reject { |path| File.exist?(path) }
finish(missing.map { |path| "MISSING_FILE: #{relative(path)}" }) unless missing.empty?

failures = []
common_vocab = read_yaml(COMMON_VOCAB_PATH, failures)
root_schema = read_json(ROOT_SCHEMA_PATH, failures)
block_schema = read_json(BLOCK_SCHEMA_PATH, failures)
raw_evidence = read_json(RAW_EVIDENCE_PATH, failures)
source_anchor = read_json(SOURCE_ANCHOR_PATH, failures)
positive = read_json(POSITIVE_FIXTURE_PATH, failures)
negative = read_json(NEGATIVE_FIXTURE_PATH, failures)
finish(failures) if [common_vocab, root_schema, block_schema, raw_evidence, source_anchor, positive, negative].any?(&:nil?)

raw_by_ref = raw_evidence.fetch("fixtures", []).to_h { |fixture| [fixture.dig("envelope", "evidence_ref"), fixture["envelope"]] }
anchor_by_ref = source_anchor.fetch("fixtures", []).to_h { |fixture| [fixture.dig("anchor", "anchor_ref"), fixture["anchor"]] }

assert(common_vocab.dig("schema", "status") == "LOCKED", "VOCABULARY_LOCK", "STD-03 必須使用 LOCKED common vocabulary", failures)
validate_schema_documents(root_schema, block_schema, common_vocab, failures)
validate_positive(positive, raw_by_ref, anchor_by_ref, failures)
validate_negative(negative, positive, raw_by_ref, anchor_by_ref, failures)
finish(failures)
