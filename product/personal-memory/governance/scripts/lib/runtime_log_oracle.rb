# frozen_string_literal: true
#
# Runtime operation-log oracle —— 由 EMEM-11 切片 1 的
# validate_personal_memory_runtime_contract.rb 與切片 3 的產品
# （product/personal-memory）共用的單一實作。
#
# 抽取原因（切片 3a 之後的 A 裁決）：產品的 operation journal 刻意輸出成這支
# evaluator 吃的 run shape，而這支正是那份 journal 唯一的既有 oracle。不抽的話
# 產品要嘛無法自我檢查 journal，要嘛得複製一份判定邏輯。
#
# **使用邊界（Owner 明示，寫在這裡以免日後誤用）**：
#   1. 這支是**事後 conformance oracle**，不是寫入治理路徑的一部分。
#      產品的寫入保護是 pre-write Runtime 判定 + SQLite constraint/trigger；
#      不得改成「journal evaluator PASS 才允許寫入」。
#   2. 只搬 evaluator，語意逐字不變；fixture、ERROR_CONTRACT 與測試編排
#      仍留在 validator，這支不擴張成 production framework。
#
# bindings 由呼叫端組裝（validator 側與產品側各自從同一份上游 spec 推導），
# REQUIRED_BINDING_KEYS 讓兩邊都能先確認引數完整，避免少帶一個鍵而讓
# 判定悄悄走偏。
require "set"
require_relative "omos_contract_helpers"
require_relative "minimal_evidence_package_shape"
require_relative "personal_memory_resource_evaluator"
require_relative "weekly_closeout_history"
require_relative "host_session_binding_shape"

