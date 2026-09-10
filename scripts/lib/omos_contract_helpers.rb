# frozen_string_literal: true
#
# 跨所有 OMOS 契約 validator 共用的最小 helper。
#
# 兩層:
#   1. 每個 validator 都逐字相同的部分:duplicate-key fail-closed 的
#      JSON / YAML 讀取基礎元件(DuplicateKeyError / StrictJsonObject /
#      assert_unique_yaml_mapping_keys),以及 present? 判斷。
#   2. personal-memory 家族(personal-memory / resource / capability / recall /
#      correction)共用的簡單 I/O 與判斷:read_json / read_yaml / assert(3-arg)/
#      sorted_set(Set 版)/ allowed_resource_ref?。
#
# 刻意不放(arity 或行為不同,各自留在檔內並在 require 之後覆蓋):
#   - STD-01/02/03 的 read_json / read_yaml —— (path, failures) 變體
#     (collect failures + rescue)。
#   - STD-01/02 的 assert —— (condition, code, message, failures),code: prefix。
#   - AIWR 的 sorted_set —— 回傳排序後的 Array,不是 Set。

require "digest"
require "json"
require "set"
require "yaml"

class DuplicateKeyError < StandardError; end

class StrictJsonObject < Hash
  def []=(key, value)
    raise DuplicateKeyError, "duplicate JSON object key #{key.inspect}" if key?(key)

    super
  end
end

def assert_unique_yaml_mapping_keys(node, path = "$")
  case node
  when Psych::Nodes::Stream, Psych::Nodes::Document
    node.children.each { |child| assert_unique_yaml_mapping_keys(child, path) }
  when Psych::Nodes::Sequence
    node.children.each_with_index { |child, index| assert_unique_yaml_mapping_keys(child, "#{path}[#{index}]") }
  when Psych::Nodes::Mapping
    seen = {}
    node.children.each_slice(2) do |key_node, value_node|
      key = key_node.respond_to?(:value) ? key_node.value : key_node.to_s
      child_path = "#{path}.#{key}"
      raise DuplicateKeyError, "duplicate YAML mapping key #{child_path}" if seen.key?(key)

      seen[key] = true
      assert_unique_yaml_mapping_keys(value_node, child_path)
    end
  end
end

def present?(value)
  !value.nil? && !(value.respond_to?(:empty?) && value.empty?)
end

# --- personal-memory 家族(personal-memory / resource / capability / recall /
# correction)共用的簡單 I/O 與判斷。STD-01/02/03 與 AIWR validator 仍各自帶
# 不同 arity 的本地版本,在 require 之後定義並覆蓋這裡,因此加入這些不改變其行為。

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
  values.to_set
end

def allowed_resource_ref?(value, resource_kind)
  value.is_a?(String) && value.start_with?("urn:omos:personal-memory:#{resource_kind}:")
end

# --- 通用結構工具：deep dup / "a/b/c" path 存取 / sorted-key canonical JSON。
# adapter-mapping validator 用來自算 canonical projection digest（fixture 不提供 digest）。

def deep_dup(obj)
  case obj
  when Hash then obj.each_with_object({}) { |(key, value), acc| acc[key] = deep_dup(value) }
  when Array then obj.map { |value| deep_dup(value) }
  else obj
  end
end

def dig_parent(root, path)
  segments = path.split("/")
  leaf = segments.pop
  node = segments.inject(root) { |acc, seg| acc.is_a?(Hash) ? acc[seg] : nil }
  [node, leaf]
end

def read_path(root, path)
  path.split("/").inject(root) { |acc, seg| acc.is_a?(Hash) ? acc[seg] : nil }
end

def delete_path(root, path)
  node, leaf = dig_parent(root, path)
  node.delete(leaf) if node.is_a?(Hash)
end

def set_path(root, path, value)
  node, leaf = dig_parent(root, path)
  node[leaf] = value if node.is_a?(Hash)
end

def canonical_json(obj)
  case obj
  when Hash then "{#{obj.keys.sort.map { |key| "#{key.to_json}:#{canonical_json(obj[key])}" }.join(",")}}"
  when Array then "[#{obj.map { |value| canonical_json(value) }.join(",")}]"
  else obj.to_json
  end
