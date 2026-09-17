#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SSP-294 切片 A：promotion widening gate 的強制。
#
# 研究發現（見 .work/CARD-SSP294A-PROMOTION-GATE-20260917.md）：
# personal-harness-integration.yaml 早就宣告了完整的 promotion_widening_gate
# （6 個 required ＋ 3 個 forbidden），但實際只有一條斷言驗到
# 「required 清單裡要有 reviewer_approval」——其餘 5 個 required 與全部 3 個
# forbidden 從來沒有任何 evaluator 會攔。本檔補上這件事。
#
# 關鍵設計：**gate 的組成不在本檔重述**，evaluation 時從上游讀。上游若新增一個
# required 條件，沒滿足它的 run 會立刻開始被擋，本檔一行都不用改。這是本 repo
# 反覆被咬過的教訓——兩份手寫清單一定會漂。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/emem-promotion-gate.yaml")
UPSTREAM_SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/emem-promotion-gate-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/emem-promotion-gate-negative-fixtures.json")

OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze
EXPECTED_OUTCOMES = %w[PROMOTED DENIED].freeze

EXPECTED_NEGATIVE_LABELS = [
  "an outcome outside the declared enum",
  "a promotion missing a condition the upstream gate requires",
  "a promotion whose condition receipt is not an omos URN",
  "a promotion naming a condition the upstream gate does not declare",
  "a promotion declaring a path the upstream gate forbids",
  "a promotion declaring a forbidden path while satisfying every required condition",
  "a promotion whose satisfied_conditions is not a condition-to-receipt map"
].freeze

def urn?(value)
  value.is_a?(String) && OMOS_URN.match?(value)
end

# gate 是從上游讀進來的 hash（required / forbidden），不是本檔宣告的常數。
def promotion_gate_failure(gate, run)
  required = gate.fetch("required", [])
  forbidden = gate.fetch("forbidden", [])

  return "PROMOTION_INVALID_OUTCOME" unless EXPECTED_OUTCOMES.include?(run["outcome"])

  # forbidden 先驗：宣告了禁止路徑就不可能被 approvals 贖回，不管 outcome 是什麼。
  declared_paths = run["declared_paths"].to_a
  return "PROMOTION_FORBIDDEN_PATH_DECLARED" if declared_paths.any? { |path| forbidden.include?(path) }

  # DENIED 不需要滿足 gate——被擋下來的升格本來就不必備齊條件。
  return nil unless run["outcome"] == "PROMOTED"

  satisfied = run["satisfied_conditions"]
  return "PROMOTION_GATE_CONDITION_UNSATISFIED" unless satisfied.is_a?(Hash)

  # 宣告了上游沒有的條件 = 這份 run 對著一個本 repo 不認得的 gate 說話。
  unknown = satisfied.keys - required
  return "PROMOTION_UNKNOWN_GATE_CONDITION" unless unknown.empty?

  missing = required - satisfied.keys
  return "PROMOTION_GATE_CONDITION_UNSATISFIED" unless missing.empty?

  return "PROMOTION_CONDITION_RECEIPT_NOT_REF" unless satisfied.values.all? { |ref| urn?(ref) }

  nil
end

# --- 契約結構斷言 ---------------------------------------------------------

failures = []
spec = read_yaml(SPEC_PATH)
upstream = read_yaml(UPSTREAM_SPEC_PATH)

assert(spec.dig("purpose", "no_second_workflow_authority") == true,
       "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec.dig("authority", "grants_acceptance") == false, "authority.grants_acceptance 必須為 false", failures)
assert(spec.dig("authority", "grants_permission") == false, "authority.grants_permission 必須為 false", failures)
assert(spec.dig("authority", "grants_canonical_writer") == false,
       "authority.grants_canonical_writer 必須為 false", failures)
assert(spec.dig("authority", "error_behavior") == "FAIL_LOUD", "authority.error_behavior 必須為 FAIL_LOUD", failures)
assert(spec.dig("provenance_boundary", "does_not_verify") == "THE_REFERENCED_RECEIPTS_ARE_AUTHENTIC",
       "provenance_boundary 必須明寫不驗證 receipt 真實性", failures)

# 綁定上游：gate_ref 必須真的能在 personal-harness-integration.yaml 裡 resolve 出東西。
gate_ref = spec.dig("widening_gate_binding", "gate_ref").to_s
prefix = "personal-harness-integration."
assert(gate_ref.start_with?(prefix), "widening_gate_binding.gate_ref 必須指向 personal-harness-integration", failures)
gate_segments = gate_ref.start_with?(prefix) ? gate_ref[prefix.length..].to_s.split(".", -1) : []
assert(!gate_segments.empty? && gate_segments.none?(&:empty?),
       "widening_gate_binding.gate_ref 的路徑片段不得為空（尾端多餘的 '.'？）", failures)
gate = gate_segments.empty? ? nil : upstream.dig(*gate_segments)
assert(gate.is_a?(Hash), "widening_gate_binding.gate_ref 必須能在上游 resolve 出一個 gate 定義：#{gate_ref}", failures)
gate ||= {}

assert(gate.fetch("required", []).any?, "上游 gate 的 required 不得為空（結構已改變？）", failures)
assert(gate.fetch("forbidden", []).any?, "上游 gate 的 forbidden 不得為空（結構已改變？）", failures)

# 本檔不得重述上游清單——出現任何一個 required／forbidden 字面值就是在複製。
spec_text = File.read(SPEC_PATH)
copied = (gate.fetch("required", []) + gate.fetch("forbidden", [])).select do |item|
  spec_text.include?(item) && !spec_text.include?("#{item} ->")
end
assert(copied.empty?,
       "本契約不得重述上游 gate 的條件名稱（會漂）：#{copied.join(', ')}", failures)

# --- error_contract 與 evaluator 實際可達 code 綁定 ------------------------

declared_codes = spec.fetch("error_contract").keys
violations = LoopReturnContract.exit_shape_violations(__FILE__, "promotion_gate_failure")
assert(violations.empty?, "promotion_gate_failure 有不合契約的 return 形式：#{violations.inspect}", failures)
reachable = LoopReturnContract.reachable_codes(__FILE__, "promotion_gate_failure")
assert((reachable - declared_codes).empty?,
       "evaluator 會回傳但 error_contract 未宣告：#{(reachable - declared_codes).sort.inspect}", failures)
assert((declared_codes - reachable).empty?,
       "error_contract 宣告但 evaluator 不可能回傳：#{(declared_codes - reachable).sort.inspect}", failures)

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)
  actual = promotion_gate_failure(gate, test_case.fetch("run"))
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  assert(declared_codes.include?(expected_code),
         "#{case_id} 的 expected_failure_code #{expected_code} 未在 error_contract 宣告", failures)
  actual = promotion_gate_failure(gate, test_case.fetch("run"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 #{expected_code}，實際 #{actual.inspect}", failures)
end

covered = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(', ')}", failures)

if failures.empty?
  puts "PASS emem promotion gate contract validation " \
       "(required=#{gate.fetch('required', []).size}, forbidden=#{gate.fetch('forbidden', []).size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