module RuntimeLogOracle
  MEPShape = MinimalEvidencePackageShape
  PMRE = PersonalMemoryResourceEvaluator
  WCH = WeeklyCloseoutHistory
  HBShape = HostSessionBindingShape

  REQUIRED_BINDING_KEYS = %i[
    engine journal_mode surfaces forbidden_surfaces supported_hosts identity_fields
    binding_shape write_path read_path id_patterns spec common_vocab
    row_identity_fields disposition_categories candidate_ref_prefix record_ref_prefix
    genesis_version
  ].freeze

  RUN_ALLOWED_FIELDS = %w[store operations].freeze
  STORE_ALLOWED_FIELDS = %w[engine journal_mode schema_version].freeze
  OPERATION_ALLOWED_FIELDS = %w[
    op_seq surface kind path host_session_binding transaction
    migration row closeout
  ].freeze
  MIGRATION_ALLOWED_FIELDS = %w[migration_id from_version to_version applied_at].freeze
  ROW_ALLOWED_FIELDS = %w[kind row_id idempotency_key supersedes_ref deleted resource].freeze

  OPERATION_KINDS = %w[SCHEMA_MIGRATION STORE_READ STORE_WRITE CLOSEOUT_COMMIT].freeze
  WRITE_KINDS = %w[SCHEMA_MIGRATION STORE_WRITE CLOSEOUT_COMMIT].freeze
  PATH_STEPS = %w[RUNTIME_POLICY_CHECK RUNTIME_TRANSACTION STORE_WRITE STORE_READ].freeze

  module_function

  def runtime_log_failure(run, b)
    return "PMR_RUN_NOT_MAP" unless run.is_a?(Hash)
    return "PMR_RUN_UNKNOWN_FIELD" unless (run.keys - RUN_ALLOWED_FIELDS).empty?

    store = run["store"]
    return "PMR_STORE_NOT_MAP" unless store.is_a?(Hash) && (store.keys - STORE_ALLOWED_FIELDS).empty?
    return "PMR_STORE_ENGINE_NOT_SQLITE" unless store["engine"] == b[:engine]
    return "PMR_STORE_JOURNAL_MODE_NOT_WAL" unless store["journal_mode"] == b[:journal_mode]
    return "PMR_STORE_SCHEMA_VERSION_MISSING" if MEPShape.blank?(store["schema_version"])

    operations = run["operations"]
    return "PMR_OPERATIONS_NOT_ARRAY" unless operations.is_a?(Array) && operations.any?

    # 跨操作狀態：這片的保證幾乎全都住在這裡。
    schema_version = nil                  # migration 鏈目前的尾巴
    migration_receipts = {}               # migration_id => 受凍結的 receipt 內容
    rows = {}                             # row_id => { kind, idempotency_key }
    key_to_row = {}                       # idempotency_key => row_id
    superseded = Set.new                  # 已被取代的 row_id
    closeout_history = {}                 # review_period_id => 依序的 closeout entries

    operations.each_with_index do |op, index|
      return "PMR_OPERATION_NOT_MAP" unless op.is_a?(Hash)
      return "PMR_OPERATION_UNKNOWN_FIELD" unless (op.keys - OPERATION_ALLOWED_FIELDS).empty?
      return "PMR_OPERATION_SEQUENCE_BROKEN" unless op["op_seq"] == index + 1

      kind = op["kind"]
      return "PMR_OPERATION_KIND_UNKNOWN" unless OPERATION_KINDS.include?(kind)

      # 禁列先於封閉列舉：那四種遠端面要以自己的錯誤碼失敗，而不是被歸進
      # 泛用的 unknown surface。
      surface = op["surface"]
      return "PMR_SURFACE_FORBIDDEN" if b[:forbidden_surfaces].include?(surface)
      return "PMR_SURFACE_NOT_IN_CLOSED_ENUM" unless b[:surfaces].include?(surface)

      binding = op["host_session_binding"]
      if surface == "LOCAL_STDIO_MCP"
        return "PMR_MCP_OPERATION_MISSING_HOST_BINDING" if binding.nil?
      elsif !binding.nil?
        # CLI 沒有 Host session 可綁；宣稱有就是偽造 provenance。
        return "PMR_CLI_OPERATION_CLAIMS_HOST_BINDING"
      end

      unless binding.nil?
        # repair-01（切片 2 P1-1／P1-2）：形狀判定搬到共用 evaluator，切片 2 的
        # Host 適配器與本片 runtime 因此不可能對同一個 binding 有不同結論。
        # 這裡逐碼轉發而不是 `return problem`，是因為 LoopReturnContract 要求
        # 出口只能是字面碼；六個碼的診斷粒度依 Owner §1.5 裁決保留。
        problem = HBShape.binding_problem(binding, b[:binding_shape])
        return "PMR_HOST_BINDING_NOT_MAP" if problem == "PMR_HOST_BINDING_NOT_MAP"
        return "PMR_HOST_BINDING_SHADOW_IDENTITY_FIELD" if problem == "PMR_HOST_BINDING_SHADOW_IDENTITY_FIELD"
        return "PMR_HOST_BINDING_UNKNOWN_FIELD" if problem == "PMR_HOST_BINDING_UNKNOWN_FIELD"
        return "PMR_HOST_BINDING_IDENTITY_FIELD_MISSING" if problem == "PMR_HOST_BINDING_IDENTITY_FIELD_MISSING"
        return "PMR_HOST_BINDING_ADDITIONAL_FIELD_NOT_STRING" if problem == "PMR_HOST_BINDING_ADDITIONAL_FIELD_NOT_STRING"
        return "PMR_HOST_BINDING_EFFECTIVE_SCOPE_NOT_VISIBILITY_SCOPE" if problem == "PMR_HOST_BINDING_EFFECTIVE_SCOPE_NOT_VISIBILITY_SCOPE"
        return "PMR_HOST_BINDING_EXECUTOR_NOT_SUPPORTED_HOST" if problem == "PMR_HOST_BINDING_EXECUTOR_NOT_SUPPORTED_HOST"
      end

      path = op["path"]
      return "PMR_PATH_NOT_ARRAY" unless path.is_a?(Array) && path.any? && path.all? { |s| PATH_STEPS.include?(s) }
      # permission-before-retrieval 的確定性 seam：store 存取之前必須先有
      # policy check，而且是第一步。check 之後才回 allow 不算數。
      return "PMR_PERMISSION_CHECK_NOT_FIRST" unless path.first == "RUNTIME_POLICY_CHECK"
      expected_path = kind == "STORE_READ" ? b[:read_path] : b[:write_path]
      return "PMR_PATH_NOT_DECLARED_PATH" unless path == expected_path

      # kind 與 payload 必須互相說得通；讀取操作不得夾帶落地列。
      expected_payload = { "SCHEMA_MIGRATION" => "migration", "STORE_WRITE" => "row",
                           "CLOSEOUT_COMMIT" => "closeout", "STORE_READ" => nil }[kind]
      payload_keys = %w[migration row closeout].select { |f| !op[f].nil? }
      return "PMR_OPERATION_PAYLOAD_MISMATCH" unless payload_keys == [expected_payload].compact

      if WRITE_KINDS.include?(kind)
        transaction = op["transaction"]
        return "PMR_WRITE_OUTSIDE_TRANSACTION" unless transaction.is_a?(Hash)
        return "PMR_UNCOMMITTED_WRITE_DURABLE" unless transaction["committed"] == true
      end

      if kind == "SCHEMA_MIGRATION"
        migration = op["migration"]
        return "PMR_MIGRATION_NOT_MAP" unless migration.is_a?(Hash) &&
                                             (migration.keys - MIGRATION_ALLOWED_FIELDS).empty?
        return "PMR_MIGRATION_RECEIPT_INCOMPLETE" unless MIGRATION_ALLOWED_FIELDS.all? { |f| !MEPShape.blank?(migration[f]) }
        # 鏈必須接得上：第一筆從 nil 起算，之後每筆的 from_version 就是目前尾巴。
        return "PMR_MIGRATION_CHAIN_BROKEN" unless migration["from_version"] == (schema_version || b[:genesis_version])

        migration_id = migration["migration_id"]
        prior = migration_receipts[migration_id]
        # receipt 不可變（correction_flow 的 receipt_mutation）：同一個
        # migration_id 用不同內容再發一次就是竄改。
        return "PMR_MIGRATION_RECEIPT_MUTATED" if !prior.nil? && prior != migration
        migration_receipts[migration_id] = migration
        schema_version = migration["to_version"]
      end

      if kind == "STORE_WRITE"
        row = op["row"]
        return "PMR_ROW_NOT_MAP" unless row.is_a?(Hash) && (row.keys - ROW_ALLOWED_FIELDS).empty?
        # 刪除在這個 store 裡不存在：history_erasure 是 correction_flow 明文禁項。
        return "PMR_HISTORY_ERASURE" if row["deleted"] == true

        row_kind = row["kind"]
        return "PMR_ROW_KIND_UNKNOWN" unless b[:id_patterns].key?(row_kind)
        row_id = row["row_id"]
        # id 形狀鎖到上游 id_template，含 UUIDv7 的 version／variant nibble。
        return "PMR_ROW_ID_NOT_MATCHING_ID_TEMPLATE" unless row_id.is_a?(String) &&
                                                            b[:id_patterns][row_kind].match?(row_id)
        return "PMR_IDEMPOTENCY_KEY_INVALID" if MEPShape.blank?(row["idempotency_key"])

        # repair-01 P1-3：落地的是一筆 Personal Memory 資源，不是一個空殼 id。
        # required_fields／forbidden 在評估當下讀 personal_memory_resource_
        # contracts.resources.<kind>，本片不維護第二份欄位清單。
        resource = row["resource"]
        return "PMR_ROW_RESOURCE_NOT_MAP" unless resource.is_a?(Hash)
        # 合法 id 配上別人的本體，等於 id 沒有真的指向任何東西。
        return "PMR_ROW_ID_NOT_BOUND_TO_RESOURCE_IDENTITY" unless resource[b[:row_identity_fields][row_kind]] == row_id

        # repair-02 P1-3：不是「required_fields 路徑存在」而已——整份本體交給
        # 既有 Personal Memory resource evaluator：support、memory kind、
        # verification／acceptance、lifecycle、Record creation gate 全部由那一份
        # 實作判定。indexes 用的是**這個 store 目前已寫入的列**，所以
        # support_link_refs 必須解析到同一個 store 裡真的存在、且 target_ref
        # 指回本列的 MemorySupportLink——這是組合，不是形式呼叫。
        store_cases = rows.map { |rid, rec| { "resource_type" => rec[:kind], "resource" => rec[:resource], "case_id" => rid } }
        store_cases << { "resource_type" => row_kind, "resource" => resource, "case_id" => row_id }
        resource_problems = PMRE.resource_failures(
          b[:spec], b[:common_vocab], PMRE.build_indexes(store_cases),
          { "resource_type" => row_kind, "resource" => resource }
        )
        return "PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT" unless resource_problems.empty?

        key = row["idempotency_key"]
        seen_row_for_key = key_to_row[key]
        # 重放必須落回同一列；換一個 row_id 就不是 retry，是第二筆。
        return "PMR_IDEMPOTENT_REPLAY_CREATED_SECOND_ROW" if !seen_row_for_key.nil? && seen_row_for_key != row_id

        # repair-01 P1-1：凍結的是「整筆 row」，不是 row_id + key。先前只記
        # {kind, key}，於是同一個 row_id + 同一把 key 只要把 supersedes_ref
        # 改掉就能就地改寫；而原封不動重放一筆 revision 反而會被誤判成第二次
        # supersession。兩者同一個根因：部分凍結。
        canonical_row = canonical_json(row)
        existing = rows[row_id]
        unless existing.nil?
          return "PMR_IN_PLACE_ROW_OVERWRITE" unless existing[:canonical] == canonical_row

          # 逐欄相同的重放是 no-op：不得再動 supersession 帳。
          next
        end

        supersedes_ref = row["supersedes_ref"]
        unless supersedes_ref.nil?
          target = rows[supersedes_ref]
          return "PMR_SUPERSEDES_TARGET_UNKNOWN" if target.nil?
          return "PMR_SUPERSEDES_TARGET_KIND_MISMATCH" unless target[:kind] == row_kind
          return "PMR_SUPERSEDES_TARGET_ALREADY_SUPERSEDED" if superseded.include?(supersedes_ref)
          superseded << supersedes_ref
        end

        rows[row_id] = { kind: row_kind, canonical: canonical_row, resource: resource }
        key_to_row[key] = row_id
      end

      if kind == "CLOSEOUT_COMMIT"
        closeout = op["closeout"]
        # 只做「能安全分組」所需的最低檢查，其餘全部交給共用 evaluator。
        return "PMR_CLOSEOUT_NOT_MAP" unless closeout.is_a?(Hash)
        period_id = closeout["review_period_id"]
        return "PMR_CLOSEOUT_REVIEW_PERIOD_ID_INVALID" if MEPShape.blank?(period_id)

        (closeout_history[period_id] ||= []) << closeout
      end
    end

    # repair-01 P1-2：同一個 review_period_id 的 CLOSEOUT_COMMIT 依發生順序
    # 排起來，就是 weekly_review_cycle 眼中的一段 closeout 歷程——直接丟給
    # 切片 4 已在用的同一支 evaluator。terminal 唯一性、status／attempt 詞彙、
    # SKIPPED 的 catch-up 規則、disposition 分類，以及本片原本完全沒有落地的
    # promotion idempotency（retry 不得換掉同一 item 的 promotion 身分），
    # 全部來自那一份實作，本片不再自己列任何一份詞彙。
    closeout_history.each_value do |entries|
      problem = WCH.weekly_review_cycle_failure(
        { "review_period_id" => entries.first["review_period_id"], "closeouts" => entries },
        b[:disposition_categories], b[:candidate_ref_prefix], b[:record_ref_prefix]
      )
      return "PMR_CLOSEOUT_FAILS_WEEKLY_CYCLE_CONTRACT" unless problem.nil?
    end

    # schema_version 不是獨立主張，是 migration 鏈的尾巴。
    return "PMR_STORE_SCHEMA_VERSION_NOT_MIGRATION_CHAIN_TAIL" unless store["schema_version"] == schema_version

    nil
  end

  def missing_binding_keys(b)
    REQUIRED_BINDING_KEYS.reject { |k| b.key?(k) }
  end
end
