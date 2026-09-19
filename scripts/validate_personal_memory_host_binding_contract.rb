#!/usr/bin/env ruby
# frozen_string_literal: true

# EMEM-11 切片 2｜Codex + Claude Code Host Binding
#
# 驗證單位是一個完整 host-binding scenario：install safe merge、uninstall、
# higher-precedence conflict、host health、SessionStart bootstrap 一起驗。
# evaluator 位於 scripts/lib/personal_memory_host_binding.rb，Slice 3 可直接重用。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"
require_relative "lib/personal_memory_host_binding"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-host-binding-fixtures.json")
HELPER_PATH = File.join(__dir__, "lib/personal_memory_host_binding.rb")

HB = PersonalMemoryHostBinding
HB_PATH = File.join(__dir__, "lib/personal_memory_host_binding.rb")
EXPECTED_V1_HOSTS = ["Codex", "Claude Code"].freeze
EXPECTED_INVARIANTS = %w[
  GLOBAL_HARNESS_NE_GLOBAL_MEMORY_VISIBILITY
  PROJECT_CONTEXT_MAY_NARROW_BUT_NOT_WIDEN_MEMORY_ACCESS
  HOST_INSTRUCTION_NE_MEMORY_AUTHORITY
  HOST_NATIVE_MEMORY_NE_PERSONAL_TRUTH
  MISSING_OR_CONFLICTED_HOST_BINDING_FAILS_CLOSED
].freeze
ALLOWED_HEALTH_FIELDS = HB::HEALTH_FAILURES.keys.freeze

def apply_mutation(base, test_case)
  return deep_dup(test_case["replace_run"]) if test_case.key?("replace_run")

  run = deep_dup(base)
  mutation = test_case["mutate"] || {}
  (mutation["set"] || {}).each { |path, value| set_path(run, path, value) }
  (mutation["delete"] || []).each { |path| delete_path(run, path) }
  (mutation["append"] || {}).each { |path, value| read_path(run, path) << value }
  run
end

def host_set_bound?(runtime_hosts, profiles)
  sorted_set(runtime_hosts) == sorted_set(profiles.keys)
end

failures = []
spec = read_yaml(SPEC_PATH)
fixtures = read_json(FIXTURE_PATH)
contract = spec.fetch("personal_memory_host_binding_v1", {})
runtime = spec.fetch("personal_memory_runtime", {})
profiles = contract.fetch("host_profiles", {})
runtime_hosts = runtime.fetch("supported_hosts_v1", [])
optional_executors = spec.dig("runtime_policy", "optional_executors") || []

assert(contract["slice_of"].to_s.include?("EMEM-11"), "host binding contract 必須標明 EMEM-11", failures)
assert(sorted_set(contract.fetch("invariants", [])) == sorted_set(EXPECTED_INVARIANTS),
       "host binding invariants 必須逐項等於主卡五條 invariant", failures)

# v1 delivery scope 的權威是兩個具體 host profile；runtime list 必須一對一跟它綁定。
assert(sorted_set(profiles.keys) == sorted_set(EXPECTED_V1_HOSTS),
       "v1 host_profiles 必須恰為 Codex + Claude Code", failures)
assert(host_set_bound?(runtime_hosts, profiles),
       "personal_memory_runtime.supported_hosts_v1 必須與 host_profiles 一對一", failures)
assert((sorted_set(runtime_hosts) - sorted_set(optional_executors)).empty?,
       "supported_hosts_v1 仍必須是 runtime_policy.optional_executors 子集", failures)

# Slice 1 residual 的 live drift probe：只往 runtime list 加第三個 executor，不能再 PASS。
drifted_hosts = deep_dup(runtime_hosts) << "DeepSeek Harness"
assert(!host_set_bound?(drifted_hosts, profiles),
       "supported_hosts_v1 漂移探針失效：只加第三個 host 應破壞一對一綁定", failures)

