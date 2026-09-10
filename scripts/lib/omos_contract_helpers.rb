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

require "time"

# --- Jira Adapter Mapping validator 共用 helper（純函式）。---

def deep_dup(obj)
  case obj
  when Hash then obj.each_with_object({}) { |(key, value), acc| acc[key] = deep_dup(value) }
  when Array then obj.map { |value| deep_dup(value) }
  else obj
  end
end

def set_path(root, path, value)
  segments = path.split("/")
  leaf = segments.pop
  node = segments.inject(root) { |acc, seg| acc.is_a?(Hash) ? acc[seg] : nil }
  node[leaf] = value if node.is_a?(Hash)
end

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
