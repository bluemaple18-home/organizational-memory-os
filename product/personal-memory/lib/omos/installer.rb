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
require "digest"
require "fileutils"
require_relative "artifact"
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

    # --- activation 佈局（Q7 §0.1 凍結的三層分離）-------------------------
    #
    #   Host identity      bin/ 底下的固定 launcher —— 寫進 Host，升版不變
    #   activation pointer current -> versions/<artifact-id>
    #   artifact identity  versions/<artifact-id> —— 內容決定，見 OMOS::Artifact
    #
    # 這三者**不得**再由單一 product_root 兼任。特別是：寫進 Host 的 command
    # 只能是 launcher 路徑，絕不能用 __dir__ 推導出來的路徑——Ruby 的 __dir__
    # 會解析 symlink，沿用它等於把 versions/<id> 寫進 Host，stale-hook 立刻
    # 復發（Q7 §0.4）。
    def omos_home = expand("~/.omos/personal-memory")
    def bin_dir = File.join(omos_home, "bin")
    def versions_dir = File.join(omos_home, "versions")
    def current_link = File.join(omos_home, "current")

    # 寫進 Host 的就是這兩條，永遠不含版本。
    def mcp_command = File.join(bin_dir, "omos-personal-memory-mcp")
    def hook_command = File.join(bin_dir, "omos-personal-memory-session-start")

    # artifact 內的實際執行目標（launcher 透過 current 轉過去）。
    LAUNCHER_NAMES = %w[omos-personal-memory-mcp omos-personal-memory-session-start].freeze

    # 要 materialize 進 artifact 的治理檔：2 份 spec ＋ 7 支共用 evaluator。
    # 相對結構與 repo 內一致，Slice C 的 drift gate 因此只需逐路徑比對。
    GOVERNANCE_FILES = [
      "規格/v0.1/personal-harness-integration.yaml",
      "規格/v0.1/common-vocabulary.yaml",
      *%w[omos_contract_helpers host_session_binding_shape personal_memory_resource_evaluator
          weekly_closeout_history minimal_evidence_package_shape runtime_log_oracle
          personal_memory_host_binding].map { |n| "scripts/lib/#{n}.rb" }
    ].freeze

    # artifact payload：產品自己的檔案。governance/ 由 materialize 另外放進去。
    PAYLOAD_ENTRIES = %w[lib exe bin vendor Gemfile Gemfile.lock .ruby-version .bundle].freeze

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
      source_mcp = File.join(@product_root, "exe/omos-personal-memory-mcp")
      source_hook = File.join(@product_root, "exe/omos-personal-memory-session-start")
      raise Failed, "INSTALL_MCP_COMMAND_MISSING" unless File.executable?(source_mcp)
      raise Failed, "INSTALL_HOOK_COMMAND_MISSING" unless File.executable?(source_hook)

      backups = {}
      store_created = !File.exist?(store_path)
      previous = receipt
      schema_version = nil
      artifact_id = nil
      begin
        # 0. 遷移前置：證據不足就當場停，不猜、不刪
        refuse_unknown_legacy!(hosts)

        # 1. 本機 store
        runtime = Runtime.open(store_path)
        schema_version = runtime.store.schema_version
        runtime.store.close

        # 2. artifact：stage → hash → rename。先算 id 再定目錄，否則 id 會
        #    參照到自己所在的路徑。
        artifact_id = materialize_artifact

        # 3. 固定 launcher（Host identity）與 current pointer（activation）
        write_launchers
        activate(artifact_id)

        # 4. 逐個 Host 寫入；每一步先備份
        hosts.each do |host|
          writer = writer_for(host)
          backups.merge!(writer.snapshot_files) { |_k, old, _new| old }
          writer.install
          # 注入失敗點（conformance 用來實測「中途失敗不留半套」）
          raise Failed, "INSTALL_INJECTED_FAILURE" if fail_after == host
        end

        # 5. receipt
        write_receipt(hosts, schema_version, artifact_id, previous)
      rescue StandardError
        rollback(backups, store_created)
        raise
      end
      { store_path: store_path, schema_version: schema_version, hosts: hosts,
        artifact_id: artifact_id, receipt: receipt }
    end

    def uninstall(hosts: installed_hosts, remove_store: false)
      backups = {}
      begin
        hosts.each do |host|
          writer = writer_for(host)
          backups.merge!(writer.snapshot_files) { |_k, old, _new| old }
          writer.uninstall
        end
        remove_activation
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

    # --- artifact materialize（stage → hash → rename）---------------------

    # 回傳 artifact id。若同內容的版本已存在就直接重用——install 因此是
    # idempotent 的，重裝不會每次長出一個新目錄。
    def materialize_artifact
      FileUtils.mkdir_p(versions_dir)
      stage = File.join(omos_home, ".staging-#{Process.pid}-#{rand(1 << 32).to_s(36)}")
      begin
        FileUtils.mkdir_p(stage)
        PAYLOAD_ENTRIES.each do |entry|
          src = File.join(@product_root, entry)
          next unless File.exist?(src)

          FileUtils.cp_r(src, File.join(stage, entry), preserve: true)
        end
        materialize_governance(stage)

        id = Artifact.identity(stage)
        target = File.join(versions_dir, id)
        if Dir.exist?(target)
          FileUtils.rm_rf(stage)
        else
          File.rename(stage, target)
        end
        id
      rescue StandardError
        FileUtils.rm_rf(stage)
        raise
      end
    end

    # 2 份 spec ＋ 7 支 evaluator 複製進 artifact，**byte-identical**。
    # 來源是 repo 原件；artifact 內維持相同相對結構。
    def materialize_governance(stage)
      GOVERNANCE_FILES.each do |rel|
        src = File.join(Contract::REPO_ROOT, rel)
        raise Failed, "INSTALL_GOVERNANCE_SOURCE_MISSING: #{rel}" unless File.file?(src)

        dst = File.join(stage, "governance", rel)
        FileUtils.mkdir_p(File.dirname(dst))
        FileUtils.cp(src, dst, preserve: true)
        next if Digest::SHA256.file(src).hexdigest == Digest::SHA256.file(dst).hexdigest

        raise Failed, "INSTALL_GOVERNANCE_COPY_MISMATCH: #{rel}"
      end
    end

    # 固定 launcher：Host 只認這兩條路徑，內容轉發到 current 背後的 artifact。
    # 參數一律原樣轉傳——hook 的 --host / --runtime-scope-mode 是 authority
    # 注入管道，不能在這裡被吃掉（Q7 §0.4）。
    def write_launchers
      FileUtils.mkdir_p(bin_dir)
      LAUNCHER_NAMES.each do |name|
        path = File.join(bin_dir, name)
        File.write(path, <<~SH)
          #!/bin/sh
          # 由 omos-personal-memory installer 產生，請勿手改。
          # Host 設定只認這條固定路徑；實際執行的版本由 current 決定。
          exec "#{current_link}/exe/#{name}" "$@"
        SH
        FileUtils.chmod(0o755, path)
      end
    end

    # 卸載時移除 activation 的三層：launcher、current pointer、所有 artifact
    # 版本。**只刪這三樣**——`~/.omos/personal-memory/` 這個父目錄底下還有
    # Personal Store 與 session state，預設一律保留（Q7 裁決點 7）。
    def remove_activation
      LAUNCHER_NAMES.each { |name| FileUtils.rm_f(File.join(bin_dir, name)) }
      FileUtils.rm_f(current_link)
      FileUtils.rm_rf(versions_dir)
      # bin/ 只有在被我們清空後才移除；若使用者放了別的東西就留著。
      Dir.rmdir(bin_dir) if Dir.exist?(bin_dir) && Dir.children(bin_dir).empty?
    end

    # current 切換必須原子：先建暫時 symlink 再 rename(2) 蓋過去。
    # 不用 `ln -sfn`——那是先刪後建，中間有一個 current 不存在的窗口。
    def activate(artifact_id)
      tmp = "#{current_link}.switching-#{Process.pid}"
      FileUtils.rm_f(tmp)
      File.symlink(File.join(versions_dir, artifact_id), tmp)
      File.rename(tmp, current_link)
    end

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
                                 hook_command: hook_command, env: trusted_env(host),
                                 legacy_commands: legacy_commands)
    end

    # 上一版實際寫進 Host 的具體命令，來源只有 receipt。沒有 receipt 就是
    # 沒有證據——這時**不猜**，見 refuse_unknown_legacy!。
    def legacy_commands
      current = [mcp_command, hook_command]
      (receipt&.fetch("commands", nil) || {}).reject { |_ref, cmd| current.include?(cmd) }
    end

    # 遷移的辨識 authority：只認 receipt 給的精確命令。若 Host 設定裡出現
    # 「執行檔名正好是我們的、但路徑不是目前 launcher、receipt 又沒記過」
    # 的註冊，代表證據不足——**當場失敗並說清楚**，不得自行刪除。
    # 誤刪使用者或第三方的 hook，比裝不起來嚴重得多。
    def refuse_unknown_legacy!(hosts)
      known = legacy_commands.values + [mcp_command, hook_command]
      hosts.each do |host|
        config = HostConfig.new(host, home: @home, command_map: command_map)
        next unless config.present?[:mcp_config]

        config.snapshot["session_start_hooks"].each do |hook|
          cmd = hook["command_ref"].to_s
          next if hook["id"] == config.own_hook_id || known.include?(cmd)
          next unless File.basename(cmd.split(" ").first.to_s) == "omos-personal-memory-session-start"

          raise Failed, "INSTALL_UNKNOWN_LEGACY_REGISTRATION: #{cmd}"
        end
      end
    end

    def write_receipt(hosts, schema_version, artifact_id, previous)
      data = {
        "installed_at" => Time.now.utc.iso8601,
        # artifact identity：內容決定，與安裝位置、mtime、本 receipt 無關。
        # 與 store 的 schema_version 是**兩件不同的事**，不得互相冒充。
        "artifact_id" => artifact_id,
        # rollback 要知道上一版是誰——不得靠重新下載或猜 SHA（Q7 裁決點 4）。
        "previous_artifact_id" => previous && (previous["artifact_id"] ||
                                               previous.dig("artifact", "id")),
        # 遷移用的精確證據：上一次實際寫進 Host 的 command **原文**
        # （receipt 的 commands 是 {command_ref => 具體命令}，要的是值不是鍵）。
        # 舊 hook 的辨識只能靠這個，不得用前綴或「看起來像 OMOS」去猜。
        "previous_commands" => previous && (previous["commands"] || {}),
        "build_source_root" => @product_root,
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
