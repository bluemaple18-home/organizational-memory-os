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
def derivation_binding_failures(inputs, raw, anchor)
  cd = inputs["content_digest"]
  tenant = inputs["tenant_id"]
  idem = "sha256:" + Digest::SHA256.hexdigest(canonical_json("content_digest" => cd, "tenant_id" => tenant))
  {
    "native_id" => raw.dig("source_identity", "native_id") == cd,
    "tenant_id" => raw["tenant_id"] == tenant,
    "source_version_value" => raw.dig("source_version", "value").nil? && anchor.dig("source_version", "value").nil?,
    "source_version_secondary_digest" => raw.dig("source_version", "secondary_digest") == cd &&
                                         anchor.dig("source_version", "secondary_digest") == cd,
    "raw_digest" => raw.dig("digests", "raw_digest") == cd,
    "canonical_digest" => raw.dig("digests", "canonical_digest").nil?,
    "normalized_digest" => present?(raw.dig("digests", "normalized_digest")) &&
                           raw.dig("digests", "normalized_digest") == anchor.dig("representation", "representation_digest"),
    "adapter_id" => raw.dig("provenance", "adapter_id") == inputs["adapter_id"],
    "adapter_version" => raw.dig("provenance", "adapter_version") == inputs["adapter_version"],
    "anchor_source_identity" => raw["source_identity"] == anchor["source_identity"],
    "anchor_identity_content_bound" => anchor.dig("source_identity", "native_id") == cd &&
                                       anchor.dig("source_identity", "source_system") == "document" &&
                                       anchor.dig("source_identity", "entity_type") == raw.dig("source_identity", "entity_type"),
    "idempotency_key" => raw["idempotency_key"] == idem
  }.reject { |_, ok| ok }.keys
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