expected_adapter_paths = {
  "Codex" => "規格/v0.1/codex-native-adapter.yaml",
  "Claude Code" => "規格/v0.1/claude-code-native-adapter.yaml"
}
expected_conflict_scopes = {
  "Codex" => %w[PROJECT],
  "Claude Code" => %w[PROJECT LOCAL]
}

profiles.each do |host, profile|
  assert(profile.is_a?(Hash), "#{host} host profile 必須是 mapping", failures)
  assert(profile["user_config_scope"] == "USER", "#{host} 只能安裝 user-scope binding", failures)
  assert(profile["native_adapter_spec"] == expected_adapter_paths.fetch(host),
         "#{host} native_adapter_spec 必須指向既有 sibling adapter", failures)

  adapter_path = File.join(ROOT, profile["native_adapter_spec"].to_s)
  assert(File.exist?(adapter_path), "#{host} native adapter 檔案必須存在", failures)
  if File.exist?(adapter_path)
    adapter = read_yaml(adapter_path)
    authority = adapter.fetch("authority", {})
    %w[grants_acceptance grants_permission grants_canonical_writer].each do |key|
      assert(authority[key] == false, "#{host} adapter 不得取得 #{key}", failures)
    end
  end

  mcp = profile.fetch("mcp_registration", {})
  hook = profile.fetch("session_start_registration", {})
  assert(mcp["id"].to_s.start_with?("omos."), "#{host} MCP id 必須 namespaced", failures)
  assert(mcp["transport"] == "STDIO", "#{host} MCP transport 必須是 STDIO", failures)
  assert(!HB.blank?(mcp["command_ref"]), "#{host} MCP command_ref 不得空白", failures)
  assert(hook["id"].to_s.start_with?("omos."), "#{host} hook id 必須 namespaced", failures)
  assert(hook["event"] == "SessionStart", "#{host} bootstrap hook 必須是 SessionStart", failures)
  assert(!HB.blank?(hook["command_ref"]), "#{host} SessionStart command_ref 不得空白", failures)

  scopes = profile.fetch("higher_precedence_conflict_scopes", [])
  assert(scopes.is_a?(Array) && scopes.any? && scopes.uniq == scopes,
         "#{host} higher_precedence_conflict_scopes 必須是非空無重複陣列", failures)
  assert(!scopes.include?("USER"), "#{host} conflict scopes 不得把 user scope 當成 higher-precedence", failures)
  assert(sorted_set(scopes) == sorted_set(expected_conflict_scopes.fetch(host)),
         "#{host} conflict scopes 必須覆蓋主卡已確認的 precedence surface", failures)

  health = profile.fetch("required_health", [])
  assert(health.is_a?(Array) && health.any? && health.uniq == health,
         "#{host} required_health 必須是非空無重複陣列", failures)
  assert((health - ALLOWED_HEALTH_FIELDS).empty?, "#{host} required_health 含 evaluator 不認得的欄位", failures)
  %w[mcp_visible session_start_hook_active runtime_compatible].each do |field|
    assert(health.include?(field), "#{host} required_health 必須含 #{field}", failures)
  end
end
assert(profiles.dig("Codex", "required_health").include?("project_trusted"),
       "Codex 必須驗 project trust", failures)

snapshot = contract.fetch("config_snapshot_contract", {})
assert(sorted_set(snapshot.fetch("fields", [])) == sorted_set(HB::CONFIG_FIELDS),
       "config_snapshot_contract.fields 必須與 evaluator config shape 一致", failures)

bootstrap_contract = contract.fetch("bootstrap_contract", {})
assert(sorted_set(bootstrap_contract.fetch("input_fields", [])) == sorted_set(HB::BOOTSTRAP_FIELDS),
       "bootstrap_contract.input_fields 必須與 evaluator 一致", failures)
assert(bootstrap_contract["runtime_scope_mode_ref"] == "employee_memory_scope_modes.modes",
       "runtime_scope_mode 必須綁既有 employee scope vocabulary", failures)
