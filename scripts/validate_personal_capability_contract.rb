#!/usr/bin/env ruby

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-negative-fixtures.json")


# SSP-290 / Personal Knowledge L1~L4 能力矩陣、升降級、safety floor 契約 validator。

EXPECTED_CAPABILITY_LEVELS = %w[
  L1
  L2
  L3
  L4
].freeze
EXPECTED_CAPABILITY_KEYS = (EXPECTED_CAPABILITY_LEVELS + %w[same_contract_all_levels]).freeze
LEVEL_ORDER = %w[L1 L2 L3 L4].freeze

EXPECTED_MATRIX_CAPABILITIES = %w[
  manual_capture
  candidate_generation
  employee_confirmation
  basic_recall_with_citation
  automatic_source_ingestion
  deterministic_dedup_version_acl_retention
  automatic_candidate_queue
  cross_source_object_linking
  workrecord_correlation
  conflict_freshness_gap_suggestion
  context_aware_recall
  promotion_suggestion
  continuous_stale_conflict_gap_monitoring
  correction_proposal
  promotion_proposal
  projection_rebuild_regression_evaluation
].freeze

EXPECTED_LEVEL_GRANTS = {
  "L1" => %w[manual_capture candidate_generation employee_confirmation basic_recall_with_citation],
  "L2" => %w[automatic_source_ingestion deterministic_dedup_version_acl_retention automatic_candidate_queue],
  "L3" => %w[cross_source_object_linking workrecord_correlation conflict_freshness_gap_suggestion context_aware_recall promotion_suggestion],
  "L4" => %w[continuous_stale_conflict_gap_monitoring correction_proposal promotion_proposal projection_rebuild_regression_evaluation]
}.freeze

EXPECTED_CAPABILITY_SAFETY_FLOOR = %w[
  permission_before_retrieval
  provenance_required
  canonical_single_writer
  candidate_not_auto_accepted_by_level
  promotion_requires_widening_gate
].freeze

L4_AUTHORITY_GATED_ACTIONS = %w[correction_proposal promotion_proposal].freeze

EXPECTED_CAPABILITY_NEGATIVE_LABELS = [
  "level claims capability above its grant",
  "downgrade removes a safety-floor invariant",
  "L4 action bypasses the authority gate",
  "profile references a non-existent level",
  "level transition skips a step",
  "capability level forks the core contract"
].freeze

def effective_capability_grant(level)
  index = LEVEL_ORDER.index(level)
  return nil if index.nil?

  LEVEL_ORDER[0..index].flat_map { |lvl| EXPECTED_LEVEL_GRANTS.fetch(lvl) }
end

# Returns nil when the capability profile is contract-valid, otherwise the exact
# machine failure code. Fixtures declare the expected code so that an unrelated
# rejection cannot stand in for real coverage.
def capability_profile_failure(profile)
  level = profile["capability_level"]
  return "UNKNOWN_CAPABILITY_LEVEL" unless LEVEL_ORDER.include?(level)
  return "LEVEL_FORKS_CORE_CONTRACT" if profile["forks_core_contract"] == true

  granted = effective_capability_grant(level)
  claimed = profile["claimed_capabilities"].to_a
  return "CAPABILITY_ABOVE_LEVEL_GRANT" if claimed.any? { |capability| !granted.include?(capability) }

  if level == "L4" && !(claimed & L4_AUTHORITY_GATED_ACTIONS).empty? && profile["authority_gate_satisfied"] != true
    return "L4_ACTION_BYPASSES_AUTHORITY_GATE"
  end

  if profile.key?("safety_floor_state")
    floor = profile.fetch("safety_floor_state", {})
    return "SAFETY_FLOOR_INVARIANT_MISSING" if EXPECTED_CAPABILITY_SAFETY_FLOOR.any? { |invariant| floor[invariant] != true }
  end

  nil
end

