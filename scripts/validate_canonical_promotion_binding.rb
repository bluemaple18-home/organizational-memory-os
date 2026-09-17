#!/usr/bin/env ruby
# frozen_string_literal: true
#
# repo #5 Canonical Direct-Write Audit 的常設防線（Owner 簽 FP-4-B）。
#
# 判準（Owner 簽 FP-2-A）：`ai-work-record-boundary.yaml` 的
# `promotion_path` 是 canonical 升格路徑的**唯一**權威。任何契約若自行宣告
# 一段包含 canonical 步驟名稱的順序，就是在重述這個權威——重述本身不一定
# 錯，但必須 pointer-bind 回上游，否則兩邊會各自演化而沒有人發現。
#
# 本檔把「有沒有人重述而未綁定」變成常設 gate：
#   1. 從 boundary 讀出 canonical 步驟詞彙（不硬編）。
#   2. 走遍 規格/v0.1/*.yaml，找出所有「元素與 canonical 步驟重疊 >= 2 個」
#      的陣列——那就是在描述同一條路徑的順序。
#   3. 每個這種陣列所屬的契約，必須在檔案裡帶一個指回
#      ai-work-record-boundary.promotion_path 的 pointer；否則必須列在下方
#      KNOWN_UNBOUND 並附理由。
#   4. KNOWN_UNBOUND 的項目若已不存在，也要紅——避免例外清單變成殭屍。
#
# KNOWN_UNBOUND 目前只有稽核當下發現的 F-01。依 Owner 簽的 FP-3-A，CC 只
# 產出 findings、不自行修，所以它以「已登記、待 Owner 裁決」的形式留在這裡，
# 而不是被默默修掉或默默放行。
#
# repair-01 起，KNOWN_UNBOUND **只**豁免「缺 pointer」這一項。step 跳步、
# 順序顛倒、規則被放寬，一律照驗照紅——例外清單不得成為變相放行。

require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
BOUNDARY_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-boundary.yaml")
SPEC_GLOB = File.join(ROOT, "規格/v0.1/*.yaml")
BOUNDARY_POINTER = "ai-work-record-boundary.promotion_path"
OVERLAP_THRESHOLD = 2

# 稽核當下已登記的未綁定重述。每一筆都必須附 finding 編號與理由。
# 新增任何一筆都代表「又多了一條沒綁的路徑」，應該先問為什麼，而不是往這裡加。
KNOWN_UNBOUND = {
  # repo #5 稽核 F-01 原本登記在此（personal-harness-integration.yaml#core_pipeline）。
  # 2026-09-17 Owner 裁決：不長期停留在例外清單。該契約已加上
  # core_pipeline_promotion_binding 明確指回上游，並由
  # validate_ai_work_record_boundary_contract.rb 斷言 covers 與上游一致
  # （含孤兒步驟檢查），例外因此移除。
  #
  # 這裡保持空的才是正常狀態。要往裡面加任何一筆，代表又出現一條沒綁的
  # canonical 路徑重述——先問為什麼，不要先加例外。
}.freeze

def canonical_steps
  boundary = read_yaml(BOUNDARY_SPEC_PATH)
  steps = boundary.dig("promotion_path", "ordered_steps")
  raise "在 boundary 找不到 promotion_path.ordered_steps（上游結構已改變？）" unless steps.is_a?(Array) && !steps.empty?

  steps
end

# 走訪 YAML 樹，回傳 [路徑字串, 陣列] 的清單。
def each_array(node, path, acc)
  case node
  when Hash
    node.each { |key, value| each_array(value, path.empty? ? key.to_s : "#{path}.#{key}", acc) }
  when Array
    acc << [path, node]
    node.each_with_index { |item, index| each_array(item, "#{path}[#{index}]", acc) }
  end
  acc
end

def restatements_in(spec, steps)
  each_array(spec, "", []).select do |_path, array|
    overlap = array.select { |item| item.is_a?(String) && steps.include?(item) }
    overlap.size >= OVERLAP_THRESHOLD
  end
end

# repair-01（big review P1）：原本只驗「有沒有綁」，不驗「綁的內容有沒有被
# 弱化」——有 pointer 就整份放行，登記在 KNOWN_UNBOUND 就整條放行。於是把
# VERIFICATION 從 core_pipeline 刪掉、或新增一份帶正確 pointer 但只有
# CANDIDATE → RECORD 的契約，gate 都照樣 PASS。那是變相放行。
#
# 以下改為對每一條 restatement 做語意比對。KNOWN_UNBOUND 現在**只**豁免
# 「缺 pointer」這一項，永遠不豁免 step／order／rule 的漂移。