assert(bootstrap_contract["runtime_scope_definition_ref"] == "ownership_visibility_contract.mode_definitions",
       "runtime scope 必須由既有 mode_definitions 解析", failures)
assert(bootstrap_contract["project_visibility_scope_ref"] == "ownership_visibility_contract.visibility_scopes",
       "project narrowing 必須綁既有 visibility_scopes", failures)
input_authority = bootstrap_contract.fetch("input_authority", {})
authority_groups = %w[host_native_inputs runtime_policy_inputs project_context_inputs derived_outputs]
authority_fields = authority_groups.flat_map { |group| input_authority.fetch(group, []) }
assert(authority_fields.uniq.length == authority_fields.length,
       "bootstrap input authority 分組不得重疊", failures)
assert(sorted_set(authority_fields) == sorted_set(HB::BOOTSTRAP_FIELDS),
       "bootstrap 每個欄位必須恰有一個 authority 分組", failures)
assert(input_authority.fetch("runtime_policy_inputs", []) == %w[runtime_scope_mode],
       "runtime_scope_mode 只能由 runtime policy 輸入", failures)
assert(!input_authority.fetch("project_context_inputs", []).include?("runtime_scope_mode"),
       "project context 不得提供 runtime_scope_mode", failures)
assert(input_authority.fetch("derived_outputs", []) == %w[produced_binding],
       "produced_binding 必須是 derived output，不是 caller authority", failures)

failure_policy = contract.fetch("failure_policy", {})
%w[broken_binding shadowed_binding incompatible_runtime].each do |key|
  assert(failure_policy[key] == "FAIL_CLOSED", "#{key} 必須 FAIL_CLOSED", failures)
end
assert(failure_policy["vendor_native_memory_fallback"] == "FORBIDDEN",
       "Host binding 失敗不得 silent fallback 到 vendor-native memory", failures)

authority = contract.fetch("authority", {})
%w[grants_personal_memory_governance grants_company_canonical_writer grants_promotion grants_acceptance].each do |key|
  assert(authority[key] == false, "Host Adapter 不得取得 #{key}", failures)
end
assert(authority["project_instruction_is_context_only"] == true,
       "project instruction 必須明確只是 context", failures)

identity_fields = spec.dig("runtime_policy", "portable_record_contract", "executor_provenance_fields") || []
binding_spec = runtime.fetch("host_session_binding", {})
binding_additional = binding_spec.fetch("additional_fields", [])
binding_forbidden = binding_spec.fetch("forbidden_fields", [])

BINDINGS = {
  supported_hosts: runtime_hosts,
  host_profiles: profiles,
  scope_modes: spec.dig("employee_memory_scope_modes", "modes") || [],
  mode_definitions: spec.dig("ownership_visibility_contract", "mode_definitions") || {},
  visibility_scopes: spec.dig("ownership_visibility_contract", "visibility_scopes") || {},
  binding_allowed_fields: identity_fields + binding_additional,
  binding_forbidden_fields: binding_forbidden,
  # repair-01 P1-1：切片 1 runtime 判定 binding 用的同一組參數。
  runtime_binding_shape: {
    identity_fields: identity_fields,
    additional_fields: binding_additional,
    allowed_fields: identity_fields + binding_additional,
    forbidden_fields: binding_forbidden,
    supported_hosts: runtime_hosts,
    visibility_scopes: (spec.dig("ownership_visibility_contract", "visibility_scopes") || {}).keys
  }
}.freeze

assert(sorted_set(binding_additional) == sorted_set(%w[cwd project_ref effective_scope]),
       "Slice 2 bootstrap 依賴的 HostSessionBinding additional_fields 漂移", failures)

