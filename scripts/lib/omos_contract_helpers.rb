# frozen_string_literal: true
#
# 跨所有 OMOS 契約 validator 共用的最小 helper。
#
# 只放「目前每個 validator 都逐字相同」的部分:duplicate-key fail-closed 的
# JSON / YAML 讀取基礎元件,以及 present? 判斷。
#
# 刻意不放:
#   - read_json / read_yaml —— STD-01/02/03 用 (path, failures) 變體(collect
#     failures + rescue),其餘用 (path);兩者行為不同,各自留在檔內。
#   - assert —— STD-01/02 用 (condition, code, message, failures)(code: prefix),
#     其餘用 (condition, message, failures);arity 不同,各自留在檔內。
#   - sorted_set —— personal-memory 用 Set、AIWR 用 sorted Array;各自留在檔內。

require "json"
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
