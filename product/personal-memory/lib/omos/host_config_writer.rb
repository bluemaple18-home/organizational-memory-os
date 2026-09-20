# frozen_string_literal: true
#
# 寫回 Host 使用者設定。這是整個產品唯一會動到使用者既有檔案的地方，
# 因此規則最嚴。
#
# **為什麼 TOML 不用 parse → dump**：實測 ~/.codex/config.toml（288 行 / 8,643
# bytes）經 toml-rb round-trip 後變成 203 行 / 8,100 bytes，3 個註解全部消失。
# 那等於拿使用者的設定檔去換一份「語意相同但人不認得」的檔案。因此 TOML 採
# **哨兵區塊的外科式編輯**：只在檔尾附加一段有明確界線的區塊，卸載時只移除
# 那段，其餘位元組完全不動。
#
# JSON（~/.claude.json 有 58 KB 使用者狀態）沒有註解，採 parse → 只改目標鍵
# → dump；但同樣先備份、寫後重讀複驗、不符即回滾。
#
# 三段式流程（Owner 規則：判定在寫入之前）：
#   1. 算出 after 快照，交既有切片 2 evaluator 判定；不合法就**不動檔案**
#   2. 備份 → 寫入
#   3. 重新讀回實際檔案複驗；不符就從備份回滾

require "json"
require "fileutils"
require_relative "contract"
require_relative "host_config"