# Returns nil when the level transition is contract-valid, otherwise the exact
# machine failure code.
def level_transition_failure(spec, transition)
  from_level = transition["from"]
  to_level = transition["to"]
  return "UNKNOWN_CAPABILITY_LEVEL" unless LEVEL_ORDER.include?(from_level) && LEVEL_ORDER.include?(to_level)

  contract = spec.fetch("level_transitions")
  is_upgrade = LEVEL_ORDER.index(to_level) > LEVEL_ORDER.index(from_level)
  allowed = if is_upgrade
              contract.dig("allowed_upgrades", from_level).to_a
            else
              contract.dig("allowed_downgrades", from_level).to_a
            end
  return "LEVEL_TRANSITION_NOT_SINGLE_STEP" unless allowed.include?(to_level)
  return "LEVEL_TRANSITION_UNAUTHORIZED_ACTOR" unless transition["authorized_actor"] == true
  return "LEVEL_TRANSITION_REASON_NOT_RECORDED" unless transition["reason_recorded"] == true
  return "LEVEL_TRANSITION_FORKS_CORE_CONTRACT" if transition["forks_core_contract"] == true

  unless is_upgrade
    floor = transition.fetch("safety_floor_after", {})
    return "DOWNGRADE_REMOVES_SAFETY_FLOOR" if EXPECTED_CAPABILITY_SAFETY_FLOOR.any? { |invariant| floor[invariant] != true }
  end

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)

capability_levels = spec.fetch("capability_levels", {})
assert(sorted_set(capability_levels.keys) == sorted_set(EXPECTED_CAPABILITY_KEYS), "capability_levels 必須只包含 L1～L4 與 same_contract_all_levels", failures)
assert(capability_levels["same_contract_all_levels"] == true, "L1～L4 必須共用同一核心契約", failures)
assert(capability_levels.dig("L4", "authority_gate_required") == true, "capability_levels.L4 authority_gate_required 必須維持 true", failures)

capability_matrix = spec.fetch("capability_matrix", {})
assert(
  sorted_set(capability_matrix.fetch("capabilities", [])) == sorted_set(EXPECTED_MATRIX_CAPABILITIES),
  "capability_matrix.capabilities 必須剛好是鎖定的 phase-1 capability 清單",
  failures
)
assert(capability_matrix["cumulative"] == true, "capability_matrix.cumulative 必須為 true", failures)
matrix_grants = capability_matrix.fetch("grants", {})
assert(sorted_set(matrix_grants.keys) == sorted_set(LEVEL_ORDER), "capability_matrix.grants 必須剛好涵蓋 L1～L4", failures)
LEVEL_ORDER.each do |level|
  assert(
    matrix_grants[level].to_a == EXPECTED_LEVEL_GRANTS.fetch(level),
    "capability_matrix.grants.#{level} 與鎖定 grant 不符",
    failures
  )
end
all_grant_rows = LEVEL_ORDER.flat_map { |level| matrix_grants[level].to_a }
assert(all_grant_rows.uniq.length == all_grant_rows.length, "capability_matrix.grants 各級不得重複列同一 capability", failures)
assert(
  sorted_set(all_grant_rows) == sorted_set(EXPECTED_MATRIX_CAPABILITIES),
  "capability_matrix.grants 各級聯集必須等於 capabilities",
  failures
)
assert(
  capability_matrix.dig("level_gated_actions", "L4").to_a == L4_AUTHORITY_GATED_ACTIONS,
  "capability_matrix.level_gated_actions.L4 必須是 correction_proposal 與 promotion_proposal",
  failures
)

