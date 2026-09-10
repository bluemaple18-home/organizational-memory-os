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
require "time"

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

# path segment 導航：Hash 用 key，Array 用十進位索引。
def navigate_segment(node, segment)
  case node
  when Hash then node[segment]
  when Array then /\A\d+\z/.match?(segment) ? node[segment.to_i] : nil
  end
end

def dig_parent(root, path)
  segments = path.split("/")
  leaf = segments.pop
  [segments.inject(root) { |acc, seg| navigate_segment(acc, seg) }, leaf]
end

def read_path(root, path)
  path.split("/").inject(root) { |acc, seg| navigate_segment(acc, seg) }
end

# 支援 "*" 萬用段（展開 Array 的每個元素），例如 blocks/*/quality。
def delete_path(root, path)
  segments = path.split("/")
  star = segments.index("*")
  if star
    node = segments[0...star].inject(root) { |acc, seg| navigate_segment(acc, seg) }
    rest = segments[(star + 1)..].join("/")
    node.each { |item| delete_path(item, rest) } if node.is_a?(Array)
    return
  end

  node, leaf = dig_parent(root, path)
  node.delete(leaf) if node.is_a?(Hash)
end

def set_path(root, path, value)
  node, leaf = dig_parent(root, path)
  case node
  when Hash then node[leaf] = value
  when Array then node[leaf.to_i] = value if /\A\d+\z/.match?(leaf)
  end
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
# FP-3（Owner 簽定）：契約只保留這一份權威分類。對 {raw_evidence, source_anchor, blocks} 的
# 每條路徑，在此清單內 = RUN_SCOPED，否則 = DETERMINISTIC。reconstruction、
# deterministic_projection_digest、normalized_document_digest 全部由它推導，不得另立清單。
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
  source_anchor/representation/source_payload_ref source_anchor/representation/source_payload_digest
  source_anchor/representation/representation_ref
  source_anchor/profile_details/page source_anchor/profile_details/page_number_basis
  source_anchor/profile_details/bbox source_anchor/profile_details/block_id
  source_anchor/profile_details/char_range source_anchor/profile_details/char_representation_ref
  source_anchor/profile_details/codepoint_range source_anchor/profile_details/line_range
  source_anchor/profile_details/line_number_basis source_anchor/profile_details/heading_path
  source_anchor/profile_details/selected_text
  blocks/*/block_id blocks/*/parent_id blocks/*/source_anchor_refs blocks/*/quality
].freeze
# profile_details 是逐子欄位分類（不是整個 subtree run-scoped），因此
# char_representation_digest 依單一規則就是 DETERMINISTIC，不需要任何特例。
DOC_MAP_DETERMINISTIC_PROFILE_DETAILS_KEYS = %w[char_representation_digest].freeze

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
      # profile_details 逐子欄位分類後，PDF 只剩 char_representation_digest 屬 deterministic；
      # MARKDOWN 的子欄位全部 run-scoped，故剩空物件。
      "profile_details" => (kind == "PDF" ? { "char_representation_digest" => nrd } : {}),
      "normalization_profile" => "OMOS_TEXT_NORM_V1"
    }
  }
end

# 一份 block 清單去掉 per-run 欄位後的 deterministic surface。
# FP-3 的分類函式：路徑落在任一 run-scoped pattern（含其子樹）之下即為 RUN_SCOPED。
def run_scoped_path?(path)
  segments = path.split("/")
  DOC_MAP_RUN_SCOPED_PATHS.any? do |pattern|
    expected = pattern.split("/")
    expected.length <= segments.length &&
      expected.each_with_index.all? { |seg, index| seg == "*" || seg == segments[index] }
  end
end

# 唯一的 surface 推導：整份 projection 去掉 DOC_MAP_RUN_SCOPED_PATHS 後就是 deterministic
# surface。以下所有 digest / 比對都只由它推導（FP-3）。
def deterministic_surface(triple)
  surface = deep_dup(triple)
  DOC_MAP_RUN_SCOPED_PATHS.each { |path| delete_path(surface, path) }
  surface
end

# FP-2：deterministic_projection_digest 只 hash deterministic surface，因此 run-scoped
# 欄位在構造上不可能改變它。
def deterministic_projection_digest(triple)
  "sha256:" + Digest::SHA256.hexdigest(canonical_json(deterministic_surface(triple)))