# repair-02 附帶：health_problem 用 HEALTH_FAILURES.fetch(field)，上游若為某個
# profile 新增一個沒有對應碼的 required_health 欄位，會丟 KeyError 當掉，而不是
# 回一個已宣告的錯誤碼——那等於 error contract 涵蓋不到的出口。這裡在契約層
# 先擋住。
profiles.each do |host, profile|
  unknown_health = (profile["required_health"] || []) - HB::HEALTH_FAILURES.keys
  assert(unknown_health.empty?,
         "#{host} 的 required_health 有沒有對應錯誤碼的欄位（會使 evaluator 丟 KeyError）：#{unknown_health.inspect}", failures)
end

bases = fixtures.fetch("bases", {})
assert(sorted_set(bases.keys) == sorted_set(%w[CODEX CLAUDE]), "fixtures 必須含兩個 Host base", failures)
bases.each do |name, run|
  actual = HB.scenario_failure(run, BINDINGS)
  assert(actual.nil?, "#{name} base 必須通過，實際 #{actual.inspect}", failures)
end

fixtures.fetch("positive_cases", []).each do |test_case|
  base = bases.fetch(test_case.fetch("base_ref"))
  run = apply_mutation(base, test_case)
  assert(canonical_json(run) != canonical_json(base) || !test_case.key?("mutate"),
         "#{test_case.fetch("case_id")} 宣告 mutation 時必須真的改變 base", failures)
  actual = HB.scenario_failure(run, BINDINGS)
  assert(actual.nil?, "#{test_case.fetch("case_id")} 預期 allow，實際 #{actual.inspect}", failures)
end

observed_codes = Set.new
fixtures.fetch("negative_cases", []).each do |test_case|
  base = bases.fetch(test_case.fetch("base_ref"))
  run = apply_mutation(base, test_case)
  unless test_case.key?("replace_run")
    mutation = test_case.fetch("mutate", {})
    assert(mutation.is_a?(Hash) && mutation.any?,
           "#{test_case.fetch("case_id")} 必須用明寫 mutation，不可重貼另一份 base", failures)
    assert(canonical_json(run) != canonical_json(base),
           "#{test_case.fetch("case_id")} mutation 必須真的改變 base", failures)
  end
  expected = test_case.fetch("expected_failure_code")
  actual = HB.scenario_failure(run, BINDINGS)
  observed_codes << actual unless actual.nil?
  assert(!actual.nil?, "#{test_case.fetch("case_id")} 預期 deny，實際通過", failures)
  assert(actual == expected, "#{test_case.fetch("case_id")} 預期 #{expected}，實際 #{actual.inspect}", failures)
end

# 三個只能靠 upstream/contract drift 觸發的 return site，獨立探測。
profile_drift = deep_dup(BINDINGS)
profile_drift[:host_profiles] = deep_dup(profiles)
profile_drift[:host_profiles].delete("Codex")
code = HB.scenario_failure(bases.fetch("CODEX"), profile_drift)
observed_codes << code
assert(code == "HBV1_HOST_PROFILE_MISSING", "host profile missing drift probe 應 fail closed", failures)

mode_drift = deep_dup(BINDINGS)
mode_drift[:mode_definitions] = deep_dup(BINDINGS[:mode_definitions])
mode_drift[:mode_definitions]["SHARED_WORK_CONTEXT"]["visibility_scope"] = "REMOVED_SCOPE"
code = HB.scenario_failure(bases.fetch("CODEX"), mode_drift)
observed_codes << code
assert(code == "HBV1_RUNTIME_SCOPE_MODE_UNBOUND", "mode->visibility drift probe 應 fail closed", failures)

reader_drift = deep_dup(BINDINGS)
reader_drift[:visibility_scopes] = deep_dup(BINDINGS[:visibility_scopes])
reader_drift[:visibility_scopes]["SELF_ONLY"]["default_readers"] = "not-an-array"
code = HB.scenario_failure(bases.fetch("CODEX"), reader_drift)
observed_codes << code
assert(code == "HBV1_VISIBILITY_READERS_NOT_ARRAY", "default_readers drift probe 應 fail closed", failures)

