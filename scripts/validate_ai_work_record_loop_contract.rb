#!/usr/bin/env ruby

# SSP-302 / AIWR-05：收口 Loop 契約 validator。
# 薄判斷：結構斷言 + 純函式 `loop_closeout_failure(run, ...)` evaluator——
#   有界（max_iterations + timeout）、iterations 不超過 max、outcome ∈ 鎖定集合且與
#   terminal_condition 一致、只補 fillable_fields（不擴張 scope）、缺人類決策即停標 blocker、
#   unfixable 即 FAILED_LOUD 且保留原證據、authority floor、fail-loud。
# 交叉讀 ai-task-card-record.yaml、ai-work-record-skill.yaml、ai-work-record-boundary.yaml
# （pointer binding）。沿用 scripts/lib/omos_contract_helpers.rb。

require "json"
require "yaml"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-loop.yaml")
CARD_RECORD_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-task-card-record.yaml")
SKILL_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-skill.yaml")
BOUNDARY_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-boundary.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-loop-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/ai-work-record-loop-negative-fixtures.json")

EXPECTED_TERMINAL_CONDITIONS = %w[
  ALL_REQUIRED_PRESENT
  MAX_ITERATIONS_REACHED
  TIMEOUT
  BLOCKER_MARKED
  UNFIXABLE
].freeze
EXPECTED_FILLABLE_FIELDS = %w[status evidence_refs].freeze
EXPECTED_FORBIDDEN_FILL_FIELDS = %w[card_id objective scope constraints acceptance].freeze
EXPECTED_ITERATION_FIELDS = %w[iteration filled_fields remaining_gaps].freeze
EXPECTED_OUTCOMES = %w[CLOSED BLOCKED FAILED_LOUD].freeze
EXPECTED_OUTCOME_CONDITION_MAP = {
  "CLOSED" => %w[ALL_REQUIRED_PRESENT MAX_ITERATIONS_REACHED],
  "BLOCKED" => %w[BLOCKER_MARKED],
  "FAILED_LOUD" => %w[TIMEOUT UNFIXABLE]
}.freeze
EXPECTED_FORBIDDEN_RUN_FIELDS = %w[
  personal_acceptance_ref
  verification_receipt_ref
  accepted_for_record
  canonical_write_receipt_ref
].freeze

# 鎖定的 machine failure code 集合。
#
# 注意：這張常數清單「不是」error_contract 完整性的證據來源。TIGHTEN-F-01 指出，
# 常數與 YAML 都由同一隻手寫,互比會通過,卻證明不了 evaluator ——
# 當時漏掉的 LOOP_MISSING_FIELD 就是這樣穿過去的。真正的綁定在
# reachable_loop_failure_codes:從 evaluator 函式本體掃出實際可達的 return literal。
# 這張常數只負責第二件事:防止有人「同時」改 evaluator 與 YAML 而悄悄動了鎖定集合。
EXPECTED_LOOP_ERROR_CODES = %w[
  LOOP_UNBOUNDED
  LOOP_OVER_TIMEOUT
  LOOP_TIMEOUT_NOT_REACHED
  LOOP_MISSING_FIELD
  LOOP_OVER_MAX_ITERATIONS
  LOOP_MALFORMED_ITERATION
  LOOP_INVALID_OUTCOME
  LOOP_OUTCOME_CONDITION_MISMATCH
  LOOP_REQUIRED_PRESENT_WITH_GAPS
  LOOP_SCOPE_EXPANSION
  LOOP_SKIPPED_HUMAN_DECISION
  LOOP_UNFIXABLE_NOT_LOUD
  LOOP_EVIDENCE_NOT_PRESERVED
  LOOP_EXCEEDS_AUTHORITY
  FAIL_SILENT
].freeze

EXPECTED_LOOP_NEGATIVE_LABELS = [
  "run without a positive max_iterations",
  "run without a positive timeout_seconds",
  "run without a verifiable elapsed_seconds",
  "elapsed_seconds exceeds timeout_seconds without failing loud",
  "the run claims a timeout terminal condition without actually exceeding the timeout",
  "iterations exceed max_iterations",
  "an iteration is missing a required field",
  "outcome is not one of the allowed outcomes",
  "outcome disagrees with the terminal condition",
  "the run claims all required fields are present while a gap remains",
  "an iteration fills a scope-defining field",
  "a human-decision gap remains but the run did not stop at a blocker",
  "a human-decision gap appears mid-run but the run continued",
  "an unfixable gap remains but the run did not fail loud",
  "an unfixable gap appears mid-run but the run continued",
  "failed loud but the original evidence was not preserved",
  "run carries a memory acceptance field",
  "error but the run still claims success",
  "the run carries no iterations field at all",
  "the run declares iterations as something other than a list",
  "the loop performs memory acceptance itself",
  "the loop writes company knowledge itself"
].freeze

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
  values.to_a.sort