end

# adapter-mapping fixture 的三段 projection surface。
def triple_of(test_case)
  {
    "raw_evidence" => test_case["raw_evidence_instance"],
    "source_anchor" => test_case["source_anchor_instance"],
    "blocks" => test_case["block_instances"]
  }
end

# F-02/F-03-R0x：宣告的 derived 欄位必須是 determinism.inputs 的函數。validator 依 inputs
# 重算並與 projected instance 逐項比對，回傳失配的 binding 名稱（key 必須逐字等於
# EXPECTED_DERIVATION_BINDING_KEYS）。改任一 input / instance-side derived 欄位 -> 至少一項失配。
DOC_MAP_DETERMINISM_INPUTS = %w[
  content_digest adapter_id adapter_version tenant_id source_instance_id
  normalized_representation_digest normalized_document_digest
].freeze
# 每個 block 中的 per-run 欄位（不屬 deterministic block surface）。
DOC_MAP_BLOCK_RUN_SCOPED_KEYS = %w[block_id parent_id source_anchor_refs quality].freeze
# 每份 projection 中「非 deterministic identity 一部分」的 per-run 欄位。移掉這些之後，剩下的
# 每一片都必須逐字等於 reconstruct_deterministic_projection(kind, inputs)。
DOC_MAP_RUN_SCOPED_PATHS = %w[
  raw_evidence/evidence_id raw_evidence/evidence_ref raw_evidence/source_aliases raw_evidence/source_event
  raw_evidence/chronology raw_evidence/access raw_evidence/transport_delivery raw_evidence/activity_refs
  raw_evidence/source_availability raw_evidence/payload_retention_state raw_evidence/deletion_confirmation_ref
  raw_evidence/permission_decision_ref raw_evidence/quality_gaps
  raw_evidence/payload/payload_ref raw_evidence/payload/size_bytes
  raw_evidence/provenance/ingestion_mode
  raw_evidence/provenance/source_observation_receipt_ref raw_evidence/provenance/adapter_activity_ref
  raw_evidence/provenance/lineage_receipt_ref
  source_anchor/anchor_id source_anchor/anchor_ref source_anchor/evidence_ref source_anchor/access
  source_anchor/quote source_anchor/source_availability source_anchor/resolution source_anchor/selectors
  source_anchor/profile_details
  source_anchor/representation/source_payload_ref source_anchor/representation/source_payload_digest
  source_anchor/representation/representation_ref
].freeze

# 從 declared inputs 完整重建 deterministic identity surface（RawEvidence + SourceAnchor 的
# 非 run-scoped 部分）。fixture 的對應片段必須逐字等於這個結果，否則 derived != f(inputs)。
def reconstruct_deterministic_projection(kind, inputs)
  cd = inputs["content_digest"]
  nrd = inputs["normalized_representation_digest"]
  identity = {
    "source_system" => "document", "source_instance_id" => inputs["source_instance_id"],
    "entity_type" => kind, "native_id" => cd, "parent_native_id" => nil
  }
  version = { "basis" => "CONTENT_ONLY", "kind" => "CONTENT_DIGEST", "value" => nil, "secondary_digest" => cd }
  media = kind == "PDF" ? "application/pdf" : "text/markdown"
  profile = kind == "PDF" ? "BINARY" : "TEXT"
  basis = kind == "PDF" ? "retained representation bytes" : "normalized text bytes"
  {
    "raw_evidence" => {
      "schema_version" => "omos.evidence.raw.v0.1",
      "tenant_id" => inputs["tenant_id"],
      "source_identity" => identity,
      "source_version" => version,
      "digests" => { "raw_digest" => cd, "canonical_digest" => nil, "normalized_digest" => nrd },
      "payload" => {
        "media_type" => media, "structured_profile" => profile,
        "canonicalization_profile" => "NONE", "retention_tier" => "SOURCE_FULL_BODY"
      },
      "provenance" => {
        "adapter_id" => inputs["adapter_id"], "adapter_version" => inputs["adapter_version"],
        "lineage_activity_status" => "COMPLETE", "verification_status" => "NOT_RUN",
        "verification_inferred_from_activity" => false
      },
      "idempotency_key" => "sha256:" + Digest::SHA256.hexdigest(
        canonical_json("content_digest" => cd, "tenant_id" => inputs["tenant_id"])
      ),
      "idempotency_basis" => {
        "profile" => "OMOS_ENTITY_SNAPSHOT_IDEMPOTENCY_V1",
        "includes" => %w[tenant_id stable_source_identity source_version],
        "excludes" => %w[received_at persisted_at ingestion_mode]
      }
    },
    "source_anchor" => {
      "schema_version" => "omos.source-anchor.v0.1",
      "source_identity" => identity,
      "source_version" => version,
      "representation" => { "media_type" => "text/plain", "representation_digest" => nrd, "digest_basis" => basis },
      "profile" => (kind == "PDF" ? "PDF_REGION_V1" : "MARKDOWN_TEXT_V1"),
      "normalization_profile" => "OMOS_TEXT_NORM_V1"
    }
  }
