#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SSP-294 切片 B：actor × 材料類別的升格決策表重放。
#
# 上游 personal-harness-integration.yaml 宣告了 15 個決策格（5 actor × 3 材料
# 類別），每格帶 decision 與（CONDITIONAL 時的）required_conditions。實際被驗
# 到的只有 MANAGER/COMPANY_MANAGED_PERSONAL 那一格的 3 條條件——其餘 14 格的
# decision 與條件從來沒有任何 evaluator 會攔。本檔補上。
#
# 表本身不在此重述：actor／類別／decision／條件全部在 evaluation 時從上游讀。
# 另有 fixture 覆蓋斷言——上游新增一格而沒人測，gate 立刻轉紅。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/emem-promotion-policy.yaml")
UPSTREAM_SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/emem-promotion-policy-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/emem-promotion-policy-negative-fixtures.json")

OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze
EXPECTED_OUTCOMES = %w[PROMOTED DENIED].freeze
EXPECTED_DECISIONS = %w[CONDITIONAL DENY].freeze

EXPECTED_NEGATIVE_LABELS = [
  "a run naming an actor the upstream table does not declare",
  "a run naming a material class the cell table does not declare",
  "an outcome outside the declared enum",
  "a promotion against a cell the table marks DENY",
  "a promotion whose satisfied_conditions is not a map",
  "a promotion missing a condition the cell requires",
  "a promotion naming a condition the cell does not require",
  "a promotion whose condition receipt is not an omos URN",
  "a cell whose decision value the contract does not recognise",
  "a cell whose required_conditions is not a list"
].freeze

def urn?(value)
  value.is_a?(String) && OMOS_URN.match?(value)
end

# policy 是上游讀進來的 PROMOTE 子表（actor -> class -> cell），非本檔常數。
def promotion_decision_failure(policy, run)
  actor_cells = policy[run["actor"]]
  return "POLICY_UNKNOWN_ACTOR" unless actor_cells.is_a?(Hash)

  cell = actor_cells[run["material_class"]]
  return "POLICY_UNKNOWN_MATERIAL_CLASS" unless cell.is_a?(Hash)

  return "POLICY_INVALID_OUTCOME" unless EXPECTED_OUTCOMES.include?(run["outcome"])

  decision = cell["decision"]
  return "POLICY_UNKNOWN_DECISION" unless EXPECTED_DECISIONS.include?(decision)

  # DENY 格：該 actor 對該類別根本沒有這個動作，帶什麼條件都不能升格。
  return "POLICY_DENIED_CELL_PROMOTED" if decision == "DENY" && run["outcome"] == "PROMOTED"

  # 拒絕升格永遠不需要理由；只有宣稱升格成功才要對條件負責。
  return nil unless run["outcome"] == "PROMOTED"

  # 刻意不做 .to_a／.to_h 之類的寬容轉型——那正是切片 A 被打穿的形狀
  # （格式錯誤被默默圓成「合法但空的」，等於檢查沒跑）。
  satisfied = run["satisfied_conditions"]
  return "POLICY_CONDITIONS_NOT_MAP" unless satisfied.is_a?(Hash)

  required = cell["required_conditions"]
  return "POLICY_CONDITIONS_NOT_MAP" unless required.is_a?(Array)

  unknown = satisfied.keys - required
  return "POLICY_UNKNOWN_CONDITION" unless unknown.empty?

  missing = required - satisfied.keys
  return "POLICY_CONDITION_UNSATISFIED" unless missing.empty?

  return "POLICY_CONDITION_RECEIPT_NOT_REF" unless satisfied.values.all? { |ref| urn?(ref) }

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

EXPECTED_BOUNDARY_ADMISSIONS = %w[
  THE_REFERENCED_RECEIPTS_ARE_AUTHENTIC
  THE_DECLARED_ACTOR_IS_THE_REAL_ACTOR
].freeze
admissions = spec.dig("provenance_boundary", "does_not_verify")
assert(admissions.is_a?(Array) && sorted_set(admissions) == sorted_set(EXPECTED_BOUNDARY_ADMISSIONS),
       "provenance_boundary.does_not_verify 必須列出本層驗不了的兩件事：" \
       "#{EXPECTED_BOUNDARY_ADMISSIONS.inspect}，實際 #{admissions.inspect}", failures)

# 綁定上游：policy_ref 必須真的 resolve 得到，且路徑片段不得為空
# （尾端多一個 '.' 會被 split 吃掉——repo #5 已經踩過這個）。
policy_ref = spec.dig("decision_table_binding", "policy_ref").to_s
prefix = "personal-harness-integration."
assert(policy_ref.start_with?(prefix), "decision_table_binding.policy_ref 必須指向 personal-harness-integration", failures)
segments = policy_ref.start_with?(prefix) ? policy_ref[prefix.length..].to_s.split(".", -1) : []
assert(!segments.empty? && segments.none?(&:empty?),
       "decision_table_binding.policy_ref 的路徑片段不得為空（尾端多餘的 '.'？）", failures)