# return-site coverage：每個 helper 內的 literal error code，加上 action 動態展開的
# install/uninstall codes，都必須由 fixture 或上面三個 drift probe 真正回傳過。
literal_codes = File.read(HELPER_PATH).scan(/HBV1_[A-Z0-9_]+/).to_set
# repair-01 把 install/uninstall 的插值出口拆成字面碼之後，原本手列的
# dynamic_codes 已完全被 literal_codes 涵蓋（實測差集為空）——留著就是第二份
# 會漂移的清單，故移除。
missing_guard_codes = literal_codes - observed_codes
assert(missing_guard_codes.empty?,
       "Host Binding return-site coverage 缺少：#{missing_guard_codes.to_a.sort.join(', ')}", failures)

# 重要 guard 的組合證明：改上游 profile 的 own MCP payload，既有合法 fixture 必須轉紅。
binding_drift = deep_dup(BINDINGS)
binding_drift[:host_profiles] = deep_dup(profiles)
binding_drift[:host_profiles]["Codex"]["mcp_registration"]["command_ref"] = "DRIFTED_COMMAND"
code = HB.scenario_failure(bases.fetch("CODEX"), binding_drift)
assert(code == "HBV1_INSTALL_NOT_SAFE_MERGE",
       "Codex MCP profile 漂移必須先由 safe-merge guard 擋下", failures)

# --- error contract（repair-01 P2-1）--------------------------------------
#
# 原本本片沒有 ERROR_CONTRACT，而且 merge_problem 的三個出口是字串插值，
# LoopReturnContract 的可達碼掃描對它們回傳 0——等於錯誤碼與 evaluator
# 之間沒有任何機器綁定。現在出口全部可靜態列舉，這裡做雙向斷言。

