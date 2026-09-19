# frozen_string_literal: true

# EMEM-11 切片 2 共用 evaluator。Slice 3 的 installer / doctor 直接重用。
require_relative "omos_contract_helpers"

module PersonalMemoryHostBinding
  module_function

  SCENARIO_FIELDS = %w[host install uninstall effective_user_config higher_precedence host_health bootstrap].freeze
  CONFIG_FIELDS = %w[mcp_entries session_start_hooks].freeze
  BOOTSTRAP_FIELDS = %w[native_session_id cwd project_ref runtime_scope_mode project_visibility_scope produced_binding].freeze
  HEALTH_FAILURES = {
    "project_trusted" => "HBV1_PROJECT_UNTRUSTED",
    "mcp_visible" => "HBV1_MCP_NOT_VISIBLE",
    "session_start_hook_active" => "HBV1_SESSION_START_HOOK_INACTIVE",
    "runtime_compatible" => "HBV1_RUNTIME_INCOMPATIBLE"
  }.freeze

  def blank?(value)
    value.nil? || (value.respond_to?(:empty?) && value.empty?) || (value.is_a?(String) && value.strip.empty?)
  end

  def config_problem(config)
    return "HBV1_CONFIG_NOT_MAP" unless config.is_a?(Hash)
    return "HBV1_CONFIG_UNKNOWN_FIELD" unless (config.keys - CONFIG_FIELDS).empty?
    return "HBV1_MCP_ENTRIES_NOT_MAP" unless config["mcp_entries"].is_a?(Hash)
    hooks = config["session_start_hooks"]
    return "HBV1_SESSION_START_HOOKS_NOT_ARRAY" unless hooks.is_a?(Array)
    return "HBV1_SESSION_START_HOOK_NOT_MAP" unless hooks.all? { |hook| hook.is_a?(Hash) }
    return "HBV1_SESSION_START_HOOK_ID_INVALID" unless hooks.all? { |hook| !blank?(hook["id"]) }
    nil
  end

  def expected_install(before_config, profile)
    expected = deep_dup(before_config)
    own_mcp = profile.fetch("mcp_registration")
    own_hook = profile.fetch("session_start_registration")
    expected["mcp_entries"][own_mcp.fetch("id")] = own_mcp.reject { |key, _| key == "id" }
    expected["session_start_hooks"] = expected["session_start_hooks"].reject { |hook| hook["id"] == own_hook.fetch("id") }
    expected["session_start_hooks"] << own_hook
    expected
  end

  def expected_uninstall(before_config, profile)
    expected = deep_dup(before_config)
    own_mcp_id = profile.dig("mcp_registration", "id")
    own_hook_id = profile.dig("session_start_registration", "id")
    expected["mcp_entries"].delete(own_mcp_id)
    expected["session_start_hooks"] = expected["session_start_hooks"].reject { |hook| hook["id"] == own_hook_id }
    expected
  end

  def merge_problem(node, profile, action)
    return "HBV1_#{action}_NOT_MAP" unless node.is_a?(Hash)
    return "HBV1_#{action}_UNKNOWN_FIELD" unless (node.keys - %w[before after]).empty?
    before = node["before"]
    after = node["after"]
    problem = config_problem(before)
    return problem unless problem.nil?
    problem = config_problem(after)
    return problem unless problem.nil?
    expected = action == "INSTALL" ? expected_install(before, profile) : expected_uninstall(before, profile)
    return "HBV1_#{action}_NOT_SAFE_MERGE" unless canonical_json(after) == canonical_json(expected)
    nil
  end

  def own_registration_problem(config, profile)
    problem = config_problem(config)
    return problem unless problem.nil?
    own_mcp = profile.fetch("mcp_registration")
    own_hook = profile.fetch("session_start_registration")
    actual_mcp = config["mcp_entries"][own_mcp.fetch("id")]
    expected_mcp = own_mcp.reject { |key, _| key == "id" }
    return "HBV1_EFFECTIVE_MCP_MISSING_OR_DRIFTED" unless canonical_json(actual_mcp) == canonical_json(expected_mcp)
    matching_hooks = config["session_start_hooks"].select { |hook| hook["id"] == own_hook.fetch("id") }
    return "HBV1_EFFECTIVE_HOOK_MISSING_OR_DRIFTED" unless matching_hooks.length == 1 && canonical_json(matching_hooks.first) == canonical_json(own_hook)
    nil
  end

  def precedence_problem(higher_precedence, profile)
    return "HBV1_HIGHER_PRECEDENCE_NOT_MAP" unless higher_precedence.is_a?(Hash)
    allowed_scopes = profile.fetch("higher_precedence_conflict_scopes")
    return "HBV1_HIGHER_PRECEDENCE_SCOPE_UNKNOWN" unless (higher_precedence.keys - allowed_scopes).empty?
    return "HBV1_HIGHER_PRECEDENCE_SCOPE_MISSING" unless (allowed_scopes - higher_precedence.keys).empty?
    own_mcp_id = profile.dig("mcp_registration", "id")
    own_hook_id = profile.dig("session_start_registration", "id")
    higher_precedence.each_value do |config|
      problem = config_problem(config)
      return problem unless problem.nil?
      return "HBV1_MCP_SHADOWED" if config["mcp_entries"].key?(own_mcp_id)
      return "HBV1_SESSION_START_HOOK_CONFLICT" if config["session_start_hooks"].any? { |hook| hook["id"] == own_hook_id }
    end
    nil
  end

  def health_problem(health, profile)
    return "HBV1_HOST_HEALTH_NOT_MAP" unless health.is_a?(Hash)
    required = profile.fetch("required_health")
    return "HBV1_HOST_HEALTH_UNKNOWN_FIELD" unless (health.keys - required).empty?
    return "HBV1_HOST_HEALTH_FIELD_MISSING" unless required.all? { |field| health.key?(field) }
    required.each do |field|
      next if health[field] == true
      return HEALTH_FAILURES.fetch(field)
    end
    nil
  end

  def derived_effective_scope(bootstrap, bindings)
    runtime_mode = bootstrap["runtime_scope_mode"]
    return [nil, "HBV1_RUNTIME_SCOPE_MODE_UNKNOWN"] unless bindings[:scope_modes].include?(runtime_mode)
    baseline = bindings[:mode_definitions].dig(runtime_mode, "visibility_scope")
    return [nil, "HBV1_RUNTIME_SCOPE_MODE_UNBOUND"] unless bindings[:visibility_scopes].key?(baseline)
    requested = bootstrap["project_visibility_scope"]
    return [baseline, nil] if requested.nil?
    return [nil, "HBV1_PROJECT_VISIBILITY_SCOPE_UNKNOWN"] unless bindings[:visibility_scopes].key?(requested)
    baseline_readers = bindings[:visibility_scopes].dig(baseline, "default_readers")
    requested_readers = bindings[:visibility_scopes].dig(requested, "default_readers")
    return [nil, "HBV1_VISIBILITY_READERS_NOT_ARRAY"] unless baseline_readers.is_a?(Array) && requested_readers.is_a?(Array)
    return [nil, "HBV1_PROJECT_SCOPE_WIDENS_BASELINE"] unless requested_readers.to_set.subset?(baseline_readers.to_set)
    [requested, nil]
  end

  def bootstrap_problem(bootstrap, host, bindings)
    return "HBV1_BOOTSTRAP_NOT_MAP" unless bootstrap.is_a?(Hash)
    return "HBV1_BOOTSTRAP_UNKNOWN_FIELD" unless (bootstrap.keys - BOOTSTRAP_FIELDS).empty?
    return "HBV1_NATIVE_SESSION_ID_MISSING" if blank?(bootstrap["native_session_id"])
    return "HBV1_CWD_MISSING" if blank?(bootstrap["cwd"])
    return "HBV1_PROJECT_REF_MISSING" if blank?(bootstrap["project_ref"])
    effective_scope, scope_problem = derived_effective_scope(bootstrap, bindings)
    return scope_problem unless scope_problem.nil?
    produced = bootstrap["produced_binding"]
    return "HBV1_PRODUCED_BINDING_NOT_MAP" unless produced.is_a?(Hash)
    return "HBV1_PRODUCED_BINDING_SHADOW_IDENTITY_FIELD" if bindings[:binding_forbidden_fields].any? { |field| produced.key?(field) }
    return "HBV1_PRODUCED_BINDING_UNKNOWN_FIELD" unless (produced.keys - bindings[:binding_allowed_fields]).empty?
    return "HBV1_PRODUCED_BINDING_INCOMPLETE" unless bindings[:binding_allowed_fields].all? { |field| produced.key?(field) }
    return "HBV1_EXECUTOR_REF_NOT_HOST" unless produced["executor_ref"] == host
    return "HBV1_EXECUTOR_SESSION_REF_NOT_NATIVE_SESSION" unless produced["executor_session_ref"] == bootstrap["native_session_id"]
    return "HBV1_CWD_NOT_BOUND" unless produced["cwd"] == bootstrap["cwd"]
    return "HBV1_PROJECT_REF_NOT_BOUND" unless produced["project_ref"] == bootstrap["project_ref"]
    return "HBV1_EFFECTIVE_SCOPE_NOT_DERIVED" unless produced["effective_scope"] == effective_scope
    nil
  end

  def scenario_failure(run, bindings)
    return "HBV1_RUN_NOT_MAP" unless run.is_a?(Hash)
    return "HBV1_RUN_UNKNOWN_FIELD" unless (run.keys - SCENARIO_FIELDS).empty?
    host = run["host"]
    return "HBV1_HOST_NOT_SUPPORTED" unless bindings[:supported_hosts].include?(host)
    profile = bindings[:host_profiles][host]
    return "HBV1_HOST_PROFILE_MISSING" unless profile.is_a?(Hash)
    problem = merge_problem(run["install"], profile, "INSTALL")
    return problem unless problem.nil?
    problem = own_registration_problem(run["effective_user_config"], profile)
    return problem unless problem.nil?
    problem = merge_problem(run["uninstall"], profile, "UNINSTALL")
    return problem unless problem.nil?
    return "HBV1_EFFECTIVE_USER_CONFIG_NOT_INSTALL_RESULT" unless
      canonical_json(run["effective_user_config"]) == canonical_json(run.dig("install", "after"))
    return "HBV1_UNINSTALL_INPUT_NOT_INSTALL_RESULT" unless
      canonical_json(run.dig("uninstall", "before")) == canonical_json(run.dig("install", "after"))
    problem = precedence_problem(run["higher_precedence"], profile)
    return problem unless problem.nil?
    problem = health_problem(run["host_health"], profile)
    return problem unless problem.nil?
    bootstrap_problem(run["bootstrap"], host, bindings)
  end
end