end

def positive_integer?(value)
  value.is_a?(Integer) && value.positive?
end

def non_negative_integer?(value)
  value.is_a?(Integer) && value >= 0
end

def timeout_terminated?(run)
  run["outcome"] == "FAILED_LOUD" && run["terminal_condition"] == "TIMEOUT"
end

# 純函式收口 Loop evaluator。回傳 nil 或精確 machine failure code。
# run 是自足 fixture 物件:
#   max_iterations, timeout_seconds, elapsed_seconds,
#   iterations[{iteration, filled_fields[], remaining_gaps[]}],
#   outcome, terminal_condition, blocker_ref, original_evidence_preserved,
#   performs_memory_acceptance, writes_company_knowledge, error, ok。
def loop_closeout_failure(run, fillable_fields, outcome_condition_map)
  # 1. 有界:缺正整數 max_iterations / timeout_seconds,或缺可驗的非負 elapsed_seconds
  return "LOOP_UNBOUNDED" unless positive_integer?(run["max_iterations"]) &&
                                 positive_integer?(run["timeout_seconds"]) &&
                                 non_negative_integer?(run["elapsed_seconds"])

  # 2. timeout 是 enforcement:elapsed 超過 timeout 只有在 FAILED_LOUD + TIMEOUT 收尾時才可過
  return "LOOP_OVER_TIMEOUT" if run["elapsed_seconds"] > run["timeout_seconds"] && !timeout_terminated?(run)

  # 2b. F-05 反向一致性:宣稱 TIMEOUT 收尾就必須真的逾時（嚴格大於;等號不算逾時）
  if run["terminal_condition"] == "TIMEOUT" && !(run["elapsed_seconds"] > run["timeout_seconds"])
    return "LOOP_TIMEOUT_NOT_REACHED"
  end

  # 3. authority floor(停用與否都適用)
  return "LOOP_EXCEEDS_AUTHORITY" if run["performs_memory_acceptance"] == true
  return "LOOP_EXCEEDS_AUTHORITY" if run["writes_company_knowledge"] == true
  return "LOOP_EXCEEDS_AUTHORITY" if EXPECTED_FORBIDDEN_RUN_FIELDS.any? { |field| run.key?(field) }

  # 4. fail-loud
  return "FAIL_SILENT" if present?(run["error"]) && run["ok"] != false

  iterations = run["iterations"]
  return "LOOP_MISSING_FIELD" unless iterations.is_a?(Array)

  # 5. 迭代不得超過 max_iterations
  return "LOOP_OVER_MAX_ITERATIONS" if iterations.length > run["max_iterations"]

  # 6. 每個 iteration fail-closed 驗三欄齊備且 filled_fields / remaining_gaps 為 Array
  iterations.each do |iteration|
    unless iteration.is_a?(Hash) && EXPECTED_ITERATION_FIELDS.all? { |field| iteration.key?(field) } &&
           iteration["filled_fields"].is_a?(Array) && iteration["remaining_gaps"].is_a?(Array)
      return "LOOP_MALFORMED_ITERATION"
    end
  end

  # 7. scope lock:每輪 filled_fields 只能是 fillable_fields
  iterations.each do |iteration|
    return "LOOP_SCOPE_EXPANSION" if iteration["filled_fields"].any? { |field| !fillable_fields.include?(field) }
  end

  # 8. outcome 合法性
  return "LOOP_INVALID_OUTCOME" unless EXPECTED_OUTCOMES.include?(run["outcome"])

  # 9. outcome 與 terminal_condition 一致
  allowed_conditions = outcome_condition_map.fetch(run["outcome"], [])
  return "LOOP_OUTCOME_CONDITION_MISMATCH" unless allowed_conditions.include?(run["terminal_condition"])

  # 10. mandatory-stop gap 逐輪檢查:第一個帶 human-decision / non-human unfixable 缺口的
  #     iteration 必須就是最後一輪,且 outcome 對應 BLOCKED / FAILED_LOUD。
  last_index = iterations.length - 1
  iterations.each_with_index do |iteration, index|
    gaps = iteration["remaining_gaps"]
    if gaps.any? { |gap| gap["requires_human_decision"] == true }
      unless index == last_index && run["outcome"] == "BLOCKED" && present?(run["blocker_ref"])
        return "LOOP_SKIPPED_HUMAN_DECISION"
      end
    end
    if gaps.any? { |gap| gap["auto_fixable"] == false && gap["requires_human_decision"] != true }
      return "LOOP_UNFIXABLE_NOT_LOUD" unless index == last_index && run["outcome"] == "FAILED_LOUD"
    end
  end

  # 11. F-04 CLOSED 語意:宣稱 ALL_REQUIRED_PRESENT 就必須真的收乾淨——最後一輪不得留任何缺口。
  #     MAX_ITERATIONS_REACHED 仍可留普通缺口（達上限、普通缺口交人），故只綁前者。
  #     置於第 10 步之後,human-decision / unfixable 缺口維持回報原本更精確的 code。
  if run["terminal_condition"] == "ALL_REQUIRED_PRESENT" && !iterations.empty? &&
     !iterations[last_index]["remaining_gaps"].empty?
    return "LOOP_REQUIRED_PRESENT_WITH_GAPS"
  end

  return "LOOP_EVIDENCE_NOT_PRESERVED" if run["outcome"] == "FAILED_LOUD" && run["original_evidence_preserved"] != true

  nil