ERROR_CONTRACT = {
  "HBV1_MCP_NOT_VISIBLE" => "personal_memory_host_binding_v1.error.mcp_not_visible",
  "HBV1_PROJECT_SCOPE_WIDENS_BASELINE" => "personal_memory_host_binding_v1.error.project_scope_widens_baseline",
  "HBV1_PROJECT_UNTRUSTED" => "personal_memory_host_binding_v1.error.project_untrusted",
  "HBV1_PROJECT_VISIBILITY_SCOPE_UNKNOWN" => "personal_memory_host_binding_v1.error.project_visibility_scope_unknown",
  "HBV1_RUNTIME_INCOMPATIBLE" => "personal_memory_host_binding_v1.error.runtime_incompatible",
  "HBV1_RUNTIME_SCOPE_MODE_UNBOUND" => "personal_memory_host_binding_v1.error.runtime_scope_mode_unbound",
  "HBV1_RUNTIME_SCOPE_MODE_UNKNOWN" => "personal_memory_host_binding_v1.error.runtime_scope_mode_unknown",
  "HBV1_SESSION_START_HOOK_INACTIVE" => "personal_memory_host_binding_v1.error.session_start_hook_inactive",
  "HBV1_VISIBILITY_READERS_NOT_ARRAY" => "personal_memory_host_binding_v1.error.visibility_readers_not_array",
  "HBV1_BOOTSTRAP_NOT_MAP" => "personal_memory_host_binding_v1.error.bootstrap_not_map",
  "HBV1_BOOTSTRAP_UNKNOWN_FIELD" => "personal_memory_host_binding_v1.error.bootstrap_unknown_field",
  "HBV1_CONFIG_NOT_MAP" => "personal_memory_host_binding_v1.error.config_not_map",
  "HBV1_CONFIG_UNKNOWN_FIELD" => "personal_memory_host_binding_v1.error.config_unknown_field",
  "HBV1_CWD_MISSING" => "personal_memory_host_binding_v1.error.cwd_missing",
  "HBV1_CWD_NOT_BOUND" => "personal_memory_host_binding_v1.error.cwd_not_bound",
  "HBV1_EFFECTIVE_HOOK_MISSING_OR_DRIFTED" => "personal_memory_host_binding_v1.error.effective_hook_missing_or_drifted",
  "HBV1_EFFECTIVE_MCP_MISSING_OR_DRIFTED" => "personal_memory_host_binding_v1.error.effective_mcp_missing_or_drifted",
  "HBV1_EFFECTIVE_SCOPE_NOT_DERIVED" => "personal_memory_host_binding_v1.error.effective_scope_not_derived",
  "HBV1_EFFECTIVE_USER_CONFIG_NOT_INSTALL_RESULT" => "personal_memory_host_binding_v1.error.effective_user_config_not_install_result",
  "HBV1_EXECUTOR_REF_NOT_HOST" => "personal_memory_host_binding_v1.error.executor_ref_not_host",
  "HBV1_EXECUTOR_SESSION_REF_NOT_NATIVE_SESSION" => "personal_memory_host_binding_v1.error.executor_session_ref_not_native_session",
  "HBV1_HIGHER_PRECEDENCE_NOT_MAP" => "personal_memory_host_binding_v1.error.higher_precedence_not_map",
  "HBV1_HIGHER_PRECEDENCE_SCOPE_MISSING" => "personal_memory_host_binding_v1.error.higher_precedence_scope_missing",
  "HBV1_HIGHER_PRECEDENCE_SCOPE_UNKNOWN" => "personal_memory_host_binding_v1.error.higher_precedence_scope_unknown",
  "HBV1_HOST_HEALTH_FIELD_MISSING" => "personal_memory_host_binding_v1.error.host_health_field_missing",
  "HBV1_HOST_HEALTH_NOT_MAP" => "personal_memory_host_binding_v1.error.host_health_not_map",
  "HBV1_HOST_HEALTH_UNKNOWN_FIELD" => "personal_memory_host_binding_v1.error.host_health_unknown_field",
  "HBV1_HOST_NOT_SUPPORTED" => "personal_memory_host_binding_v1.error.host_not_supported",
  "HBV1_HOST_PROFILE_MISSING" => "personal_memory_host_binding_v1.error.host_profile_missing",
  "HBV1_INSTALL_NOT_MAP" => "personal_memory_host_binding_v1.error.install_not_map",
  "HBV1_INSTALL_NOT_SAFE_MERGE" => "personal_memory_host_binding_v1.error.install_not_safe_merge",
  "HBV1_INSTALL_UNKNOWN_FIELD" => "personal_memory_host_binding_v1.error.install_unknown_field",
  "HBV1_MCP_ENTRIES_NOT_MAP" => "personal_memory_host_binding_v1.error.mcp_entries_not_map",
  "HBV1_MCP_SHADOWED" => "personal_memory_host_binding_v1.error.mcp_shadowed",
  "HBV1_NATIVE_SESSION_ID_MISSING" => "personal_memory_host_binding_v1.error.native_session_id_missing",
  "HBV1_PRODUCED_BINDING_INCOMPLETE" => "personal_memory_host_binding_v1.error.produced_binding_incomplete",
  "HBV1_PRODUCED_BINDING_NOT_MAP" => "personal_memory_host_binding_v1.error.produced_binding_not_map",
  "HBV1_PRODUCED_BINDING_REJECTED_BY_RUNTIME" => "personal_memory_host_binding_v1.error.produced_binding_rejected_by_runtime",
  "HBV1_PRODUCED_BINDING_SHADOW_IDENTITY_FIELD" => "personal_memory_host_binding_v1.error.produced_binding_shadow_identity_field",
  "HBV1_PRODUCED_BINDING_UNKNOWN_FIELD" => "personal_memory_host_binding_v1.error.produced_binding_unknown_field",
  "HBV1_PROJECT_REF_MISSING" => "personal_memory_host_binding_v1.error.project_ref_missing",
  "HBV1_PROJECT_REF_NOT_BOUND" => "personal_memory_host_binding_v1.error.project_ref_not_bound",
  "HBV1_RUN_NOT_MAP" => "personal_memory_host_binding_v1.error.run_not_map",
  "HBV1_RUN_UNKNOWN_FIELD" => "personal_memory_host_binding_v1.error.run_unknown_field",
  "HBV1_SESSION_START_HOOKS_NOT_ARRAY" => "personal_memory_host_binding_v1.error.session_start_hooks_not_array",
  "HBV1_SESSION_START_HOOK_CONFLICT" => "personal_memory_host_binding_v1.error.session_start_hook_conflict",
  "HBV1_SESSION_START_HOOK_ID_INVALID" => "personal_memory_host_binding_v1.error.session_start_hook_id_invalid",
  "HBV1_SESSION_START_HOOK_NOT_MAP" => "personal_memory_host_binding_v1.error.session_start_hook_not_map",
  "HBV1_UNINSTALL_INPUT_NOT_INSTALL_RESULT" => "personal_memory_host_binding_v1.error.uninstall_input_not_install_result",
  "HBV1_UNINSTALL_NOT_MAP" => "personal_memory_host_binding_v1.error.uninstall_not_map",
  "HBV1_UNINSTALL_NOT_SAFE_MERGE" => "personal_memory_host_binding_v1.error.uninstall_not_safe_merge",
  "HBV1_UNINSTALL_UNKNOWN_FIELD" => "personal_memory_host_binding_v1.error.uninstall_unknown_field"
}.freeze