end

# 一份 block 清單去掉 per-run 欄位後的 deterministic surface。
def deterministic_block_surface(blocks)
  blocks.to_a.map do |block|
    trimmed = deep_dup(block)
    DOC_MAP_BLOCK_RUN_SCOPED_KEYS.each { |key| trimmed.delete(key) }
    trimmed
  end
end

# deterministic block surface 的 canonical SHA256（第 7 個 declared input 綁定對象）。
def normalized_document_digest(blocks)
  "sha256:" + Digest::SHA256.hexdigest(canonical_json(deterministic_block_surface(blocks)))
end

# fixture 的 {raw_evidence, source_anchor, blocks} 去掉 run-scoped 之後，逐鍵與「只由 inputs
# 重建」的結果比對。回傳不符（含未分類欄位、block digest 不符、block content_sha256 不一致）
# 的路徑清單。
def deterministic_surface_mismatches(kind, inputs, raw, anchor, blocks)
  observed = deep_dup("raw_evidence" => raw, "source_anchor" => anchor)
  DOC_MAP_RUN_SCOPED_PATHS.each { |path| delete_path(observed, path) }
  problems = diff_paths(reconstruct_deterministic_projection(kind, inputs), observed, "")

  unless normalized_document_digest(blocks) == inputs["normalized_document_digest"]
    problems << "blocks/normalized_document_digest (expected #{inputs["normalized_document_digest"].inspect}, " \
                "got #{normalized_document_digest(blocks).inspect})"
  end
  blocks.to_a.each_with_index do |block, index|
    expected_sha = "sha256:" + Digest::SHA256.hexdigest(block["content"].to_s)
    problems << "blocks/#{index}/content_sha256 (expected #{expected_sha}, got #{block["content_sha256"].inspect})" unless
      block["content_sha256"] == expected_sha
  end
  # PDF profile_details 整體 run-scoped，但 char_representation_digest 仍綁到 normalized rep digest。
  if kind == "PDF" && anchor.dig("profile_details", "char_representation_digest") != inputs["normalized_representation_digest"]
    problems << "source_anchor/profile_details/char_representation_digest (expected " \
                "#{inputs["normalized_representation_digest"].inspect}, got " \
                "#{anchor.dig("profile_details", "char_representation_digest").inspect})"
  end
  problems
end

def diff_paths(expected, observed, prefix)
  return [] if expected == observed

  if expected.is_a?(Hash) && observed.is_a?(Hash)
    (expected.keys | observed.keys).flat_map { |key| diff_paths(expected[key], observed[key], "#{prefix}#{key}/") }
  else
    ["#{prefix.chomp("/")} (expected #{expected.inspect}, got #{observed.inspect})"]
  end
end

# 從 profile-specific schema 的 allOf 取 profile_details.required。
def profile_details_required(profile_schema)
  profile_schema.fetch("allOf").each do |part|
    next unless part.is_a?(Hash)

    required = part.dig("properties", "profile_details", "required")
    return required.to_a if required
  end
  []
end
