# frozen_string_literal: true
#
# omos-personal-memory doctor。
#
# 主卡要求的 13 項，每一項都對**實物**：讀實際設定檔、實際啟動目標、實際開啟
# store。三種結果必須分得開（這是驗收組 B 的核心）：
#
#   CONFIG_PRESENT   設定檔裡有這筆註冊
#   PROCESS_OK       那個 executable 真的能被啟動並完成 MCP 握手
#   STORE_OK         store 真的能開、版本安全、schema 是 migration 鏈的尾巴
#
# 「設定存在」不蘊含「程序能啟動」，後者也不蘊含「store 能用」。任何一項都
# 不接受 caller 自報——doctor 自己去看。

require "json"
require "open3"
require "timeout"
require_relative "contract"
require_relative "host_config"
require_relative "installer"
require_relative "store"
require_relative "session_start"

module OMOS
  class Doctor
    Result = Struct.new(:id, :status, :detail, keyword_init: true) do
      def ok? = status == "OK"
      def to_h = { "check" => id, "status" => status, "detail" => detail }
    end

    HANDSHAKE_TIMEOUT = 15

    def initialize(home: Dir.home, product_root: File.expand_path("../..", __dir__),
                   store_path: nil, cwd: Dir.pwd)
      @installer = Installer.new(home: home, product_root: product_root, store_path: store_path)
      @home = home
      @cwd = cwd
    end

    def run
      checks = []
      checks.concat(store_checks)
      checks.concat(process_checks)
      HostConfig.hosts.each { |host| checks.concat(host_checks(host)) }
      checks.concat(binding_checks)
      checks.concat(cycle_checks)
      checks << uninstall_metadata_check
      checks
    end

    # WARN 是誠實的第三種狀態：「這一項在這台機器上無法觀測」。
    # 它不該被當成健康，也不該被當成失敗——healthy? 以「沒有 FAIL」為準，
    # WARN 由呼叫端另外列出。
    def failures(results = run) = results.select { |r| r.status == "FAIL" }
    def warnings(results = run) = results.select { |r| r.status == "WARN" }
    def healthy?(results = run) = failures(results).empty?

    private

    def ok(id, detail) = Result.new(id: id, status: "OK", detail: detail)
    def bad(id, detail) = Result.new(id: id, status: "FAIL", detail: detail)
    def warn_(id, detail) = Result.new(id: id, status: "WARN", detail: detail)

    def store_path = @installer.store_path

    # --- STORE_OK 群 -----------------------------------------------------

    def store_checks
      return [bad("store_exists", "store 不存在：#{store_path}"),
              bad("store_writable", "無 store"),
              bad("sqlite_version_safe", "無 store"),
              bad("schema_version", "無 store"),
              bad("migration_state", "無 store")] unless File.exist?(store_path)

      store = Store.open(store_path)
      results = [ok("store_exists", store_path)]
      results << (File.writable?(store_path) ? ok("store_writable", "可寫") : bad("store_writable", "不可寫"))
      version = store.sqlite_version
      results << if store.version_at_least?(version, Store::WAL_RESET_FIX)
                   ok("sqlite_version_safe", "#{version}（產品連線回報，≥ #{Store::WAL_RESET_FIX}）")
                 else
                   bad("sqlite_version_safe",
                       "#{version} 低於 WAL-reset 修復版本 #{Store::WAL_RESET_FIX}，多連線寫入可能損毀資料庫")
                 end
      results << (store.journal_mode.to_s.casecmp("wal").zero? ?
                  ok("journal_mode_wal", store.journal_mode) : bad("journal_mode_wal", store.journal_mode))
      receipts = store.migration_receipts
      tail = receipts.last&.dig("to_version")
      results << if !receipts.empty? && store.schema_version == tail
                   ok("schema_version", "#{store.schema_version}（= migration 鏈尾）")
                 else
                   bad("schema_version", "schema_version=#{store.schema_version.inspect} 鏈尾=#{tail.inspect}")
                 end
      results << (receipts.empty? ? bad("migration_state", "無 migration receipt") :
                  ok("migration_state", "#{receipts.size} 筆 receipt"))
      store.close
      results
    rescue Store::VersionUnsafe => e
      [bad("sqlite_version_safe", e.message)]
    end

    # --- PROCESS_OK 群：真的把 executable 叫起來 -------------------------

    def process_checks
      cmd = @installer.mcp_command
      return [bad("mcp_executable", "不存在或不可執行：#{cmd}")] unless File.executable?(cmd)

      [ok("mcp_executable", cmd), mcp_handshake_check(cmd)]
    end

    # 「設定裡有」不等於「叫得起來」——這裡真的 spawn 並完成 MCP 握手。
    def mcp_handshake_check(cmd)
      request = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                                "params" => { "protocolVersion" => "2024-11-05", "capabilities" => {},
                                              "clientInfo" => { "name" => "doctor", "version" => "0" } } })
      out = nil
      Timeout.timeout(HANDSHAKE_TIMEOUT) do
        out, = Open3.capture3({ "OMOS_PERSONAL_MEMORY_STORE" => store_path }, cmd,
                              stdin_data: "#{request}\n")
      end
      name = JSON.parse(out.lines.first.to_s).dig("result", "serverInfo", "name")
      name == "omos-personal-memory" ? ok("mcp_handshake", "啟動並完成握手") :
        bad("mcp_handshake", "回應非預期：#{out.lines.first.to_s[0, 80]}")
    rescue Timeout::Error
      bad("mcp_handshake", "#{HANDSHAKE_TIMEOUT} 秒內未完成握手")
    rescue StandardError => e
      bad("mcp_handshake", "#{e.class}: #{e.message[0, 80]}")
    end

    # --- CONFIG_PRESENT 群：逐 Host 讀實際設定 ---------------------------

    def host_checks(host)
      config = HostConfig.new(host, home: @home, command_map: @installer.command_map)
      present = config.present?
      return [bad("#{tag(host)}_config_file", "設定檔不存在：#{config.mcp_config_path}")] unless present[:mcp_config]

      snapshot = config.snapshot
      profile = Contract.spec.dig("personal_memory_host_binding_v1", "host_profiles", host)
      results = [ok("#{tag(host)}_config_file", config.mcp_config_path)]

      mcp_present = snapshot["mcp_entries"].key?(config.own_mcp_id)
      results << (mcp_present ? ok("#{tag(host)}_mcp_visible", config.own_mcp_id) :
                  bad("#{tag(host)}_mcp_visible", "設定檔內找不到 #{config.own_mcp_id}"))

      hook = snapshot["session_start_hooks"].find { |h| h["id"] == config.own_hook_id }
      results << (hook ? ok("#{tag(host)}_session_start_hook_active", config.own_hook_id) :
                  bad("#{tag(host)}_session_start_hook_active", "SessionStart hook 未啟用"))

      # 漂移判定委派切片 2 既有 evaluator（含 command_ref 對不上的情況）
      drift = config.own_registration_problem
      results << (drift.nil? ? ok("#{tag(host)}_registration_intact", "未漂移") :
                  bad("#{tag(host)}_registration_intact", drift))

      # 遮蔽：同名設定被更高優先序蓋掉
      results << shadow_check(host, profile, config)
      results
    rescue HostConfig::DiscoveryError => e
      [bad("#{tag(host)}_config_file", e.message[0, 120])]
    end

    # 更高優先序的同名註冊＝遮蔽。判定用切片 2 的 precedence_problem，
    # 即使 payload 與本產品完全相同也必須報（看的是 id 與優先序，不是內容）。
    #
    # 讀的是**實際的專案層設定檔**。3c-2 初版這裡餵的是空快照，等於永遠回 OK、
    # 偵測不到任何真實遮蔽；那是自報健康，已修。
    def shadow_check(host, profile, config)
      observed = config.higher_precedence(@cwd)
      unobservable = observed.select { |_scope, snap| snap == :not_observable }.keys
      scannable = observed.reject { |_scope, snap| snap == :not_observable }

      if scannable.empty?
        # Codex 實測：專案層設定只帶 trust_level，沒有 MCP 覆寫可掃。
        # 照實說「這個 scope 無法觀測」，不假裝掃過了。
        return warn_("#{tag(host)}_no_shadow",
                     "#{unobservable.join(", ")} scope 無可觀測的 MCP 覆寫來源；遮蔽無法在此偵測")
      end

      problem = Contract::HostBinding.precedence_problem(scannable, profile)
      detail = "掃描 #{scannable.keys.join(", ")}"
      detail += "（#{unobservable.join(", ")} 無法觀測）" unless unobservable.empty?
      return bad("#{tag(host)}_no_shadow", "#{problem}｜#{detail}") unless problem.nil?

      ok("#{tag(host)}_no_shadow", "無遮蔽（#{detail}）")
    rescue HostConfig::DiscoveryError => e
      bad("#{tag(host)}_no_shadow", e.message[0, 120])
    end

    # --- binding / scope / cycle ----------------------------------------

    def binding_checks
      probe = SessionStart.produce(
        host: HostConfig.hosts.first, native_session_id: "doctor-probe",
        cwd: Dir.pwd, project_ref: "urn:omos:project:doctor", runtime_scope_mode: "EMPLOYEE_PRIVATE"
      )
      results = [ok("binding_bootstrap", "產出 effective_scope=#{probe["effective_scope"]}")]
      widened = begin
        SessionStart.produce(host: HostConfig.hosts.first, native_session_id: "doctor-probe",
                             cwd: Dir.pwd, project_ref: "urn:omos:project:doctor",
                             runtime_scope_mode: "EMPLOYEE_PRIVATE",
                             project_visibility_scope: widest_scope)
        nil
      rescue SessionStart::Refused => e
        e.code
      end
      results << (widened.nil? ? bad("project_narrowing", "專案竟可擴權") :
                  ok("project_narrowing", "擴權被拒：#{widened}"))
      results
    rescue SessionStart::Refused => e
      [bad("binding_bootstrap", e.code)]
    end

    def widest_scope
      scopes = Contract.spec.dig("ownership_visibility_contract", "visibility_scopes") || {}
      scopes.max_by { |_k, v| (v["default_readers"] || []).size }&.first
    end

    # 週期連續性：同一 review_period_id 至多一次 terminal closeout。
    def cycle_checks
      return [warn_("weekly_review_continuity", "store 不存在，略過")] unless File.exist?(store_path)

      store = Store.open(store_path)
      dupes = store.db.execute(
        "SELECT review_period_id, COUNT(*) FROM closeouts WHERE is_terminal = 1 GROUP BY review_period_id HAVING COUNT(*) > 1"
      )
      total = store.db.get_first_value("SELECT COUNT(*) FROM closeouts") || 0
      store.close
      [dupes.empty? ? ok("weekly_review_continuity", "#{total} 筆 closeout，無重複 terminal") :
       bad("weekly_review_continuity", "重複 terminal：#{dupes.inspect}")]
    end

    def uninstall_metadata_check
      data = @installer.receipt
      return bad("uninstall_metadata", "找不到安裝 receipt：#{@installer.receipt_path}") if data.nil?

      required = %w[installed_at product_root store_path commands hosts]
      missing = required.reject { |k| data.key?(k) }
      return bad("uninstall_metadata", "receipt 缺欄位：#{missing.inspect}") unless missing.empty?

      ok("uninstall_metadata", "receipt 完整（#{data["hosts"].keys.join(", ")}）")
    end

    def tag(host) = host.downcase.tr(" ", "_")
  end
end