end

# deterministic block surface 的 canonical SHA256（第 7 個 declared input 綁定對象）。
def normalized_document_digest(triple)
  "sha256:" + Digest::SHA256.hexdigest(canonical_json(deterministic_surface(triple)["blocks"].to_a))
end

# deterministic surface 逐鍵與「只由 inputs 重建」的結果比對。回傳不符（含未分類欄位、
# block-set digest 不符、block content_sha256 不一致）的路徑清單。
def deterministic_surface_mismatches(kind, inputs, triple)
  surface = deterministic_surface(triple)
  identity_surface = { "raw_evidence" => surface["raw_evidence"], "source_anchor" => surface["source_anchor"] }
  problems = diff_paths(reconstruct_deterministic_projection(kind, inputs), identity_surface, "")

  observed_ndd = normalized_document_digest(triple)
  unless observed_ndd == inputs["normalized_document_digest"]
    problems << "blocks/normalized_document_digest (expected #{inputs["normalized_document_digest"].inspect}, " \
                "got #{observed_ndd.inspect})"
  end
  triple["blocks"].to_a.each_with_index do |block, index|
    expected_sha = "sha256:" + Digest::SHA256.hexdigest(block["content"].to_s)
    problems << "blocks/#{index}/content_sha256 (expected #{expected_sha}, got #{block["content_sha256"].inspect})" unless
      block["content_sha256"] == expected_sha
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

# --- Jira Adapter Mapping validator 共用 helper（純函式）。---

# RFC3339 timestamp -> Time，parse 失敗回 nil（用真正 parse 比較，不用字串比較）。
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

# 一個 supplied reconciliation version 物件的 fail-closed 驗（型別 / RFC3339 value /
# locked sha256 secondary_digest）。回傳 machine failure code 或 nil。
SHA256_LOCKED_PATTERN = /\Asha256:[0-9a-f]{64}\z/.freeze
def reconciliation_version_problem(node)
  return "JIRA_MAP_RECONCILIATION_VERSION_UNPARSEABLE" unless node.is_a?(Hash)
  return "JIRA_MAP_RECONCILIATION_VERSION_UNPARSEABLE" if parse_instant(node["value"]).nil?
  return "JIRA_MAP_RECONCILIATION_VERSION_DIGEST_MALFORMED" unless node["secondary_digest"].is_a?(String) &&
                                                                  SHA256_LOCKED_PATTERN.match?(node["secondary_digest"])

  nil
end

# F-01-F03-R02：compact projection 與完整 STD instance 不得脫鉤。逐項比對 mapping-critical
# 欄位（含 (cloud_id, issue_id) end-to-end identity binding），回傳未通過的欄位名稱。
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
  problems << "projected native_id_basis" unless projection.dig("raw_evidence", "source_identity", "native_id_basis") == "JIRA_CLOUD_ID_PLUS_ISSUE_ID"

  # Jira stable identity = (cloud_id, issue_id)：source_instance_id 即 cloud_id、native_id 即 issue_id。
  { "raw_evidence" => raw_instance, "source_anchor" => anchor_instance }.each do |name, doc|
    si = doc["source_identity"] || {}
    problems << "#{name}.source_identity.source_system" unless si["source_system"] == "jira-cloud"
    problems << "#{name}.source_identity.source_instance_id == cloud_id" unless si["source_instance_id"] == inst_details["cloud_id"]
    problems << "#{name}.source_identity.entity_type == issue" unless si["entity_type"] == "issue"
    problems << "#{name}.source_identity.native_id == issue_id" unless si["native_id"] == inst_details["issue_id"]
  end
  problems << "raw_evidence.source_identity == source_anchor.source_identity" unless raw_instance["source_identity"] == anchor_instance["source_identity"]

  reconciliation = projection["reconciliation"]
  if reconciliation.is_a?(Hash) && reconciliation["current_identity"].is_a?(Hash)
    current = reconciliation["current_identity"]
    unless current["cloud_id"] == inst_details["cloud_id"] && current["issue_id"] == inst_details["issue_id"]
      problems << "reconciliation.current_identity == instance identity"
    end
  end

  problems
end