module OMOS
  class HostConfigWriter
    class RefusedWrite < StandardError
      attr_reader :code

      def initialize(code)
        @code = code
        super(code)
      end
    end

    BEGIN_MARK = "# >>> omos-personal-memory (managed block — do not edit by hand) >>>"
    END_MARK = "# <<< omos-personal-memory <<<"

    # legacy_commands：{command_ref => 上一版實際寫進 Host 的具體命令}。
    # 來源只有 install receipt——遷移舊形狀安裝時，唯有靠這份精確證據才能
    # 認出「那條 hook 是我們自己上一版寫的」。**不得**用前綴或名稱相似去猜。
    def initialize(host, home:, mcp_command:, hook_command:, env: {}, legacy_commands: {})
      @host = host
      @home = home
      @env = env
      @mcp_command = mcp_command
      @hook_command = hook_command
      @legacy_commands = legacy_commands || {}
      # 安裝 receipt 記錄的對應：具體命令 → 契約 command_ref。
      @command_map = {
        mcp_command => Contract.spec.dig("personal_memory_host_binding_v1", "host_profiles",
                                         host, "mcp_registration", "command_ref"),
        hook_command => Contract.spec.dig("personal_memory_host_binding_v1", "host_profiles",
                                          host, "session_start_registration", "command_ref")
      }
      # hook_invocation 讀 @hook_command／@env，必須等它們賦值後才能呼叫；
      # repair-02 P2 把比對從前綴改成精確相等後，先前「先呼叫、後賦值」的
      # 順序會讓這裡存進去的鍵少了命令本體，只剩參數，永遠比對不到。
      @command_map[hook_invocation] = @command_map[hook_command]
      # 舊版命令一併登記進 map，映到同一個 command_ref。這樣讀取端會把它
      # 正規化成「本產品自己的註冊」，install 的 before/after 判定與
      # own_group? 才會一致地認出它——而且仍然是**精確字串**比對。
      @legacy_commands.each { |ref, cmd| @command_map[cmd] = ref if cmd.is_a?(String) && !cmd.empty? }
      @config = HostConfig.new(host, home: home, command_map: @command_map)
      @profile = Contract.spec.dig("personal_memory_host_binding_v1", "host_profiles", host)
    end

    attr_reader :config, :command_map

    def mcp_path = @config.mcp_config_path
    def hook_path = @config.hook_config_path

    # 目前所有受影響檔案的備份（install/uninstall 前呼叫）
    def snapshot_files
      [mcp_path, hook_path].uniq.each_with_object({}) do |path, acc|
        acc[path] = File.exist?(path) ? File.binread(path) : nil
      end
    end

    def restore(backup)
      backup.each do |path, content|
        if content.nil?
          FileUtils.rm_f(path)
        else
          FileUtils.mkdir_p(File.dirname(path))
          File.binwrite(path, content)
        end
      end
    end

    # --- install ---------------------------------------------------------

    def install
      before = @config.snapshot
      after = Contract::HostBinding.expected_install(before, @profile)
      guard!(before, after, :install)

      backup = snapshot_files
      begin
        apply_install
        verify!(after)
      rescue StandardError
        restore(backup)
        raise
      end
      { before: before, after: after, backup: backup }
    end

    def uninstall
      before = @config.snapshot
      after = Contract::HostBinding.expected_uninstall(before, @profile)
      guard!(before, after, :uninstall)

      backup = snapshot_files
      begin
        apply_uninstall
        verify!(after)
      rescue StandardError
        restore(backup)
        raise
      end
      { before: before, after: after, backup: backup }
    end

    private

    # 判定在寫入之前：合法性由切片 2 的既有 evaluator 決定，不是這裡自己判。
    def guard!(before, after, action)
      node = { "before" => before, "after" => after }
      problem = if action == :install
                  Contract::HostBinding.install_merge_problem(node, @profile)
                else
                  Contract::HostBinding.uninstall_merge_problem(node, @profile)
                end
      raise RefusedWrite, problem unless problem.nil?
    end

    # 寫完必須以**實際檔案**重讀複驗，不信自己剛剛寫了什麼。
    def verify!(expected)
      actual = HostConfig.new(@host, home: @home, command_map: @command_map).snapshot
      return if actual == expected

      raise RefusedWrite, "HBV1_POST_WRITE_VERIFY_MISMATCH"
    end

    def format_of(key) = @config.discovery.fetch(key)

    def apply_install
      write_block(mcp_path, format_of("mcp_config_format"), managed_block)
      return if hook_path == mcp_path

      write_block(hook_path, format_of("session_start_config_format"), managed_block)
    end

    def apply_uninstall
      remove_block(mcp_path, format_of("mcp_config_format"))
      return if hook_path == mcp_path

      remove_block(hook_path, format_of("session_start_config_format"))
    end

    # --- TOML：哨兵區塊外科式編輯 ----------------------------------------

    # 形狀取自 codex-cli 0.153.2 實證（見規格 registration_shape）：
    #   MCP entry 只有 command 與巢狀 .env 表，**沒有 transport**；
    #   hook 是 [[hooks.<Event>]] → [[hooks.<Event>.hooks]] 兩層，
    #   handler 帶 type/command，**沒有 id、也沒有 env**。
    # 因此本產品的 hook 以「命令列參數」攜帶 authority input，
    # 並以 command 字串辨識自己的註冊（不是 id）。
    def managed_block
      env_lines = @env.map { |k, v| "#{k} = #{v.to_json}" }.join("\n")
      <<~TOML.rstrip
        #{BEGIN_MARK}
        [mcp_servers."#{@config.own_mcp_id}"]
        command = #{@mcp_command.to_json}

        [mcp_servers."#{@config.own_mcp_id}".env]
        #{env_lines}

        [[hooks.SessionStart]]

        [[hooks.SessionStart.hooks]]
        type = "command"
        command = #{hook_invocation.to_json}
        #{END_MARK}
      TOML
    end

    # hook 無法帶 env，authority input 只能進命令列。設定檔本身就是信任邊界。
    def hook_invocation
      "#{@hook_command} --host #{@host.inspect} --runtime-scope-mode #{@env.fetch("OMOS_RUNTIME_SCOPE_MODE")}"
    end

    def write_block(path, format, block)
      case format
      when "TOML" then toml_write(path, block)
      when "JSON" then json_write(path)
      else raise RefusedWrite, "HBV1_UNKNOWN_CONFIG_FORMAT"
      end
    end

    def remove_block(path, format)
      case format
      when "TOML" then toml_remove(path)
      when "JSON" then json_remove(path)
      else raise RefusedWrite, "HBV1_UNKNOWN_CONFIG_FORMAT"
      end
    end

    def toml_write(path, block)
      FileUtils.mkdir_p(File.dirname(path))
      existing = File.exist?(path) ? File.read(path) : ""
      cleaned = strip_managed(existing)
      separator = cleaned.empty? || cleaned.end_with?("\n\n") ? "" : (cleaned.end_with?("\n") ? "\n" : "\n\n")
      File.write(path, "#{cleaned}#{separator}#{block}\n")
    end

    def toml_remove(path)
      return unless File.exist?(path)

      File.write(path, strip_managed(File.read(path)))
    end

    # 只移除哨兵之間的內容，其餘位元組不動。
    def strip_managed(text)
      return text unless text.include?(BEGIN_MARK)

      out = text.gsub(/#{Regexp.escape(BEGIN_MARK)}.*?#{Regexp.escape(END_MARK)}\n?/m, "")
      # 尾端換行收斂回單一個，卸載後才能與安裝前位元組完全相同。
      out.sub(/\n+\z/, "\n")
    end

    # --- JSON：只改目標鍵 ------------------------------------------------

    # install 與 uninstall 只差「放進去」還是「拿掉」，走同一條路徑。
    def json_write(_path) = mutate_registration(remove: false)
    def json_remove(_path) = mutate_registration(remove: true)

    def mutate_registration(remove:)
      mutate_json(mcp_path) do |doc|
        key = @config.discovery.fetch("mcp_entries_path")
        entries = (doc[key] ||= {})
        if remove
          entries.delete(@config.own_mcp_id)
        else
          entries[@config.own_mcp_id] = { "command" => @mcp_command, "env" => @env }
        end
      end
      mutate_json(hook_path) do |doc|
        # Claude Code 同樣是三層：event → matcher group → handler[]。
        # 自己的 group 以「handler 的 command」辨識，不是 id。
        groups = ((doc["hooks"] ||= {})["SessionStart"] ||= [])
        groups.reject! { |g| own_group?(g) }
        groups << { "hooks" => [{ "type" => "command", "command" => hook_invocation }] } unless remove
      end
    end

    # repair-02 P2：必須是**精確**比對，不能用裸 prefix。
    # reviewer 實測 ".../omos-personal-memory-session-start-foreign" 會被
    # start_with? 誤認成自己的 hook，install/uninstall 就可能動到別人的註冊。
    #
    # Slice A：改以 command_map 解析後的 command_ref 判定——map 的鍵是精確
    # 字串，因此 collision-adjacent 的第三方命令查不到、仍會被正確排除；
    # 同時自然涵蓋 receipt 提供的舊版命令（遷移用）。
    def own_group?(group)
      return false unless group.is_a?(Hash)

      own_ref = @command_map[@hook_command]
      Array(group["hooks"]).any? do |h|
        next false unless h.is_a?(Hash)

        cmd = h["command"].to_s
        @command_map.key?(cmd) && @command_map[cmd] == own_ref
      end
    end

    def mutate_json(path)
      FileUtils.mkdir_p(File.dirname(path))
      doc = File.exist?(path) ? JSON.parse(File.read(path)) : {}
      yield doc
      File.write(path, "#{JSON.pretty_generate(doc)}\n")
    end
  end
end
