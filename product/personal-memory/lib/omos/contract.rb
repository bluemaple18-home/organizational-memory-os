# frozen_string_literal: true
#
# 產品與既有契約／共用 evaluator 的橋接層。
#
# 這一層存在的唯一理由，就是 Owner 選 Ruby 的理由：**直接重用 scripts/lib 底下
# 已經過三輪 review 的治理 evaluator**，不在產品端新寫第二套治理邏輯，也不做
# 跨語言橋接。
#
# 注意：這裡載入的 spec 路徑目前指向 repo 內的 規格/v0.1/。把 spec 與共用
# evaluator 一起打包進可安裝的產物，是 3c installer 的交付項，尚未完成
# （NOT_IMPLEMENTED），在此明記以免日後誤以為已處理。

require "yaml"
require "json"
require "set"

module OMOS
  module Contract
    REPO_ROOT = File.expand_path("../../../..", __dir__)
    SHARED_LIB = File.join(REPO_ROOT, "scripts/lib")
    SPEC_PATH = File.join(REPO_ROOT, "規格/v0.1/personal-harness-integration.yaml")
    VOCAB_PATH = File.join(REPO_ROOT, "規格/v0.1/common-vocabulary.yaml")

    # 共用 evaluator：一律從既有位置載入，不複製到產品目錄。
    require File.join(SHARED_LIB, "omos_contract_helpers")
    require File.join(SHARED_LIB, "host_session_binding_shape")
    require File.join(SHARED_LIB, "personal_memory_resource_evaluator")
    require File.join(SHARED_LIB, "weekly_closeout_history")
    require File.join(SHARED_LIB, "minimal_evidence_package_shape")
    require File.join(SHARED_LIB, "runtime_log_oracle")
    require File.join(SHARED_LIB, "personal_memory_host_binding")

    ResourceEvaluator = PersonalMemoryResourceEvaluator
    BindingShape = HostSessionBindingShape
    CloseoutHistory = WeeklyCloseoutHistory
    Shape = MinimalEvidencePackageShape
    # 事後 conformance oracle。**不得用於寫入治理路徑**——寫入保護是
    # OMOS::Runtime 的 pre-write 判定加上 SQLite constraint/trigger。
    LogOracle = RuntimeLogOracle
    # 切片 2 的 Host 適配 evaluator：安裝 safe-merge、shadow、health、
    # bootstrap 與 effective_scope 推導全部委派它。
    HostBinding = PersonalMemoryHostBinding

    module_function

    def spec
      @spec ||= YAML.safe_load(File.read(SPEC_PATH), permitted_classes: [], aliases: false)
    end

    def vocab
      @vocab ||= YAML.safe_load(File.read(VOCAB_PATH), permitted_classes: [], aliases: false)
    end

    def runtime
      spec.fetch("personal_memory_runtime")
    end

    # 契約裡宣告的執行參數，全部在評估當下讀上游，產品端不留副本。
    def store_engine = runtime.dig("store", "engine")
    def journal_mode = runtime.dig("store", "journal_mode")
    def genesis_version = runtime.dig("store", "genesis_version")
    def access_surfaces = runtime.fetch("access_surfaces")
    def forbidden_surfaces = runtime.fetch("forbidden_access_surfaces")
    def write_path = runtime.fetch("write_path")
    def read_path = runtime.fetch("read_path")
    # delivered = 這一版真的能產出可信 HostSessionBinding 的 Host。
    # known = 契約認識、能評估設定面的 Host（含 blocked）。兩者分開是 Owner
    # 2026-09-20 的裁決：blocked 不等於不認識，設定面評估必須維持。
    def supported_hosts = runtime.fetch("supported_hosts_v1")
    def blocked_hosts = runtime.fetch("blocked_hosts_v1", {}).keys
    def known_hosts = supported_hosts + blocked_hosts

    def id_templates
      spec.dig("personal_memory_resource_contracts", "shared_constraints", "id_templates")
    end

    def row_identity_field(kind)
      runtime.dig("row_contract", "identity_fields", kind)
    end

    # row id 形狀：沿用切片 A 既有的 template 展開（含 UUIDv7 version／variant
    # nibble），UUID 版本由上游 identifiers.omos_generated.algorithm 推導，
    # 產品端不寫死。
    def id_pattern(kind)
      @id_patterns ||= {}
      @id_patterns[kind] ||= begin
        digit = Shape.build_bindings(spec, vocab, {})[0][:uuid_version_digit]
        Regexp.new("\\A#{Shape.build_id_template_pattern(id_templates.fetch(kind), digit)}\\z")
      end
    end

    # HostSessionBinding 的形狀參數——與切片 1／2 的 validator 用同一組來源。
    #
    # 這裡有兩個**不能共用**的 seam（repair-03 P1-1：共用會讓 blocked host
    # 繞過 bootstrap 直接被 Runtime 授權）：
    #
    #   binding_shape_bindings        純形狀／composition 判定。問的是
    #                                 「executor_ref 是不是契約認識的 Host」，
    #                                 因此認 known_hosts（含 blocked）。
    #   runtime_authorization_bindings Runtime 真正的授權閘。問的是
    #                                 「這一版准不准這個 Host 動 store」，
    #                                 只認 delivered（supported_hosts_v1）。
    def binding_shape_bindings = binding_bindings_for(known_hosts)

    # Runtime 授權用：blocked host 的 binding 到這裡一律擋下，不論它形狀多合法。
    def runtime_authorization_bindings = binding_bindings_for(supported_hosts)

    def binding_bindings_for(hosts)
      identity = spec.dig("runtime_policy", "portable_record_contract", "executor_provenance_fields")
      additional = runtime.dig("host_session_binding", "additional_fields")
      {
        identity_fields: identity,
        additional_fields: additional,
        allowed_fields: identity + additional,
        forbidden_fields: runtime.dig("host_session_binding", "forbidden_fields"),
        supported_hosts: hosts,
        visibility_scopes: (spec.dig("ownership_visibility_contract", "visibility_scopes") || {}).keys
      }
    end

    def disposition_categories
      ((spec.dig("historical_comparison", "categories") || []) + ["NEEDS_ORG_FOLLOWUP"]).to_set
    end

    def candidate_ref_prefix = id_templates["PersonalMemoryCandidate"].to_s.split("{").first
    def record_ref_prefix = id_templates["PersonalMemoryRecord"].to_s.split("{").first

    # --- 治理判定：一律委派共用 evaluator，產品端不自己判 ---------------

    # 落地前的本體判定。indexes 由呼叫端用**store 目前已寫入的列**建出來，
    # 與切片 1 runtime validator 的做法相同。
    def resource_problem(kind, resource, store_rows)
      cases = store_rows.map do |row|
        { "resource_type" => row[:kind], "resource" => row[:resource], "case_id" => row[:row_id] }
      end
      cases << { "resource_type" => kind, "resource" => resource, "case_id" => resource[row_identity_field(kind)] }
      problems = ResourceEvaluator.resource_failures(
        spec, vocab, ResourceEvaluator.build_indexes(cases),
        { "resource_type" => kind, "resource" => resource }
      )
      problems.empty? ? nil : problems
    end

    # Runtime 的授權閘走這支——只認已交付的 Host。純形狀比對要用
    # binding_shape_bindings，不要圖方便共用這一支。
    def binding_problem(binding)
      BindingShape.binding_problem(binding, runtime_authorization_bindings)
    end

    # 事後 conformance 用：把 operation journal 交給切片 1 的 oracle 判定。
    # 這是證據，不是保護——呼叫點只會出現在 test/，不會出現在 runtime.rb。
    def runtime_log_bindings
      tmpl = id_templates
      {
        engine: store_engine, journal_mode: journal_mode,
        surfaces: access_surfaces, forbidden_surfaces: forbidden_surfaces,
        supported_hosts: supported_hosts,
        identity_fields: spec.dig("runtime_policy", "portable_record_contract", "executor_provenance_fields"),
        binding_shape: binding_shape_bindings,
        write_path: write_path, read_path: read_path,
        id_patterns: tmpl.keys.each_with_object({}) { |k, h| h[k] = id_pattern(k) },
        spec: spec, common_vocab: vocab,
        row_identity_fields: runtime.dig("row_contract", "identity_fields"),
        disposition_categories: disposition_categories,
        candidate_ref_prefix: candidate_ref_prefix, record_ref_prefix: record_ref_prefix,
        genesis_version: genesis_version
      }
    end

    def runtime_log_problem(log)
      b = runtime_log_bindings
      missing = LogOracle.missing_binding_keys(b)
      raise "oracle bindings 缺少 #{missing.inspect}" unless missing.empty?

      LogOracle.runtime_log_failure(log, b)
    end

    # closeout 歷程判定：entries 是同一個 review_period_id 依序的 closeout。
    def closeout_history_problem(review_period_id, entries)
      CloseoutHistory.weekly_review_cycle_failure(
        { "review_period_id" => review_period_id, "closeouts" => entries },
        disposition_categories, candidate_ref_prefix, record_ref_prefix
      )
    end
  end
end