level_transitions = spec.fetch("level_transitions", {})
assert(level_transitions["single_step_only"] == true, "level_transitions.single_step_only 必須為 true", failures)
assert(level_transitions.dig("allowed_upgrades", "L1").to_a == %w[L2], "L1 只能升級到 L2", failures)
assert(level_transitions.dig("allowed_upgrades", "L2").to_a == %w[L3], "L2 只能升級到 L3", failures)
assert(level_transitions.dig("allowed_upgrades", "L3").to_a == %w[L4], "L3 只能升級到 L4", failures)
assert(level_transitions.dig("allowed_upgrades", "L4").to_a.empty?, "L4 之上不得有升級目標", failures)
assert(level_transitions.dig("allowed_downgrades", "L4").to_a == %w[L3], "L4 只能降級到 L3", failures)
assert(level_transitions.dig("allowed_downgrades", "L3").to_a == %w[L2], "L3 只能降級到 L2", failures)
assert(level_transitions.dig("allowed_downgrades", "L2").to_a == %w[L1], "L2 只能降級到 L1", failures)
assert(level_transitions.dig("allowed_downgrades", "L1").to_a.empty?, "L1 之下不得有降級目標", failures)
assert(
  sorted_set(level_transitions.fetch("transition_requirements", [])) == sorted_set(%w[authorized_actor reason_recorded]),
  "level transition 必須要求 authorized_actor 與 reason_recorded",
  failures
)
assert(level_transitions.dig("downgrade_rules", "must_preserve_safety_floor") == true, "降級必須保留 safety floor", failures)
assert(level_transitions.dig("downgrade_rules", "reduces_automation_depth_only") == true, "降級只減自動化深度必須為 true", failures)
assert(
  sorted_set(level_transitions.fetch("forbidden", [])) == sorted_set(%w[multi_step_jump unauthorized_actor downgrade_that_removes_safety_floor transition_that_forks_core_contract]),
  "level_transitions.forbidden 必須剛好是四個鎖定禁止項",
  failures
)

capability_safety_floor = spec.fetch("capability_safety_floor", {})
assert(
  sorted_set(capability_safety_floor.fetch("invariants", [])) == sorted_set(EXPECTED_CAPABILITY_SAFETY_FLOOR),
  "capability_safety_floor.invariants 與鎖定清單不符",
  failures
)
assert(capability_safety_floor["applies_to_all_levels"] == true, "capability_safety_floor 必須適用所有 level", failures)
assert(capability_safety_floor["downgrade_preserves_all_invariants"] == true, "capability_safety_floor 降級不得移除任一不變項", failures)
assert(
  capability_safety_floor.dig("l4_authority_gate", "authority_gate_required") == true,
  "capability_safety_floor.l4_authority_gate.authority_gate_required 必須為 true",
  failures
)
assert(
  capability_safety_floor.dig("l4_authority_gate", "gated_actions").to_a == L4_AUTHORITY_GATED_ACTIONS,
  "capability_safety_floor.l4_authority_gate.gated_actions 必須是 correction_proposal 與 promotion_proposal",
  failures
)

capability_profile_cases = read_json(POSITIVE_FIXTURE_PATH).fetch("capability_profile_cases")
level_transition_cases = read_json(POSITIVE_FIXTURE_PATH).fetch("level_transition_cases")
capability_profile_negative_cases = read_json(NEGATIVE_FIXTURE_PATH).fetch("capability_profile_negative_cases")
level_transition_negative_cases = read_json(NEGATIVE_FIXTURE_PATH).fetch("level_transition_negative_cases")

capability_profile_cases.each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} capability profile positive fixture 必須預期 allow", failures)
  actual = capability_profile_failure(test_case.fetch("profile"))
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

level_transition_cases.each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} level transition positive fixture 必須預期 allow", failures)
  actual = level_transition_failure(spec, test_case.fetch("transition"))
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

capability_profile_negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} capability profile negative fixture 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = capability_profile_failure(test_case.fetch("profile"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

level_transition_negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} level transition negative fixture 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = level_transition_failure(spec, test_case.fetch("transition"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

covered_capability_negative_labels = sorted_set(
  (capability_profile_negative_cases + level_transition_negative_cases).map { |test_case| test_case.fetch("covers_capability_negative_fixture") }
)
missing_capability_negative_labels = sorted_set(EXPECTED_CAPABILITY_NEGATIVE_LABELS) - covered_capability_negative_labels
assert(missing_capability_negative_labels.empty?, "capability negative fixtures 未覆蓋：#{missing_capability_negative_labels.to_a.join(", ")}", failures)

if failures.empty?
  puts "PASS personal capability contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
