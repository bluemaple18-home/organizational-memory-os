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

    # normalized 快照的形狀，與切片 2 的 config_snapshot_contract 一致。
    EMPTY = { "mcp_entries" => {}, "session_start_hooks" => [] }.freeze

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

      entries = dig_path(doc, @discovery.fetch("mcp_entries_path"))
      return {} unless entries.is_a?(Hash)

      # 正規化成切片 2 的 mcp entry 形狀：只保留契約關心的欄位，
      # 其餘 Host 專屬設定不進快照（快照是判定用，不是備份）。
      entries.each_with_object({}) do |(id, cfg), acc|
        next unless cfg.is_a?(Hash)

        acc[id] = { "transport" => transport_of(cfg), "command_ref" => command_ref_of(cfg) }
      end
    end

    def read_session_start_hooks
      doc = load_file(hook_config_path, @discovery.fetch("session_start_config_format"))
      return [] if doc.nil?

      hooks = dig_path(doc, @discovery.fetch("session_start_hooks_path"))
      return [] if hooks.nil?

      list = hooks.is_a?(Array) ? hooks : [hooks]
      list.each_with_index.map do |entry, index|
        next unless entry.is_a?(Hash)

        { "id" => entry["id"] || entry["name"] || "unnamed-#{index}",
          "event" => "SessionStart",
          "command_ref" => command_ref_of(entry) }
      end.compact
    end

    # 兩個 Host 的欄位名不同（Codex 用 command/args，Claude 用 command），
    # 正規化成契約詞彙 command_ref；判定仍由既有 evaluator 做。
    def command_ref_of(cfg)
      cmd = cfg["command_ref"] || cfg["command"] || cfg.dig("hooks", 0, "command")
      concrete = cmd.is_a?(Array) ? cmd.join(" ") : cmd.to_s
      @command_map.fetch(concrete, concrete)
    end

    def transport_of(cfg)
      return cfg["transport"] if cfg["transport"].is_a?(String)

      cfg.key?("url") ? "HTTP" : "STDIO"
    end
  end
end
