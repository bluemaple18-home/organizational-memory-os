# frozen_string_literal: true
#
# Host 設定探索：把切片 2 驗過的 **normalized 快照**綁到**實際檔案**。
#
# 切片 2 驗的是測資直接提供的三段式快照；這一層負責真的去讀
# ~/.codex/config.toml 與 ~/.claude.json / ~/.claude/settings.json，
# 正規化成同一個形狀，交給既有的 PersonalMemoryHostBinding evaluator 判定。
#
# **3b 邊界：唯讀。** 這裡沒有任何寫入路徑——安裝與 safe-merge 是 3c 的
# installer 交付項。路徑與結構讀自 host_profiles.<host>.config_discovery，
# 產品端不寫死。

require "json"
require "toml-rb"
require_relative "contract"

module OMOS
  class HostConfig
    class DiscoveryError < StandardError; end

    attr_reader :host, :discovery, :home

    # command_map：{具體命令 => 契約的 command_ref}。
    # 契約裡的 command_ref 是符號 token（例如 OMOS_PERSONAL_MEMORY_MCP），
    # 但實際設定檔必須放具體路徑。安裝 receipt 記錄兩者的對應，讓正規化後的
    # 快照回到契約詞彙——對不上就是漂移，由既有 evaluator 報
    # HBV1_EFFECTIVE_MCP_MISSING_OR_DRIFTED。
    def initialize(host, home: Dir.home, command_map: {})
      profile = Contract.spec.dig("personal_memory_host_binding_v1", "host_profiles", host)
      raise DiscoveryError, "未支援的 Host: #{host}" if profile.nil?

      @host = host
      @profile = profile
      @discovery = profile.fetch("config_discovery")
      @home = home
      @command_map = command_map
    end

    def self.hosts = Contract.spec.dig("personal_memory_host_binding_v1", "host_profiles").keys

    def mcp_config_path = expand(@discovery.fetch("mcp_config_file"))
    def hook_config_path = expand(@discovery.fetch("session_start_config_file"))

    # 檔案是否存在，是與「設定是否正確」不同的結果——doctor 必須分開報。
    def present?
      { mcp_config: File.exist?(mcp_config_path), hook_config: File.exist?(hook_config_path) }
    end

    # 讀出實際設定並正規化成切片 2 evaluator 吃的形狀。
    def snapshot
      { "mcp_entries" => read_mcp_entries, "session_start_hooks" => read_session_start_hooks }
    end

    # 更高優先序 scope 的實際快照（遮蔽偵測用）。
    #
    # 兩個 Host 的情況本質不同，實測為憑：
    #   Codex       ~/.codex/config.toml 的 [projects."<path>"] 只帶
    #               trust_level，沒有專案層 MCP 覆寫 → 這個 scope 不是
    #               遮蔽來源，回傳 :not_observable，讓 doctor 照實說。
    #   Claude Code <cwd>/.mcp.json 與 <cwd>/.claude/settings.local.json
    #               都可能以更高優先序蓋掉 user scope 的同名註冊。
    def higher_precedence(cwd)
      sources = @discovery["higher_precedence_sources"] || {}
      sources.each_with_object({}) do |(scope, conf), acc|
        if conf["mcp_entries_path"].nil? && conf["session_start_hooks_path"].nil?
          acc[scope] = :not_observable
          next
        end
        path = conf.fetch("file").sub("{cwd}", cwd.to_s)
        doc = load_file(expand(path), conf.fetch("format")) || {}
        entries = conf["mcp_entries_path"] ? dig_path(doc, conf["mcp_entries_path"]) : nil
        hooks = conf["session_start_hooks_path"] ? dig_path(doc, conf["session_start_hooks_path"]) : nil
        acc[scope] = {
          "mcp_entries" => normalize_entries(entries),
          "session_start_hooks" => normalize_hooks(hooks)
        }
      end
    end

    # 本產品自己的註冊是否已存在且未漂移——判定委派既有 evaluator。
    def own_registration_problem
      Contract::HostBinding.own_registration_problem(snapshot, @profile)
    end

    # 本產品宣告的註冊 id（安裝與 doctor 都用這兩個）
    def own_mcp_id = @profile.dig("mcp_registration", "id")
    def own_hook_id = @profile.dig("session_start_registration", "id")

    private

    def expand(path)
      path.sub(%r{\A~(?=/)}, @home)
    end

    def load_file(path, format)
      return nil unless File.exist?(path)

      raw = File.read(path)
      case format
      when "TOML" then TomlRB.parse(raw)
      when "JSON" then JSON.parse(raw)
      else raise DiscoveryError, "未知設定格式: #{format}"
      end
    rescue TomlRB::ParseError, JSON::ParserError => e
      # 設定壞掉要明確失敗，不 silent fallback 成「沒有註冊」。
      raise DiscoveryError, "#{path} 無法解析（#{format}）：#{e.message}"
    end

    def dig_path(doc, dotted)
      dotted.split(".").inject(doc) { |node, seg| node.is_a?(Hash) ? node[seg] : nil }
    end

    def read_mcp_entries
      doc = load_file(mcp_config_path, @discovery.fetch("mcp_config_format"))
      return {} if doc.nil?

      normalize_entries(dig_path(doc, @discovery.fetch("mcp_entries_path")))
    end

    # 正規化成切片 2 的 mcp entry 形狀：只保留契約關心的欄位，
    # 其餘 Host 專屬設定不進快照（快照是判定用，不是備份）。
    def normalize_entries(entries)
      return {} unless entries.is_a?(Hash)

      entries.each_with_object({}) do |(id, cfg), acc|
        next unless cfg.is_a?(Hash)

        acc[id] = { "transport" => transport_of(cfg), "command_ref" => command_ref_of(cfg) }
      end
    end

    def read_session_start_hooks
      doc = load_file(hook_config_path, @discovery.fetch("session_start_config_format"))
      return [] if doc.nil?

      normalize_hooks(dig_path(doc, @discovery.fetch("session_start_hooks_path")))
    end

    # 兩個 Host 的 hook 都是三層：event → matcher group → handler[]。
    # handler **沒有 id**，所以這裡把每個 handler 攤平，並以 command 辨識
    # 本產品自己那一筆；辨識出來後仍以契約的 own_hook_id 呈現，讓切片 2 的
    # 既有 evaluator 不需要任何改動。
    def normalize_hooks(groups)
      return [] if groups.nil?

      Array(groups).flat_map.with_index do |group, gi|
        handlers = group.is_a?(Hash) ? Array(group["hooks"]) : []
        handlers = [group] if handlers.empty? && group.is_a?(Hash) && group.key?("command")
        handlers.each_with_index.map do |handler, hi|
          next unless handler.is_a?(Hash)

          ref = command_ref_of(handler)
          { "id" => hook_id_for(ref, gi, hi), "event" => "SessionStart", "command_ref" => ref }
        end.compact
      end
    end

    def hook_id_for(command_ref, group_index, handler_index)
      return own_hook_id if command_ref == own_hook_command_ref

      "unnamed-#{group_index}-#{handler_index}"
    end

    def own_hook_command_ref
      @profile.dig("session_start_registration", "command_ref")
    end

    # 兩個 Host 的欄位名不同（Codex 用 command/args，Claude 用 command），
    # 正規化成契約詞彙 command_ref；判定仍由既有 evaluator 做。
    def command_ref_of(cfg)
      cmd = cfg["command_ref"] || cfg["command"] || cfg.dig("hooks", 0, "command")
      concrete = cmd.is_a?(Array) ? cmd.join(" ") : cmd.to_s
      return @command_map[concrete] if @command_map.key?(concrete)

      # hook 的 authority input 走命令列參數，所以實際字串是「命令 + 參數」；
      # 以最長前綴命中，避免因為多了參數就判成漂移。
      hit = @command_map.keys.select { |k| concrete.start_with?(k) }.max_by(&:length)
      hit ? @command_map[hit] : concrete
    end

    def transport_of(cfg)
      return cfg["transport"] if cfg["transport"].is_a?(String)

      cfg.key?("url") ? "HTTP" : "STDIO"
    end
  end
end
