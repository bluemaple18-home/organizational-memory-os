# frozen_string_literal: true
#
# omos-personal-memory installer。
#
# 責任：初始化本機 store、把 MCP 與 SessionStart 註冊寫進**已交付 Host** 的
# 使用者設定、產出安裝 receipt；以及對應的 uninstall。
#
# 安全規則（主卡「安裝與復原」驗收組）：
#   - 判定先於寫入：每個 Host 的 merge 合法性由切片 2 既有 evaluator 判定，
#     不合法就完全不動檔案。
#   - 跨 Host 原子性：任一 Host 失敗，**所有**已動過的檔案都從備份還原，
#     不留下半套卻回報成功。
#   - 不碰非本產品的設定：TOML 用哨兵區塊外科式編輯，JSON 只改目標鍵。
#   - receipt 是卸載與 doctor 的依據，記錄 command_ref → 具體命令的對應。

require "json"
require "time"
require "fileutils"
require_relative "contract"
require_relative "host_config"
require_relative "host_config_writer"
require_relative "runtime"

module OMOS
  class Installer
    class Failed < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super(code)
      end
    end

    DEFAULT_STORE = "~/.omos/personal-memory/personal.db"
    RECEIPT_PATH = "~/.omos/personal-memory/install-receipt.json"

    attr_reader :home, :product_root

    def initialize(home: Dir.home, product_root: File.expand_path("../..", __dir__),
                   store_path: nil, runtime_scope_mode: "EMPLOYEE_PRIVATE")
      @home = home
      @product_root = product_root
      @store_path = store_path
      @runtime_scope_mode = runtime_scope_mode
    end

    def store_path = @store_path || expand(DEFAULT_STORE)
    def receipt_path = expand(RECEIPT_PATH)
    def mcp_command = File.join(@product_root, "exe/omos-personal-memory-mcp")
    def hook_command = File.join(@product_root, "exe/omos-personal-memory-session-start")

    def receipt
      return nil unless File.exist?(receipt_path)

      JSON.parse(File.read(receipt_path))
    end

    # receipt 記錄的 {具體命令 => command_ref}，供 HostConfig 正規化與 doctor 使用。
    def command_map
      HostConfig.hosts.each_with_object({}) do |host, acc|
        acc.merge!(writer_for(host).command_map)
      end
    end

    # --- install ---------------------------------------------------------

    # 預設只安裝**已交付**的 Host（repair-03 P2：v1 的 delivery scope 只有
    # Claude Code，不該再往 Codex 寫一套必定不能使用的 MCP + hook）。
    # Codex 的 profile 與設定面評估仍然保留——設定面認得它，不等於要交付它。
    # 需要明確安裝某個 blocked host（例如用真 codex CLI 驗證我們寫出的形狀）
    # 時，呼叫端要自己把它列進 hosts:，不會預設發生。
    def delivered_hosts = Contract.supported_hosts

    # 卸載預設依 install receipt 記錄的 hosts 清理；沒有 receipt 就掃過所有
    # 契約認識的 Host——先前版本曾把 Codex 也裝進去，不掃就會留下殘件。
    def installed_hosts
      receipt&.fetch("hosts", nil)&.keys || HostConfig.hosts
    end

    def install(hosts: delivered_hosts, fail_after: nil)
      raise Failed, "INSTALL_MCP_COMMAND_MISSING" unless File.executable?(mcp_command)
      raise Failed, "INSTALL_HOOK_COMMAND_MISSING" unless File.executable?(hook_command)

      backups = {}
      store_created = !File.exist?(store_path)
      schema_version = nil
      begin
        # 1. 本機 store
        runtime = Runtime.open(store_path)
        schema_version = runtime.store.schema_version
        runtime.store.close

        # 2. 逐個 Host 寫入；每一步先備份
        hosts.each do |host|
          writer = writer_for(host)
          backups.merge!(writer.snapshot_files) { |_k, old, _new| old }
          writer.install
          # 注入失敗點（conformance 用來實測「中途失敗不留半套」）
          raise Failed, "INSTALL_INJECTED_FAILURE" if fail_after == host
        end

        # 3. receipt
        write_receipt(hosts, schema_version)
      rescue StandardError
        rollback(backups, store_created)
        raise
      end
      { store_path: store_path, schema_version: schema_version, hosts: hosts, receipt: receipt }
    end

    def uninstall(hosts: installed_hosts, remove_store: false)
      backups = {}
      begin
        hosts.each do |host|
          writer = writer_for(host)
          backups.merge!(writer.snapshot_files) { |_k, old, _new| old }
          writer.uninstall
        end
        FileUtils.rm_f(receipt_path)
        # Personal Store 預設保留——卸載產品不等於銷毀個人記憶。
        FileUtils.rm_f(store_path) if remove_store
      rescue StandardError
        restore_all(backups)
        raise
      end
      { hosts: hosts, store_removed: remove_store }
    end

    # 升級：命令路徑或 schema 可能變了，重跑安裝即可（install 本身 idempotent）。
    def upgrade(hosts: delivered_hosts)
      install(hosts: hosts)
    end

    private

    def expand(path) = path.sub(%r{\A~(?=/)}, @home)

    # installer 是唯一可信的 authority 注入點：Host 的 stdin 不會給 host 與
    # runtime_scope_mode，模型也不得提供。MCP server 走官方的 env 表，
    # hook 沒有 env 欄位，只能走命令列參數。
    def trusted_env(host)
      { "OMOS_HOST" => host,
        "OMOS_RUNTIME_SCOPE_MODE" => @runtime_scope_mode,
        "OMOS_PERSONAL_MEMORY_STORE" => store_path }
    end

    def writer_for(host)
      HostConfigWriter.new(host, home: @home, mcp_command: mcp_command,
                                 hook_command: hook_command, env: trusted_env(host))
    end

    def write_receipt(hosts, schema_version)
      data = {
        "installed_at" => Time.now.utc.iso8601,
        "product_root" => @product_root,
        "ruby_version" => RUBY_VERSION,
        "store_path" => store_path,
        "schema_version" => schema_version,
        "commands" => command_map.invert,
        "hosts" => hosts.each_with_object({}) do |host, acc|
          config = HostConfig.new(host, home: @home)
          acc[host] = {
            "mcp_config_file" => config.mcp_config_path,
            "hook_config_file" => config.hook_config_path,
            "mcp_id" => config.own_mcp_id,
            "hook_id" => config.own_hook_id
          }
        end
      }
      FileUtils.mkdir_p(File.dirname(receipt_path))
      File.write(receipt_path, "#{JSON.pretty_generate(data)}\n")
    end

    def restore_all(backups)
      backups.each do |path, content|
        if content.nil?
          FileUtils.rm_f(path)
        else
          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite(path, content)
        end
      end
    end

    def rollback(backups, store_created)
      restore_all(backups)
      FileUtils.rm_f(receipt_path)
      # 這次安裝才建立的 store 才刪；既有 store 一律不動。
      return unless store_created

      [store_path, "#{store_path}-wal", "#{store_path}-shm"].each { |f| FileUtils.rm_f(f) }
    end
  end
end
