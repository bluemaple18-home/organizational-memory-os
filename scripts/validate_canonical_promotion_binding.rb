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
  "personal-harness-integration.yaml#core_pipeline" =>
    "FINDING F-01（repo #5 稽核，2026-09-16）：core_pipeline 自行宣告 10 步流程，" \
    "其中含 canonical 尾段（CANDIDATE → VERIFICATION → PERSONAL_ACCEPTANCE → RECORD），" \
    "未 pointer-bind 回 boundary，且無任何 validator 讀取它。" \
    "目前順序與上游一致、非現行繞過路徑；處置權依 FP-3-A 在 Owner。"
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

failures = []
steps = canonical_steps
seen_keys = Set.new

Dir[SPEC_GLOB].sort.each do |spec_path|
  basename = File.basename(spec_path)
  next if basename == File.basename(BOUNDARY_SPEC_PATH) # 上游自己不算重述

  raw = File.read(spec_path)
  spec = read_yaml(spec_path)
  bound = raw.include?(BOUNDARY_POINTER)

  restatements_in(spec, steps).each do |path, array|
    key = "#{basename}##{path}"
    seen_keys << key
    next if bound # 契約有指回上游，視為已綁定
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
