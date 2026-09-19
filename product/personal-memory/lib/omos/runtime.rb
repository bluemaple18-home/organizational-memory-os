# frozen_string_literal: true
#
# Runtime 治理層。CLI 與（3b 的）MCP server 都只能經由這裡碰 store。
#
# **Owner 裁決的核心約束：該拒絕的寫入，要在落地前就被同一套治理邏輯拒絕。**
# 因此所有判定都發生在 `store.transaction` 之外、之前；被拒絕的寫入完全不進
# 交易，資料庫裡不會出現該筆。operation journal 仍然寫，但它的角色是
# **可重播的證據**，供事後審計與 conformance 比對，不是保護機制本身。
#
# 判定一律委派 scripts/lib 底下既有的共用 evaluator，產品端不新寫治理邏輯。
# 錯誤碼沿用 personal_memory_runtime 契約既有的 PMR_* 詞彙，讓產品與
# validator 講同一種語言。

require "json"
require "time"
require_relative "contract"
require_relative "store"

module OMOS
  class Runtime
    # 被治理層拒絕的寫入。code 是契約詞彙，detail 供人閱讀。
    class Rejected < StandardError
      attr_reader :code, :detail

      def initialize(code, detail = nil)
        @code = code
        @detail = detail
        super([code, detail].compact.join(": "))
      end
    end

    SURFACES = { cli: "LOCAL_CLI", mcp: "LOCAL_STDIO_MCP" }.freeze

    attr_reader :store

    def initialize(store)
      @store = store
    end

    def self.open(path)
      store = Store.open(path)
      store.migrate!
      new(store)
    end

    # --- 讀取路徑 --------------------------------------------------------
    #
    # capability_safety_floor.invariants.permission_before_retrieval：
    # 權限檢查必須發生在碰 store 之前，而且是第一步。

    def read_rows(surface:, binding: nil)
      authorize!(surface, binding)                 # ← 先做，且不碰 store
      rows = store.rows                            # ← 之後才讀
      journal(surface, "STORE_READ", Contract.read_path, binding, nil)
      rows
    end

    # --- 寫入路徑 --------------------------------------------------------

    def write_row(kind:, resource:, idempotency_key:, surface:, supersedes_ref: nil, binding: nil)
      authorize!(surface, binding)

      identity_field = Contract.row_identity_field(kind)
      raise Rejected.new("PMR_ROW_KIND_UNKNOWN", kind.to_s) if identity_field.nil?

      row_id = resource.is_a?(Hash) ? resource[identity_field] : nil
      raise Rejected, "PMR_ROW_RESOURCE_NOT_MAP" unless resource.is_a?(Hash)
      unless row_id.is_a?(String) && Contract.id_pattern(kind).match?(row_id)
        raise Rejected.new("PMR_ROW_ID_NOT_MATCHING_ID_TEMPLATE", row_id.inspect)
      end
      unless idempotency_key.is_a?(String) && !idempotency_key.strip.empty?
        raise Rejected, "PMR_IDEMPOTENCY_KEY_INVALID"
      end

      candidate = { "kind" => kind, "row_id" => row_id, "idempotency_key" => idempotency_key,
                    "resource" => resource }
      candidate["supersedes_ref"] = supersedes_ref if supersedes_ref
      canonical = JSON.generate(deep_sort(candidate))

      existing = store.row(row_id)
      unless existing.nil?
        # 逐欄相同的重放是合法 no-op；其餘任何差異都是就地改寫。
        raise Rejected, "PMR_IN_PLACE_ROW_OVERWRITE" unless existing[:canonical] == canonical

        journal(surface, "STORE_WRITE", Contract.write_path, binding, candidate)
        return { row_id: row_id, replayed: true }
      end

      seen_for_key = store.row_for_key(idempotency_key)
      if !seen_for_key.nil? && seen_for_key[:row_id] != row_id
        raise Rejected.new("PMR_IDEMPOTENT_REPLAY_CREATED_SECOND_ROW", seen_for_key[:row_id])
      end

      unless supersedes_ref.nil?
        target = store.row(supersedes_ref)
        raise Rejected.new("PMR_SUPERSEDES_TARGET_UNKNOWN", supersedes_ref) if target.nil?
        raise Rejected, "PMR_SUPERSEDES_TARGET_KIND_MISMATCH" unless target[:kind] == kind
        if store.rows.any? { |r| r[:supersedes_ref] == supersedes_ref }
          raise Rejected.new("PMR_SUPERSEDES_TARGET_ALREADY_SUPERSEDED", supersedes_ref)
        end
      end

      # 本體判定委派既有 resource evaluator；indexes 由**目前 store 裡已寫入
      # 的列**建出，因此 support_link_refs 必須解析到同一個 store 裡真的存在、
      # 且 target_ref 指回本列的 MemorySupportLink。
      problems = Contract.resource_problem(kind, resource, store.rows)
      raise Rejected.new("PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT", problems.first) unless problems.nil?

      # 判定全部通過，才開交易。
      store.transaction do
        store.db.execute(
          "INSERT INTO memory_rows (row_id, kind, idempotency_key, supersedes_ref, canonical, resource_json, created_at) " \
          "VALUES (?,?,?,?,?,?,?)",
          [row_id, kind, idempotency_key, supersedes_ref, canonical, JSON.generate(resource), now]
        )
      end
      journal(surface, "STORE_WRITE", Contract.write_path, binding, candidate)
      { row_id: row_id, replayed: false }
    end

    # --- closeout --------------------------------------------------------

    def commit_closeout(closeout:, surface:, binding: nil)
      authorize!(surface, binding)
      raise Rejected, "PMR_CLOSEOUT_NOT_MAP" unless closeout.is_a?(Hash)

      period_id = closeout["review_period_id"]
      unless period_id.is_a?(String) && !period_id.strip.empty?
        raise Rejected, "PMR_CLOSEOUT_REVIEW_PERIOD_ID_INVALID"
      end

      # 把這一筆接在既有歷程後面，整段交給切片 4 的共用 evaluator 判定。
      # terminal 唯一性、status／attempt 詞彙、SKIPPED catch-up 規則、
      # disposition 分類，以及 promotion identity 不得在 retry 間漂移，
      # 全部來自那一份實作。
      history = store.closeouts_for(period_id) + [closeout]
      problem = Contract.closeout_history_problem(period_id, history)
      raise Rejected.new("PMR_CLOSEOUT_FAILS_WEEKLY_CYCLE_CONTRACT", problem) unless problem.nil?

      terminal = Contract::CloseoutHistory::TERMINAL_STATUSES.include?(closeout["final_status"])
      store.transaction do
        store.db.execute(
          "INSERT INTO closeouts (review_period_id, attempt_seq, final_status, is_terminal, payload_json, committed_at) " \
          "VALUES (?,?,?,?,?,?)",
          [period_id, store.next_attempt_seq(period_id), closeout["final_status"],
           terminal ? 1 : 0, JSON.generate(closeout), now]
        )
      end
      journal(surface, "CLOSEOUT_COMMIT", Contract.write_path, binding, closeout)
      { review_period_id: period_id, terminal: terminal }
    end

    # --- 證據：把 journal 還原成切片 1 validator 吃的 run 形狀 -----------
    #
    # 這是證據，不是保護。conformance 會另外以實際資料庫讀回、rollback 與
    # 重啟持久化確認，不只驗這份 journal。

    def operation_log
      migrations = store.migration_receipts.map do |receipt|
        { "surface" => "LOCAL_CLI", "kind" => "SCHEMA_MIGRATION", "path" => Contract.write_path,
          "transaction" => { "committed" => true }, "migration" => receipt }
      end
      recorded = store.journal.map do |(_, surface, kind, path_json, binding_json, payload_json)|
        op = { "surface" => surface, "kind" => kind, "path" => JSON.parse(path_json) }
        op["host_session_binding"] = JSON.parse(binding_json) if binding_json
        op["transaction"] = { "committed" => true } unless kind == "STORE_READ"
        payload = payload_json && JSON.parse(payload_json)
        case kind
        when "STORE_WRITE" then op["row"] = payload
        when "CLOSEOUT_COMMIT" then op["closeout"] = payload
        end
        op
      end
      operations = (migrations + recorded).each_with_index.map { |op, i| op.merge("op_seq" => i + 1) }
      {
        "store" => { "engine" => Contract.store_engine,
                     "journal_mode" => store.journal_mode.to_s.upcase,
                     "schema_version" => store.schema_version },
        "operations" => operations
      }
    end

    private

    def now = Time.now.utc.iso8601

    # 權限 seam：surface 合法性與 binding 形狀都在碰 store 之前判定。
    def authorize!(surface, binding)
      raise Rejected.new("PMR_SURFACE_FORBIDDEN", surface) if Contract.forbidden_surfaces.include?(surface)
      raise Rejected.new("PMR_SURFACE_NOT_IN_CLOSED_ENUM", surface) unless Contract.access_surfaces.include?(surface)

      if surface == SURFACES[:mcp]
        raise Rejected, "PMR_MCP_OPERATION_MISSING_HOST_BINDING" if binding.nil?
      elsif !binding.nil?
        raise Rejected, "PMR_CLI_OPERATION_CLAIMS_HOST_BINDING"
      end
      return if binding.nil?

      problem = Contract.binding_problem(binding)
      raise Rejected.new(problem) unless problem.nil?
    end

    def journal(surface, kind, path, binding, payload)
      store.db.execute(
        "INSERT INTO operation_journal (surface, kind, path_json, binding_json, payload_json, occurred_at) VALUES (?,?,?,?,?,?)",
        [surface, kind, JSON.generate(path), binding && JSON.generate(binding),
         payload && JSON.generate(payload), now]
      )
    end

    def deep_sort(obj)
      case obj
      when Hash then obj.keys.sort.each_with_object({}) { |k, acc| acc[k] = deep_sort(obj[k]) }
      when Array then obj.map { |v| deep_sort(v) }
      else obj
      end
    end
  end
end
