#!/usr/bin/env ruby

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-negative-fixtures.json")


# SSP-292 / EMEM-03 Recall / MemoryContextPack 契約 validator。

EXPECTED_RECALL_REQUEST_FIELDS = %w[
  intent
  requester_identity
  requester_scope
  ownership_mode
  visibility_scope
  context_budget
].freeze

EXPECTED_CONTEXT_PACK_FIELDS = %w[
  pack_id
  request_ref
  permission_decision_ref
  permission_decision_before_selection
  permission_decision_covered_memory_refs
  selected_memories
  source_refs
  applicability
  freshness
  permission_intersection_refs
  not_applicable_filtered_count
  omitted_or_gap_notice
  budget_usage
].freeze

# 這幾個 pack 欄位必須有實值（不是只有 key）。
CONTEXT_PACK_PRESENT_FIELDS = %w[pack_id request_ref permission_decision_ref].freeze
EXPECTED_INTERSECTION_ENTRY_FIELDS = %w[memory_ref intersection_ref].freeze
RECALL_FORBIDDEN_SEARCH_STRATEGIES = {
  "GLOBAL_THEN_PROMPT_GUARD" => "SEARCH_ALL_THEN_PROMPT_GUARD",
  "UNRESTRICTED_GLOBAL_SEARCH" => "UNRESTRICTED_GLOBAL_SEARCH"
}.freeze

EXPECTED_RECALL_GAP_REASONS = %w[STALE_PRESENT NOT_APPLICABLE_FILTERED BUDGET_OMITTED].freeze
EXPECTED_RECALL_FORBIDDEN = %w[
  SEARCH_ALL_THEN_PROMPT_GUARD
  UNRESTRICTED_GLOBAL_SEARCH
  STALE_WITHOUT_FRESHNESS
  CROSS_OWNER_WITHOUT_INTERSECTION
].freeze

EXPECTED_RECALL_NEGATIVE_LABELS = [
  "recall request missing a required field",
  "permission decision scope narrower than selected set",
  "search all personal memory then rely on prompt guard",
  "stale memory returned without freshness marker",
  "budget-omitted memory without a gap notice",
  "cross-owner selection without permission intersection"
].freeze

# Thin recall-contract check: no retrieval engine, only MemoryContextPack shape,
# permission ordering, gap-notice, and the forbidden search-all-then-prompt-guard
# path. `request` and `pack` are self-contained fixture objects. Returns nil or
# the exact machine failure code.
def context_pack_failure(request, pack)
  return "RECALL_REQUEST_MISSING_FIELD" if EXPECTED_RECALL_REQUEST_FIELDS.any? { |field| !present?(request[field]) }
  return "CONTEXT_PACK_MISSING_FIELD" if EXPECTED_CONTEXT_PACK_FIELDS.any? { |field| !pack.key?(field) }
  return "CONTEXT_PACK_MISSING_FIELD" if CONTEXT_PACK_PRESENT_FIELDS.any? { |field| !present?(pack[field]) }
  return "CONTEXT_PACK_MISSING_FIELD" unless pack["permission_decision_covered_memory_refs"].is_a?(Array)
  return "CONTEXT_PACK_MISSING_FIELD" unless pack["permission_intersection_refs"].is_a?(Array)

  forbidden_search_code = RECALL_FORBIDDEN_SEARCH_STRATEGIES[pack["search_strategy"]]
  return forbidden_search_code if forbidden_search_code

  return "PERMISSION_DECISION_AFTER_SELECTION" if pack["permission_decision_before_selection"] != true

  selected = pack["selected_memories"].to_a
  selected_refs = selected.map { |memory| memory["memory_ref"] }
  covered_refs = pack["permission_decision_covered_memory_refs"].to_a
  return "PERMISSION_DECISION_SCOPE_TOO_NARROW" unless (selected_refs - covered_refs).empty?

  intersection_refs = pack["permission_intersection_refs"].to_a
  requester = request["requester_identity"]
  selected.each do |memory|
    next if memory["owner_ref"] == requester

    entry = intersection_refs.find { |candidate| candidate["memory_ref"] == memory["memory_ref"] }
    return "CROSS_OWNER_WITHOUT_INTERSECTION" if entry.nil? || !present?(entry["intersection_ref"])
  end

  gap_reasons = pack["omitted_or_gap_notice"].to_a.map { |notice| notice["reason"] }
  return "STALE_WITHOUT_FRESHNESS" if selected.any? { |memory| memory["freshness"] == "STALE" } &&
                                      !(pack.dig("freshness", "stale_present") == true && gap_reasons.include?("STALE_PRESENT"))
  return "BUDGET_OMITTED_WITHOUT_NOTICE" if pack.dig("budget_usage", "omitted_count").to_i.positive? &&
                                            !gap_reasons.include?("BUDGET_OMITTED")
  return "NOT_APPLICABLE_WITHOUT_NOTICE" if pack["not_applicable_filtered_count"].to_i.positive? &&
                                            !gap_reasons.include?("NOT_APPLICABLE_FILTERED")

  nil
