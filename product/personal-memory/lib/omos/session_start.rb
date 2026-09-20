# frozen_string_literal: true
#
# SessionStart：由 Host 提供的原生輸入，產出既有形狀的 HostSessionBinding。
#
# 推導完全委派切片 2 的既有 evaluator：
#   - effective_scope 由 PersonalMemoryHostBinding.derived_effective_scope
#     從 mode_definitions → visibility_scope → default_readers 推導，
#     project 只能 equal 或 narrowing，無法證明收窄就 fail closed；
#   - 產出的 binding 再交給 HostSessionBindingShape 判定形狀，
#     也就是切片 1 runtime 判定 binding 用的同一支。
#
# 本產品不自己解讀 scope，也不自己定義 binding 欄位。

require "json"
require_relative "contract"

module OMOS
  class SessionStart
    class Refused < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super(code)
      end
    end

    # bootstrap 的輸入權責分工由契約規定：runtime_scope_mode 屬 runtime policy，
    # project context 永遠不能提供它，也不能自己寫 produced binding。
    def self.bootstrap_bindings
      spec = Contract.spec
      {
        supported_hosts: Contract.supported_hosts,
        host_profiles: spec.dig("personal_memory_host_binding_v1", "host_profiles"),
        scope_modes: spec.dig("employee_memory_scope_modes", "modes") || [],
        mode_definitions: spec.dig("ownership_visibility_contract", "mode_definitions") || {},
        visibility_scopes: spec.dig("ownership_visibility_contract", "visibility_scopes") || {},
        binding_allowed_fields: Contract.binding_shape_bindings[:allowed_fields],
        binding_forbidden_fields: Contract.binding_shape_bindings[:forbidden_fields],
        runtime_binding_shape: Contract.binding_shape_bindings
      }
    end

    # project_ref 由 cwd 決定，不接受模型或呼叫端提供——這是 authority 的一部分。
    def self.project_ref_for(cwd)
      "urn:omos:project:#{File.basename(File.expand_path(cwd))}"
    end

    # host           Host 名稱（必須是 supported_hosts_v1 之一）
    # native_session_id / cwd  Host 原生輸入
    # project_ref / project_visibility_scope  專案脈絡（可選 scope）
    # runtime_scope_mode  runtime policy 輸入，不得由專案脈絡提供
    def self.produce(host:, native_session_id:, cwd:, project_ref:,
                     runtime_scope_mode:, project_visibility_scope: nil)
      b = bootstrap_bindings
      raise Refused, "HBV1_HOST_NOT_SUPPORTED" unless b[:supported_hosts].include?(host)

      bootstrap = {
        "native_session_id" => native_session_id, "cwd" => cwd, "project_ref" => project_ref,
        "runtime_scope_mode" => runtime_scope_mode
      }
      bootstrap["project_visibility_scope"] = project_visibility_scope unless project_visibility_scope.nil?

      scope, scope_problem = Contract::HostBinding.derived_effective_scope(bootstrap, b)
      raise Refused, scope_problem unless scope_problem.nil?

      binding = {
        "executor_ref" => host,
        "executor_session_ref" => native_session_id,
        "cwd" => cwd,
        "project_ref" => project_ref,
        "effective_scope" => scope
      }

      # 產出的 binding 必須是切片 1 runtime 收得下的——用同一支 evaluator 判定。
      problem = Contract.binding_problem(binding)
      raise Refused, problem unless problem.nil?

      # 再把整個 bootstrap（含 produced binding）交給切片 2 的 evaluator 複核，
      # 確保 identity mapping 與 authority 分工也成立。
      bootstrap_with_binding = bootstrap.merge("produced_binding" => binding)
      bootstrap_problem = Contract::HostBinding.bootstrap_problem(bootstrap_with_binding, host, b)
      raise Refused, bootstrap_problem unless bootstrap_problem.nil?

      binding
    end
  end
end