action = spec.dig("decision_table_binding", "action").to_s
assert(!action.empty?, "decision_table_binding.action 不得為空", failures)

actor_action_policy = segments.empty? ? nil : upstream.dig(*segments)
assert(actor_action_policy.is_a?(Hash),
       "decision_table_binding.policy_ref 必須能在上游 resolve 出決策表：#{policy_ref}", failures)
actor_action_policy ||= {}

# 抽出 PROMOTE 子表：actor -> material_class -> cell
policy = {}
actor_action_policy.each do |actor, actions|
  next unless actions.is_a?(Hash)

  cells = actions[action]
  policy[actor] = cells if cells.is_a?(Hash)
end
assert(!policy.empty?, "上游找不到任何 #{action} 決策格（結構已改變？）", failures)

declared_cells = policy.flat_map { |actor, cells| cells.keys.map { |klass| "#{actor}/#{klass}" } }
assert(declared_cells.size >= 2, "決策格數異常少（#{declared_cells.size}），上游結構可能已改變", failures)

# 本契約不得重述上游的 actor／類別／條件名稱。
spec_text = File.read(SPEC_PATH)
upstream_names = (policy.keys + policy.values.flat_map(&:keys) +
                  policy.values.flat_map { |cells| cells.values.flat_map { |c| c["required_conditions"].to_a } }).uniq
copied = upstream_names.select { |name| spec_text.include?(name) }
assert(copied.empty?, "本契約不得重述上游決策表的名稱（會漂）：#{copied.sort.join(', ')}", failures)

# --- error_contract 與 evaluator 可達 code 綁定 ---------------------------

declared_codes = spec.fetch("error_contract").keys
violations = LoopReturnContract.exit_shape_violations(__FILE__, "promotion_decision_failure")
assert(violations.empty?, "promotion_decision_failure 有不合契約的 return 形式：#{violations.inspect}", failures)
reachable = LoopReturnContract.reachable_codes(__FILE__, "promotion_decision_failure")
assert((reachable - declared_codes).empty?,
       "evaluator 會回傳但 error_contract 未宣告：#{(reachable - declared_codes).sort.inspect}", failures)
assert((declared_codes - reachable).empty?,
       "error_contract 宣告但 evaluator 不可能回傳：#{(declared_codes - reachable).sort.inspect}", failures)

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

# 少數 guard 無法用健康的上游資料產生（例如 decision 是無法辨識的值——上游若
# 打錯字，沒有這道 guard 就會被當成寬鬆分支放行）。這類 case 可自帶 policy；
# 沒有自帶的一律對真實上游表評估，那才是正常路徑。
def policy_for(test_case, upstream_policy)
  override = test_case["policy"]
  override.is_a?(Hash) ? override : upstream_policy
end

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)
  actual = promotion_decision_failure(policy_for(test_case, policy), test_case.fetch("run"))
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  assert(declared_codes.include?(expected_code),
         "#{case_id} 的 expected_failure_code #{expected_code} 未在 error_contract 宣告", failures)
  actual = promotion_decision_failure(policy_for(test_case, policy), test_case.fetch("run"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 #{expected_code}，實際 #{actual.inspect}", failures)
end

covered_labels = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(', ')}", failures)

# 覆蓋斷言：上游每一格都必須被至少一個 fixture 踩過。上游新增一格而沒人測，
# 這裡立刻紅——避免決策格又回到「宣告了但沒人驗」的原始狀態。
# 覆蓋斷言是「決策感知」的：光是踩過那一格還不夠，必須踩到**與該格 decision
# 相符的那條路徑**——CONDITIONAL 格要有成功升格的正例（才會真的去驗條件），
# DENY 格要有被拒的正例。否則上游把某格從 DENY 翻成 CONDITIONAL，原本的
# DENIED 正例照樣通過，治理上的放寬就沒有人發現。
real_cases = (positive_fixtures.fetch("cases") + negative_cases).reject { |c| c["policy"].is_a?(Hash) }
promoted_cells = real_cases.select { |c| c.dig("run", "outcome") == "PROMOTED" }
                           .map { |c| "#{c.dig('run', 'actor')}/#{c.dig('run', 'material_class')}" }.uniq
denied_cells = real_cases.select { |c| c.dig("run", "outcome") == "DENIED" }
                         .map { |c| "#{c.dig('run', 'actor')}/#{c.dig('run', 'material_class')}" }.uniq

policy.each do |actor, cells|
  cells.each do |klass, cell|
    key = "#{actor}/#{klass}"
    case cell["decision"]
    when "CONDITIONAL"
      assert(promoted_cells.include?(key),
             "CONDITIONAL 格 #{key} 缺少成功升格的 fixture——條件因此從未被驗", failures)
    when "DENY"
      assert(denied_cells.include?(key),
             "DENY 格 #{key} 缺少被拒的 fixture", failures)
    end
  end
end

if failures.empty?
  puts "PASS emem promotion policy contract validation (cells=#{declared_cells.size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
