#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SSP-294 切片 C：source ACL ceiling 的強制（Owner 簽 FP-1-A / FP-2-A / FP-3-A）。
#
# 上游宣告「source ACL 是天花板，個人記憶可收窄不可放寬，除非過 promotion
# gate」，並列出 3 個 required_receipts；三個 visibility scope 也都宣告
# widening_requires_promotion_gate: true。但目前唯一的檢查是
# validate_personal_memory_scope_contract.rb:137——斷言**規則的敘述文字裡含有
# "cannot widen"**。那句話在不在文字裡，跟有沒有真的擋住是兩回事。
#
# FP-2-A：本檔治理的是 actor_action_policy.PROMOTE（可見範圍放寬），**不是**
# ai-work-record-boundary.promotion_path（證據→個人記憶的 6 步鏈）。兩者同名
# 不同物，不得互相套用。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/emem-scope-ceiling.yaml")
UPSTREAM_SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/emem-scope-ceiling-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/emem-scope-ceiling-negative-fixtures.json")

OMOS_URN = /\Aurn:omos:[a-z0-9-]+:.+\z/.freeze
EXPECTED_OUTCOMES = %w[APPLIED REFUSED].freeze

EXPECTED_NEGATIVE_LABELS = [
  "a change naming a scope the upstream contract does not declare",
  "an outcome outside the declared enum",
  "a change whose receipts field is not a map",
  "a widening missing a receipt the ceiling requires",
  "a widening whose receipt is not an omos URN",
  "a widening naming a receipt the ceiling does not require",
  "a widening with no promotion gate reference",
  "a move between incomparable scopes with no gate reference"
].freeze

def urn?(value)
  value.is_a?(String) && OMOS_URN.match?(value)
end

# 「可證明的收窄」＝目標範圍的 default_readers 是來源的**真子集**。
# 上游沒有宣告順序，所以這個關係從既有資料推導，而不是發明一套格。
# 無法證明是收窄的（含兩個互不包含的範圍之間的移動）一律視為放寬——天花板
# 規則要防的是放寬溜過去，fail-closed 只能往這個方向。
def provably_narrowing?(scopes, from_scope, to_scope)
  from_readers = scopes.dig(from_scope, "default_readers")
  to_readers = scopes.dig(to_scope, "default_readers")
  return false unless from_readers.is_a?(Array) && to_readers.is_a?(Array)

  to_set = to_readers.to_set
  from_set = from_readers.to_set
  to_set.subset?(from_set) && to_set != from_set
end

def scope_ceiling_failure(scopes, inheritance, run)
  from_scope = run["from_scope"]
  to_scope = run["to_scope"]
  return "CEILING_UNKNOWN_SCOPE" unless scopes.key?(from_scope) && scopes.key?(to_scope)
  return "CEILING_INVALID_OUTCOME" unless EXPECTED_OUTCOMES.include?(run["outcome"])

  # 拒絕套用永遠可以；只有真的改了範圍才要對天花板負責。
  return nil unless run["outcome"] == "APPLIED"
  return nil if provably_narrowing?(scopes, from_scope, to_scope)

  # 到這裡代表：不是可證明的收窄 → 當作放寬處理。
  required_receipts = inheritance.fetch("required_receipts", [])
  receipts = run["receipts"]
  return "CEILING_RECEIPTS_NOT_MAP" unless receipts.is_a?(Hash)

  unknown = receipts.keys - required_receipts
  return "CEILING_UNKNOWN_RECEIPT" unless unknown.empty?

  missing = required_receipts - receipts.keys
  return "CEILING_RECEIPT_MISSING" unless missing.empty?
  return "CEILING_RECEIPT_NOT_REF" unless receipts.values.all? { |ref| urn?(ref) }

  # 是否需要 gate 由來源範圍自己宣告，不是本檔決定。
  gate_required = scopes.dig(from_scope, "widening_requires_promotion_gate") == true
  return "CEILING_WIDENING_WITHOUT_GATE" if gate_required && !urn?(run["promotion_gate_ref"])

  nil
end

# --- 契約結構斷言 ---------------------------------------------------------

failures = []
spec = read_yaml(SPEC_PATH)
upstream = read_yaml(UPSTREAM_SPEC_PATH)

assert(spec.dig("purpose", "no_second_workflow_authority") == true,
       "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec.dig("authority", "grants_canonical_writer") == false,
       "authority.grants_canonical_writer 必須為 false", failures)
assert(spec.dig("authority", "error_behavior") == "FAIL_LOUD", "authority.error_behavior 必須為 FAIL_LOUD", failures)

EXPECTED_BOUNDARY_ADMISSIONS = %w[
  THE_REFERENCED_RECEIPTS_ARE_AUTHENTIC
  THE_REFERENCED_GATE_RUN_ACTUALLY_PASSED
  THE_DECLARED_SCOPES_MATCH_THE_REAL_MATERIAL
].freeze
admissions = spec.dig("provenance_boundary", "does_not_verify")
assert(admissions.is_a?(Array) && sorted_set(admissions) == sorted_set(EXPECTED_BOUNDARY_ADMISSIONS),
       "provenance_boundary.does_not_verify 必須列出本層驗不了的三件事：" \
       "#{EXPECTED_BOUNDARY_ADMISSIONS.inspect}，實際 #{admissions.inspect}", failures)