# 回傳弱化描述字串；沒有弱化則回傳 nil。
def weakening_in_sequence(array, steps)
  present = array.select { |item| item.is_a?(String) && steps.include?(item) }
  indices = present.map { |step| steps.index(step) }

  # 順序必須與上游一致（上游 steps_out_of_order: forbidden）。
  unless indices == indices.sort
    return "步驟順序與上游不一致（#{present.join(' → ')}）；上游為 #{steps.join(' → ')}"
  end

  # 涵蓋區間內不得跳步（上游 skip_any_step: forbidden）。只檢查這條 restatement
  # 自己涵蓋的範圍——它可以只描述尾段，但不能在尾段中間挖掉一步。
  span = (indices.first..indices.last).to_a
  missing = span - indices
  return nil if missing.empty?

  "涵蓋 #{steps[indices.first]} → #{steps[indices.last]} 但跳過了 " \
  "#{missing.map { |i| steps[i] }.join(' / ')}（上游 skip_any_step: forbidden）"
end

# 下游不得重新定義上游的 rules；同名 key 的值必須與上游相同。
def weakened_rules(spec, upstream_rules)
  found = []
  walk = lambda do |node, path|
    case node
    when Hash
      node.each do |key, value|
        key_path = path.empty? ? key.to_s : "#{path}.#{key}"
        if upstream_rules.key?(key.to_s) && !value.is_a?(Hash) && !value.is_a?(Array)
          upstream_value = upstream_rules.fetch(key.to_s)
          unless value == upstream_value
            found << "#{key_path} = #{value.inspect}，與上游 promotion_path.rules.#{key} " \
                     "= #{upstream_value.inspect} 不一致（下游不得重新定義上游規則）"
          end
        end
        walk.call(value, key_path)
      end
    when Array
      node.each_with_index { |item, index| walk.call(item, "#{path}[#{index}]") }
    end
  end
  walk.call(spec, "")
  found
end

# repair-02（CC 自檢）：原本用「整份檔案文字裡有沒有出現 pointer 字串」判定
# 已綁定——散文裡提一句就算數。於是把 promotion_path_ref 改成 none、只靠下方
# rule 說明文字裡的那串字，仍會被當成已綁定。那又是「驗存在、不驗實質」。
#
# 改成只認**結構化欄位的值**：某個 scalar 的值本身就是 pointer（或其點號延伸），
# 才算綁定。散文因為前後有句子，整值比對不會命中。
def bound_to_upstream?(node)
  case node
  when Hash then node.any? { |_key, value| bound_to_upstream?(value) }
  when Array then node.any? { |item| bound_to_upstream?(item) }
  when String then /\A#{Regexp.escape(BOUNDARY_POINTER)}[\w.]*\z/.match?(node.strip)
  else false
  end
end

failures = []
steps = canonical_steps
upstream_rules = read_yaml(BOUNDARY_SPEC_PATH).dig("promotion_path", "rules") || {}
seen_keys = Set.new

Dir[SPEC_GLOB].sort.each do |spec_path|
  basename = File.basename(spec_path)
  next if basename == File.basename(BOUNDARY_SPEC_PATH) # 上游自己不算重述

  spec = read_yaml(spec_path)
  bound = bound_to_upstream?(spec)

  # 規則弱化與有沒有 pointer 無關，先驗——這是 FP-2-A 的「不得放寬 forbidden」。
  weakened_rules(spec, upstream_rules).each do |detail|
    failures << "#{basename} 弱化了上游規則：#{detail}"
  end

  restatements_in(spec, steps).each do |path, array|
    key = "#{basename}##{path}"
    seen_keys << key

    # (1) 語意比對：不論有沒有 pointer、不論有沒有登記例外，都必須跑。
    #     KNOWN_UNBOUND 只豁免「缺 pointer」，不豁免內容漂移。
    weakening = weakening_in_sequence(array, steps)
    failures << "#{key} 弱化了 canonical 升格路徑：#{weakening}" if weakening

    # (2) 綁定檢查：有 pointer 或已登記例外才放過。
    next if bound
    next if KNOWN_UNBOUND.key?(key)

    overlap = array.select { |item| item.is_a?(String) && steps.include?(item) }
    failures << "#{key} 宣告了包含 canonical 步驟的順序（#{overlap.join(' / ')}），" \
                "但整份契約沒有指回 #{BOUNDARY_POINTER} 的 pointer，也未登記在 KNOWN_UNBOUND。"
  end
end

# 例外清單不得留殭屍：登記的項目必須真的還存在。
KNOWN_UNBOUND.each_key do |key|
  next if seen_keys.include?(key)

  failures << "KNOWN_UNBOUND 登記的 #{key} 已不存在（重述已移除或改名？），請一併移除此例外。"
end

if failures.empty?
  puts "PASS canonical promotion binding validation " \
       "(canonical steps=#{steps.size}, known unbound=#{KNOWN_UNBOUND.size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