end

# evaluator 內唯一允許的 return 形式。
#
# SSP302-F-01：reachable_loop_failure_codes 是 regex 掃描,而 regex 必然是語法特定的。
# 原本只保證「掃到的都對」,沒有保證「沒有掃不到的」——於是
#
#     return 'LOOP_UNDECLARED' if run["x"]
#
# 是 Ruby 真正可回傳的新 code,卻完全穿過三層 assertion。
#
# 想用 regex 涵蓋 Ruby 全部 return 語法(插值、heredoc、常數、方法回傳)本質上做不完,
# 做了也只是換一個更難察覺的 under-approximation。因此改為把不確定性關掉:
# evaluator 的 return 形式本身是可窮舉的白名單,違反即轉紅。
ALLOWED_EVALUATOR_RETURN = /\Areturn (?:nil|"[A-Z][A-Z0-9_]*")(?:\s+(?:if|unless)\b.*)?\z/.freeze

# 掃描與形式檢查共用同一段函式本體,不會各掃各的。
def loop_evaluator_body
  File.read(__FILE__)[/^def loop_closeout_failure.*?^end$/m].to_s
end

# evaluator 實際可回傳的 code,由原始碼掃出。
#
# 只掃 loop_closeout_failure 函式本體,避免掃到註解、常數清單或其他函式的字串。
# 單雙引號都掃,讓單引號 code 同時踩中形式白名單與完整性斷言(雙層)。
# 掃不到任何 code 時必須視為掃描失效並轉紅,而不是「剛好沒有 code」。
def reachable_loop_failure_codes
  loop_evaluator_body.scan(/return ["\']([A-Z][A-Z0-9_]*)["\']/).flatten.uniq
end

# 回傳所有不符白名單的 return 語句;非空即代表掃描可能漏認 code。
def unexpected_evaluator_return_forms
  loop_evaluator_body.lines.map(&:strip)
                     .select { |line| line.start_with?("return") }
                     .reject { |line| ALLOWED_EVALUATOR_RETURN.match?(line) }
end

failures = []
spec = read_yaml(SPEC_PATH)
card_record_spec = read_yaml(CARD_RECORD_SPEC_PATH)
skill_spec = read_yaml(SKILL_SPEC_PATH)
boundary = read_yaml(BOUNDARY_SPEC_PATH)

schema = spec.fetch("schema", {})
assert(schema["schema_id"] == "urn:omos:schema:ai-work-record-loop:0.1.0", "schema_id 必須是 ai-work-record-loop:0.1.0", failures)
assert(schema["version"] == "0.1.0", "schema.version 必須是 0.1.0", failures)
assert(schema.fetch("traces_to", []).include?("AIWR-05"), "schema.traces_to 必須包含 AIWR-05", failures)

assert(spec.dig("purpose", "no_second_workflow_authority") == true, "purpose.no_second_workflow_authority 必須為 true", failures)
assert(spec["runtime_independence"] == true, "runtime_independence 必須為 true", failures)

termination = spec.fetch("termination", {})
assert(
  sorted_set(termination.fetch("terminal_conditions", [])) == sorted_set(EXPECTED_TERMINAL_CONDITIONS),
  "termination.terminal_conditions 與鎖定清單不符",
  failures
)

scope_lock = spec.fetch("scope_lock", {})
assert(scope_lock.fetch("fillable_fields", []) == EXPECTED_FILLABLE_FIELDS, "scope_lock.fillable_fields 必須是 [status, evidence_refs]", failures)
assert(
  sorted_set(scope_lock.fetch("forbidden_fill_fields", [])) == sorted_set(EXPECTED_FORBIDDEN_FILL_FIELDS),
  "scope_lock.forbidden_fill_fields 與鎖定清單不符",
  failures
)
# fillable ∪ forbidden 必須剛好涵蓋 ai-task-card-record.fields
card_fields = card_record_spec.fetch("fields", {}).keys
assert(
  sorted_set(EXPECTED_FILLABLE_FIELDS + EXPECTED_FORBIDDEN_FILL_FIELDS) == sorted_set(card_fields),
  "scope_lock 的 fillable ∪ forbidden 必須剛好等於 ai-task-card-record.fields",
  failures
)

run_record = spec.fetch("run_record", {})
assert(run_record.fetch("iteration_fields", []) == EXPECTED_ITERATION_FIELDS, "run_record.iteration_fields 與鎖定清單不符", failures)
assert(sorted_set(run_record.fetch("outcomes", [])) == sorted_set(EXPECTED_OUTCOMES), "run_record.outcomes 與鎖定清單不符", failures)
assert(run_record.fetch("outcome_condition_map", {}) == EXPECTED_OUTCOME_CONDITION_MAP, "run_record.outcome_condition_map 與鎖定對映不符", failures)
# outcome_condition_map 的值域必須 ⊆ terminal_conditions
map_conditions = EXPECTED_OUTCOME_CONDITION_MAP.values.flatten.uniq
assert((map_conditions - EXPECTED_TERMINAL_CONDITIONS).empty?, "outcome_condition_map 的 condition 必須都是 terminal_conditions 成員", failures)

authority = spec.fetch("authority", {})
assert(authority["performs_memory_acceptance"] == false, "authority.performs_memory_acceptance 必須是 false", failures)
assert(authority["writes_company_knowledge"] == false, "authority.writes_company_knowledge 必須是 false", failures)
assert(authority["error_behavior"] == "FAIL_LOUD", "authority.error_behavior 必須是 FAIL_LOUD", failures)
assert(
  sorted_set(authority.fetch("forbidden_run_fields", [])) == sorted_set(EXPECTED_FORBIDDEN_RUN_FIELDS),
  "authority.forbidden_run_fields 與鎖定清單不符",
  failures
)
boundary_error_enum = boundary.dig("automated_step_contract", "error_behavior_enum").to_a
assert(boundary_error_enum == %w[FAIL_LOUD], "boundary automated_step_contract.error_behavior_enum 必須是 [FAIL_LOUD]", failures)
assert(authority["error_behavior"] == boundary_error_enum.first, "authority.error_behavior 必須與 boundary error_behavior_enum 一致", failures)

# cross-reference pointer binding
must_match = spec.dig("cross_reference", "must_match") || {}
{
  "card_fields_from" => "ai-task-card-record.fields",
  "status_enum_from" => "ai-task-card-record.status_enum",
  "draft_card_from" => "ai-work-record-skill.output_contract.draft_card",
  "error_behavior_from" => "ai-work-record-boundary.automated_step_contract.error_behavior_enum"
}.each do |pointer_key, expected_path|
  assert(must_match[pointer_key] == expected_path, "cross_reference.must_match.#{pointer_key} 必須是 #{expected_path}", failures)
end
assert(present?(card_record_spec.fetch("fields", {})), "card-record fields 必須存在且非空", failures)
assert(present?(card_record_spec.fetch("status_enum", [])), "card-record status_enum 必須存在且非空", failures)
assert(present?(skill_spec.dig("output_contract", "draft_card_rule")), "skill output_contract.draft_card 規則必須存在", failures)
assert(present?(boundary.dig("automated_step_contract", "error_behavior_enum")), "boundary error_behavior_enum 必須存在且非空", failures)

declared_loop_codes = spec.fetch("error_contract", {}).keys
reachable_loop_codes = reachable_loop_failure_codes
assert(!reachable_loop_codes.empty?, "無法從 loop_closeout_failure 原始碼掃出任何 code,掃描失效", failures)

# SSP302-F-01：先確認 evaluator 沒有使用掃描認不得的 return 形式,
# 否則下面的「宣告 == 可回傳」比對建立在一個會低估的集合上。
unexpected_returns = unexpected_evaluator_return_forms
assert(
  unexpected_returns.empty?,
  "loop_closeout_failure 出現 reachable_loop_failure_codes 掃不到的 return 形式" \
  "（只允許 return nil 或 return \"<CODE>\"）：#{unexpected_returns.join(" ／ ")}",
  failures
)
assert(
  sorted_set(declared_loop_codes) == sorted_set(reachable_loop_codes),
  "error_contract 必須逐字等於 evaluator 實際可回傳的 code 集合：" \
  "僅宣告 #{(sorted_set(declared_loop_codes) - sorted_set(reachable_loop_codes)).to_a.join(", ")}；" \
  "僅可回傳 #{(sorted_set(reachable_loop_codes) - sorted_set(declared_loop_codes)).to_a.join(", ")}",
  failures
)
assert(
  sorted_set(reachable_loop_codes) == sorted_set(EXPECTED_LOOP_ERROR_CODES),
  "evaluator 可回傳的 code 集合已偏離鎖定清單（新增/移除 code 須經契約變更）",
  failures
)
spec.fetch("error_contract", {}).each do |code, event|
  assert(present?(event), "error_contract.#{code} 必須宣告事件名", failures)
end
assert(present?(spec.dig("termination", "timeout_reached_rule")),
       "termination.timeout_reached_rule 必須存在（F-05 反向一致性的規範文字）", failures)
assert(present?(spec.dig("run_record", "required_present_rule")),
       "run_record.required_present_rule 必須存在（F-04 CLOSED 語意的規範文字）", failures)
assert(
  sorted_set(spec.fetch("required_negative_fixtures", [])) == sorted_set(EXPECTED_LOOP_NEGATIVE_LABELS),
  "required_negative_fixtures 與鎖定 label 清單不符",
  failures
)

positive = read_json(POSITIVE_FIXTURE_PATH)
negative = read_json(NEGATIVE_FIXTURE_PATH)

positive.fetch("loop_closeout_cases").each do |test_case|
  assert(test_case.fetch("expected") == "allow", "#{test_case.fetch("case_id")} loop positive 必須預期 allow", failures)
  actual = loop_closeout_failure(test_case.fetch("run"), EXPECTED_FILLABLE_FIELDS, EXPECTED_OUTCOME_CONDITION_MAP)
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際被拒：#{actual}", failures)
end

negative.fetch("loop_closeout_negative_cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  assert(test_case.fetch("expected") == "deny", "#{case_id} loop negative 必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")
  actual = loop_closeout_failure(test_case.fetch("run"), EXPECTED_FILLABLE_FIELDS, EXPECTED_OUTCOME_CONDITION_MAP)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 failure code #{expected_code}，實際 #{actual.inspect}", failures)
end

covered_labels = sorted_set(negative.fetch("loop_closeout_negative_cases").map { |test_case| test_case.fetch("covers_loop_negative_fixture") })
missing_labels = sorted_set(EXPECTED_LOOP_NEGATIVE_LABELS) - covered_labels
assert(missing_labels.empty?, "loop negative fixtures 未覆蓋：#{missing_labels.join(", ")}", failures)

# TIGHTEN-F-01 的第二層保險：evaluator 每一個可回傳的 code 都必須有負例實際踩到。
# 只驗「宣告集合相符」不夠——一個從未被任何 fixture 觸發的分支,改壞了也不會轉紅。
covered_codes = sorted_set(negative.fetch("loop_closeout_negative_cases").map { |test_case| test_case.fetch("expected_failure_code") })
uncovered_codes = sorted_set(reachable_loop_codes) - covered_codes
assert(uncovered_codes.empty?, "以下 failure code 沒有任何負例覆蓋：#{uncovered_codes.to_a.join(", ")}", failures)
negative.fetch("loop_closeout_negative_cases").each do |test_case|
  code = test_case.fetch("expected_failure_code")
  assert(declared_loop_codes.include?(code), "#{test_case.fetch("case_id")} 的 expected_failure_code #{code} 未在 error_contract 宣告", failures)
end

if failures.empty?
  puts "PASS ai work record loop contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
