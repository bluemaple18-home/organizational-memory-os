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
