#!/usr/bin/env ruby

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/personal_memory_resource_evaluator"

# resource evaluator 已抽成共用 helper，供 EMEM-11 切片 1 的 runtime
# 一併消費——本片只呼叫它，不再保留第二份實作。
PMRE = PersonalMemoryResourceEvaluator

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
COMMON_VOCAB_PATH = File.join(ROOT, "規格/v0.1/common-vocabulary.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-negative-fixtures.json")

# EMEM-01 / PMCORE-02：PersonalMemoryCandidate／Record／MemorySupportLink／
# MemoryConflictSet 四個 resource 的結構、lifecycle、support／conflict ref 綁定契約。

EXPECTED_PERSONAL_MEMORY_RESOURCES = %w[
  PersonalMemoryCandidate
  PersonalMemoryRecord
  MemorySupportLink
  MemoryConflictSet
].freeze
EXPECTED_RESOURCE_NEGATIVE_LABELS = [
  "PersonalMemoryCandidate without support link",
  "PersonalMemoryCandidate treated as accepted record",
  "PersonalMemoryRecord created without personal acceptance",
  "transient task state promoted as personal memory",
  "support link crosses employee owner without permission intersection",
  "support link target_ref mismatches supported resource",
  "support link ref does not resolve",
  "support link uses disallowed source anchor profile",
  "MemoryConflictSet selects winner without review authority",
  "MemoryConflictSet declares canonical_winner_ref",
  "PersonalMemoryRecord lifecycle transition is not allowed",
  "MemoryConflictSet crosses owner without permission intersection",
  "MemoryConflictSet member ref uses wrong resource kind",
  "MemoryConflictSet member ref does not resolve",
  "MemoryConflictSet support link ref does not resolve",
  "MemoryConflictSet support link target or relation is invalid",
  "MemoryConflictSet member owner metadata mismatches parsed member"
].freeze


failures = []
spec = read_yaml(SPEC_PATH)
common_vocab = read_yaml(COMMON_VOCAB_PATH)

resource_contracts = spec.fetch("personal_memory_resource_contracts", {})
assert(resource_contracts["version"] == "0.1.0", "personal_memory_resource_contracts.version 必須是 0.1.0", failures)
assert(
  sorted_set(resource_contracts.dig("resources")&.keys.to_a) == sorted_set(EXPECTED_PERSONAL_MEMORY_RESOURCES),
  "personal_memory_resource_contracts 必須定義四個 PMCORE-02 resources",
  failures
)
assert(resource_contracts.dig("shared_constraints", "model_summary_as_support") == "forbidden", "model summary 不得作為 support", failures)
assert(resource_contracts.dig("shared_constraints", "cross_employee_reference_rule").to_s.include?("permission_intersection_ref"), "跨 employee reference 必須要求 permission_intersection_ref", failures)
assert(PMRE.enum_from(spec, "personal_memory_resource_contracts", "enums", "candidate_status") == PMRE::EXPECTED_CANDIDATE_STATUSES, "candidate_status enum 不符合 PMCORE-02", failures)
assert(PMRE.enum_from(spec, "personal_memory_resource_contracts", "enums", "record_status") == PMRE::EXPECTED_RECORD_STATUSES, "record_status enum 不符合 PMCORE-02", failures)
assert(
  PMRE.enum_from(spec, "personal_memory_resource_contracts", "resources", "MemoryConflictSet", "forbidden_authority").include?("winner_selection"),
  "MemoryConflictSet 必須禁止自行選 winner",
  failures
)

positive_resource_cases = read_json(POSITIVE_FIXTURE_PATH).fetch("resource_cases")
negative_resource_cases = read_json(NEGATIVE_FIXTURE_PATH).fetch("resource_cases")
fixture_resource_indexes = PMRE.build_indexes(positive_resource_cases + negative_resource_cases)

positive_resource_cases.each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} resource positive fixture 必須預期 allow", failures)
  actual = PMRE.evaluate_resource_case(spec, common_vocab, fixture_resource_indexes, test_case)
  assert(actual == test_case.fetch("expected"), "#{test_case.fetch("case_id")} 預期 allow，實際 #{actual}: #{PMRE.resource_failures(spec, common_vocab, fixture_resource_indexes, test_case).join("; ")}", failures)
end

negative_resource_cases.each do |test_case|
  assert(test_case.fetch("expected") == "deny", "#{test_case.fetch("case_id")} resource negative fixture 必須預期 deny", failures)
  actual = PMRE.evaluate_resource_case(spec, common_vocab, fixture_resource_indexes, test_case)
  assert(actual == test_case.fetch("expected"), "#{test_case.fetch("case_id")} 預期 deny，實際 #{actual}", failures)
end

covered_resource_negative_labels = sorted_set(negative_resource_cases.map { |test_case| test_case.fetch("covers_resource_negative_fixture") })
missing_resource_negative_labels = sorted_set(EXPECTED_RESOURCE_NEGATIVE_LABELS) - covered_resource_negative_labels
assert(missing_resource_negative_labels.empty?, "resource negative fixtures 未覆蓋：#{missing_resource_negative_labels.to_a.join(", ")}", failures)

if failures.empty?
  puts "PASS personal memory resource contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
