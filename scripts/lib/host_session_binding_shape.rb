# frozen_string_literal: true
#
# HostSessionBinding 形狀 evaluator —— 由 EMEM-11 切片 1
# （validate_personal_memory_runtime_contract.rb）與切片 2
# （validate_personal_memory_host_binding_contract.rb）共用的單一實作。
#
# 抽取原因（切片 2 repair-01，P1-1 / P1-2）：review 實測切片 2 能產出切片 1
# runtime 會拒絕的 binding——切片 2 的 blank? 對 `false` 與 `1` 都回 false，
# 切片 1 用的是「必須是非空字串」。同一個 binding 兩片判定不同，代表
# 「Host 適配器產出的東西 runtime 一定收得下」這句話沒有機器保證。
#
# 同一次順便收掉 effective_scope 的語意分裂（P1-2）：它固定是
# ownership_visibility_contract.visibility_scopes 的詞彙（例如 SELF_ONLY），
# 不是 mode_definitions 的 mode（例如 EMPLOYEE_PRIVATE）。runtime_scope_mode
# 與 effective_scope 分離，後者在這裡做詞彙鎖，兩片因此不可能再各自解讀。
#
# 錯誤碼沿用切片 1 既有的 PMR_HOST_BINDING_* 命名：搬移不改碼，切片 1 的
# 負例與 error contract 不需要重新編號；切片 2 則以「這裡回 nil」作為
# 跨片 composition 的判準。
module HostSessionBindingShape
  module_function

  # 切片 1 一直用的語意：必須是非空字串。切片 2 原本的 blank? 放行 false／
  # 數字，正是 P1-1 的根因，所以這裡只留這一個定義。
  def nonblank_string?(value)
    value.is_a?(String) && !value.strip.empty?
  end

  # bindings：
  #   :identity_fields    上游 executor_provenance_fields
  #   :additional_fields  契約允許的附加欄位（cwd / project_ref / effective_scope）
  #   :allowed_fields     identity + additional（封閉外殼）
  #   :forbidden_fields   第二套身分詞彙的禁列
  #   :supported_hosts    personal_memory_runtime.supported_hosts_v1
  #   :visibility_scopes  ownership_visibility_contract.visibility_scopes 的 key
  def binding_problem(binding, b)
    return "PMR_HOST_BINDING_NOT_MAP" unless binding.is_a?(Hash)
    return "PMR_HOST_BINDING_SHADOW_IDENTITY_FIELD" if b[:forbidden_fields].any? { |f| binding.key?(f) }
    return "PMR_HOST_BINDING_UNKNOWN_FIELD" unless (binding.keys - b[:allowed_fields]).empty?
    # 身分欄位名讀上游 executor_provenance_fields，值本身也要鎖形狀。
    return "PMR_HOST_BINDING_IDENTITY_FIELD_MISSING" unless b[:identity_fields].all? { |f| nonblank_string?(binding[f]) }
    # 欄位名合法不等於值合法：附加欄位出現時必須是非空字串，否則一個巢狀
    # 物件——或一個 false——就能穿過整張 allowlist。
    return "PMR_HOST_BINDING_ADDITIONAL_FIELD_NOT_STRING" unless b[:additional_fields]
      .all? { |f| !binding.key?(f) || nonblank_string?(binding[f]) }
    # P1-2：effective_scope 是 visibility scope，不是 ownership mode。
    return "PMR_HOST_BINDING_EFFECTIVE_SCOPE_NOT_VISIBILITY_SCOPE" if binding.key?("effective_scope") &&
                                                                      !b[:visibility_scopes].include?(binding["effective_scope"])
    return "PMR_HOST_BINDING_EXECUTOR_NOT_SUPPORTED_HOST" unless b[:supported_hosts].include?(binding["executor_ref"])

    nil
  end
end