# FP-2-A：必須明文隔離兩個 promotion，且不得綁 promotion_path。
collision = spec.fetch("promotion_name_collision", {})
assert(collision["rule"].to_s.include?("promotion_path"),
       "promotion_name_collision 必須明文說明與 promotion_path 的區別", failures)
assert(spec.fetch("hard_stops", []).any? { |s| s.include?("promotion_path") },
       "hard_stops 必須明寫不得綁定 promotion_path", failures)

# repair-01（big review P1）：上面兩條只驗「文字有沒有寫著不能綁」，沒有驗
# 「契約本身真的沒有綁」——reviewer 塞了一個結構化 promotion_path_ref 進去，
# 兩條斷言照樣 PASS。FP-2-A 是禁令，不能只靠散文宣告，這裡補機器掃描：
# 整份契約結構裡，任何字串值只要 resolve 得到
# ai-work-record-boundary.promotion_path（或其子路徑），就是違反禁令。
def promotion_path_pointer?(value)
  return false unless value.is_a?(String)

  /\Aai-work-record-boundary\.promotion_path(\.[\w.]+)?\z/.match?(value.strip)
end

def find_promotion_path_bindings(node, path, acc)
  case node
  when Hash
    node.each { |key, value| find_promotion_path_bindings(value, path.empty? ? key.to_s : "#{path}.#{key}", acc) }
  when Array
    node.each_with_index { |item, index| find_promotion_path_bindings(item, "#{path}[#{index}]", acc) }
  when String
    acc << path if promotion_path_pointer?(node)
  end
  acc
end

forbidden_bindings = find_promotion_path_bindings(spec, "", [])
assert(forbidden_bindings.empty?,
       "FP-2-A 違規：契約結構裡出現指向 ai-work-record-boundary.promotion_path 的欄位"        "（禁令不能只靠散文，這裡是機器掃描）：#{forbidden_bindings.join(', ')}", failures)

# 綁定上游：兩個 ref 都必須 resolve 得到（尾端多餘 '.' 也要擋）。
def resolve_upstream(spec, upstream, key, failures)
  ref = spec.dig("ceiling_binding", key).to_s
  prefix = "personal-harness-integration."
  assert(ref.start_with?(prefix), "ceiling_binding.#{key} 必須指向 personal-harness-integration", failures)
  segments = ref.start_with?(prefix) ? ref[prefix.length..].to_s.split(".", -1) : []
  assert(!segments.empty? && segments.none?(&:empty?),
         "ceiling_binding.#{key} 的路徑片段不得為空（尾端多餘的 '.'？）", failures)
  resolved = segments.empty? ? nil : upstream.dig(*segments)
  assert(resolved.is_a?(Hash), "ceiling_binding.#{key} 必須能在上游 resolve 出定義：#{ref}", failures)
  resolved.is_a?(Hash) ? resolved : {}
end

inheritance = resolve_upstream(spec, upstream, "inheritance_ref", failures)
scopes = resolve_upstream(spec, upstream, "scopes_ref", failures)

required_receipts = inheritance.fetch("required_receipts", [])
assert(required_receipts.any?, "上游 source_acl_inheritance.required_receipts 不得為空（結構已改變？）", failures)
assert(scopes.any?, "上游 visibility_scopes 不得為空（結構已改變？）", failures)

# 本契約不得重述上游的 receipt 或 scope 名稱。
spec_text = File.read(SPEC_PATH)
copied = (required_receipts + scopes.keys).select { |name| spec_text.include?(name) }
assert(copied.empty?, "本契約不得重述上游名稱（會漂）：#{copied.sort.join(', ')}", failures)

# --- error_contract 綁定 --------------------------------------------------

declared_codes = spec.fetch("error_contract").keys
violations = LoopReturnContract.exit_shape_violations(__FILE__, "scope_ceiling_failure")
assert(violations.empty?, "scope_ceiling_failure 有不合契約的 return 形式：#{violations.inspect}", failures)
reachable = LoopReturnContract.reachable_codes(__FILE__, "scope_ceiling_failure")
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
  actual = scope_ceiling_failure(scopes, inheritance, test_case.fetch("run"))
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
end

negative_cases = negative_fixtures.fetch("cases")
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  assert(declared_codes.include?(expected_code),
         "#{case_id} 的 expected_failure_code #{expected_code} 未在 error_contract 宣告", failures)
  actual = scope_ceiling_failure(scopes, inheritance, test_case.fetch("run"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 #{expected_code}，實際 #{actual.inspect}", failures)
end

covered = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(', ')}", failures)

# 每個宣告 widening_requires_promotion_gate 的範圍，都必須有一個「從它放寬且
# 缺 gate 就被擋」的負例——否則該範圍的旗標等於沒被驗過。
gated_scopes = scopes.select { |_name, defn| defn.is_a?(Hash) && defn["widening_requires_promotion_gate"] == true }.keys
exercised_gate_denials = negative_cases.select { |c| c.fetch("expected_failure_code") == "CEILING_WIDENING_WITHOUT_GATE" }
                                       .map { |c| c.dig("run", "from_scope") }.uniq
uncovered_gates = gated_scopes - exercised_gate_denials
assert(uncovered_gates.empty?,
       "宣告需要 gate 的範圍缺少「缺 gate 即被擋」的負例：#{uncovered_gates.sort.join(', ')}", failures)

if failures.empty?
  puts "PASS emem scope ceiling contract validation " \
       "(scopes=#{scopes.size}, receipts=#{required_receipts.size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