# repair-02：斷言基準改成「evaluator 原始碼裡出現的每一個 HBV1_ 字面量」，
# 不再用 AST 的 reachable_codes 當權威。上一輪 43 = 43 之所以是假一致，正是
# 因為 reachable_codes 只看 `return "字面量"` 這一種出口形式：
#   - health_problem 的 `return HEALTH_FAILURES.fetch(field)`（表格查詢）
#   - derived_effective_scope 的 `[nil, "HBV1_..."]` 再由呼叫端 `return scope_problem` 轉送
# 兩者 runtime 真的會吐，掃描器卻完全看不見（實測少了 9 碼）。
# 字面量掃描對「出口用什麼形式回傳」不敏感，因此不會再出現同一類假一致。
evaluator_source = File.readlines(HB_PATH).reject { |line| line.strip.start_with?("#") }.join
source_codes = evaluator_source.scan(/HBV1_[A-Z0-9_]+/).uniq
assert((source_codes - ERROR_CONTRACT.keys).empty?,
       "evaluator 原始碼有但 error_contract 未宣告：#{(source_codes - ERROR_CONTRACT.keys).sort.inspect}", failures)
assert((ERROR_CONTRACT.keys - source_codes).empty?,
       "error_contract 宣告但 evaluator 原始碼沒有：#{(ERROR_CONTRACT.keys - source_codes).sort.inspect}", failures)

# AST 可達碼降級為「子集」斷言：它仍能抓到 return 位置的漂移，但不再是權威。
EVALUATOR_DEFS = File.readlines(HB_PATH).grep(/^  def /).map { |line| line[/def ([a-z_0-9?]+)/, 1] }
reachable_codes = EVALUATOR_DEFS.flat_map { |fn| LoopReturnContract.reachable_codes(HB_PATH, fn) }.uniq
assert((reachable_codes - ERROR_CONTRACT.keys).empty?,
       "AST 可達碼未被 error_contract 涵蓋：#{(reachable_codes - ERROR_CONTRACT.keys).sort.inspect}", failures)

# 防回歸：出口不得再出現字串插值，否則上面的掃描會再次靜默失效。
interpolated = File.readlines(HB_PATH).each_with_index
                   .reject { |line, _| line.strip.start_with?("#") }
                   .select { |line, _| line =~ /return "[^"]*\#\{/ }
                   .map { |_, i| i + 1 }
assert(interpolated.empty?,
       "evaluator 出口不得使用字串插值（可達碼掃描會看不見）：行 #{interpolated.inspect}", failures)

if failures.empty?
  puts "PASS personal memory host binding contract validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