end

failures = []
spec = read_yaml(SPEC_PATH)

recall = spec.fetch("recall_context_pack", {})
assert(recall["permission_strategy"] == "INTERSECTION", "recall_context_pack.permission_strategy 必須是 INTERSECTION", failures)
assert(recall["unrestricted_global_personal_memory_search"] == "forbidden", "recall_context_pack 必須禁止 unrestricted global search", failures)
recall_contract = recall.fetch("contract", {})
assert(
  recall_contract.fetch("request_required_fields", []) == EXPECTED_RECALL_REQUEST_FIELDS,
  "recall_context_pack.contract.request_required_fields 與鎖定清單不符",
  failures
)
assert(
  recall_contract.fetch("pack_required_fields", []) == EXPECTED_CONTEXT_PACK_FIELDS,
  "recall_context_pack.contract.pack_required_fields 與鎖定清單不符",
  failures
)
assert(recall_contract.dig("permission_ordering", "decision_before_candidate_set") == true, "recall permission decision 必須先於 candidate set", failures)
assert(recall_contract.dig("permission_ordering", "decision_scope_covers_selected") == true, "recall permission decision scope 必須涵蓋 selected", failures)
assert(
  sorted_set(recall_contract.fetch("gap_notice_reasons", [])) == sorted_set(EXPECTED_RECALL_GAP_REASONS),
  "recall_context_pack.contract.gap_notice_reasons 與鎖定清單不符",
  failures
)
assert(
  sorted_set(recall_contract.fetch("forbidden", [])) == sorted_set(EXPECTED_RECALL_FORBIDDEN),
  "recall_context_pack.contract.forbidden 與鎖定清單不符",
  failures
)
assert(
  spec.dig("contract_registry", "define_for_employee_memory", "MemoryContextPack", "required_fields_ref") == "recall_context_pack.contract.pack_required_fields",
  "MemoryContextPack.required_fields_ref 必須指向 recall_context_pack.contract.pack_required_fields",
  failures
)
assert(
  recall_contract.fetch("permission_intersection_entry_fields", []) == EXPECTED_INTERSECTION_ENTRY_FIELDS,
  "recall_context_pack.contract.permission_intersection_entry_fields 必須是 [memory_ref, intersection_ref]",
  failures
)
assert(
  recall_contract.fetch("forbidden_search_strategies", {}) == RECALL_FORBIDDEN_SEARCH_STRATEGIES,
  "recall_context_pack.contract.forbidden_search_strategies 與鎖定對映表不符",
  failures
)

context_pack_cases = read_json(POSITIVE_FIXTURE_PATH).fetch("context_pack_cases")
context_pack_negative_cases = read_json(NEGATIVE_FIXTURE_PATH).fetch("context_pack_negative_cases")

context_pack_cases.each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} context pack positive fixture 必須預期 allow", failures)
  actual = context_pack_failure(test_case.fetch("request"), test_case.fetch("pack"))
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

context_pack_negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} context pack negative fixture 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = context_pack_failure(test_case.fetch("request"), test_case.fetch("pack"))
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

covered_recall_negative_labels = sorted_set(context_pack_negative_cases.map { |test_case| test_case.fetch("covers_recall_negative_fixture") })
missing_recall_negative_labels = sorted_set(EXPECTED_RECALL_NEGATIVE_LABELS) - covered_recall_negative_labels
assert(missing_recall_negative_labels.empty?, "recall negative fixtures 未覆蓋：#{missing_recall_negative_labels.to_a.join(", ")}", failures)

if failures.empty?
  puts "PASS recall context pack contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
