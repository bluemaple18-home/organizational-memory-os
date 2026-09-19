# frozen_string_literal: true
#
# 本機 stdio MCP server。
#
# 契約 invariant：
#   - HOST_BINDING_IS_AN_ADAPTER_NOT_THE_RUNTIME
#     這支只是適配器。它不做任何治理判定，所有寫入一律經 OMOS::Runtime，
#     因此與 CLI 走的是同一套授權與交易層。
#   - NO_REMOTE_PERSONAL_STORE_ACCESS_SURFACE
#     只用 stdio transport；不開 HTTP、不轉送。
#
# surface 固定為 LOCAL_STDIO_MCP，因此每次呼叫都必須帶 HostSessionBinding，
# 由 Runtime 以切片 1／2 共用的 evaluator 判定；缺少或形狀不對一律明確失敗，
# 不 silent fallback。

require "json"
require "mcp"
require_relative "runtime"
require_relative "session_start"

module OMOS
  class MCPServer
    SURFACE = Runtime::SURFACES[:mcp]

    class << self
      attr_accessor :runtime
    end

    # 每個 tool 都先把 binding 還原出來，再交給 Runtime。binding 由 Host 在
    # SessionStart 產生後隨呼叫帶入——這裡不自己捏造身分。
    # MCP gem 會把 JSON 參數 deep-symbolize，但既有治理 evaluator 判定的是
    # **字串鍵**的契約形狀（allowlist 比的是 "executor_ref" 這種字串）。
    # 不正規化的話，一個完全合法的 binding 會被誤判成 UNKNOWN_FIELD——
    # 第一次跑 3b conformance 就是這樣紅的。
    def self.stringify(obj)
      case obj
      when Hash then obj.each_with_object({}) { |(k, v), acc| acc[k.to_s] = stringify(v) }
      when Array then obj.map { |v| stringify(v) }
      else obj
      end
    end

    def self.reply(text)
      MCP::Tool::Response.new([{ type: "text", text: text }])
    end

    def self.rejected(error)
      # 明確失敗：把契約錯誤碼原樣回給 Host，不吞掉、不降級。
      reply(JSON.generate({ "status" => "REJECTED", "code" => error.code, "detail" => error.detail }))
    end

    ReadTool = Class.new(MCP::Tool) do
      tool_name "personal_memory_read"
      description "讀出本機 Personal Store 的所有列（權限檢查先於讀取）"
      input_schema(
        properties: { "host_session_binding" => { type: "object" } },
        required: ["host_session_binding"]
      )
      define_singleton_method(:call) do |host_session_binding: nil, server_context: nil, **|
        rows = MCPServer.runtime.read_rows(surface: MCPServer::SURFACE,
                                           binding: MCPServer.stringify(host_session_binding))
        MCPServer.reply(JSON.generate(rows.map { |r| { "kind" => r[:kind], "row_id" => r[:row_id] } }))
      rescue Runtime::Rejected => e
        MCPServer.rejected(e)
      end
    end

    WriteTool = Class.new(MCP::Tool) do
      tool_name "personal_memory_write"
      description "寫入一列 Personal Memory；寫入前由既有治理 evaluator 判定，被拒者不落地"
      input_schema(
        properties: {
          "host_session_binding" => { type: "object" },
          "kind" => { type: "string" },
          "resource" => { type: "object" },
          "idempotency_key" => { type: "string" },
          "supersedes_ref" => { type: "string" }
        },
        required: %w[host_session_binding kind resource idempotency_key]
      )
      define_singleton_method(:call) do |host_session_binding: nil, kind: nil, resource: nil,
                                         idempotency_key: nil, supersedes_ref: nil, server_context: nil, **|
        result = MCPServer.runtime.write_row(
          kind: kind, resource: MCPServer.stringify(resource), idempotency_key: idempotency_key,
          supersedes_ref: supersedes_ref, surface: MCPServer::SURFACE,
          binding: MCPServer.stringify(host_session_binding)
        )
        MCPServer.reply(JSON.generate({ "status" => result[:replayed] ? "REPLAYED" : "WROTE",
                                        "row_id" => result[:row_id] }))
      rescue Runtime::Rejected => e
        MCPServer.rejected(e)
      end
    end

    CloseoutTool = Class.new(MCP::Tool) do
      tool_name "personal_memory_closeout"
      description "提交一次 weekly closeout；唯一性與 promotion idempotency 由既有 evaluator 判定"
      input_schema(
        properties: { "host_session_binding" => { type: "object" }, "closeout" => { type: "object" } },
        required: %w[host_session_binding closeout]
      )
      define_singleton_method(:call) do |host_session_binding: nil, closeout: nil, server_context: nil, **|
        result = MCPServer.runtime.commit_closeout(
          closeout: MCPServer.stringify(closeout), surface: MCPServer::SURFACE,
          binding: MCPServer.stringify(host_session_binding)
        )
        MCPServer.reply(JSON.generate({ "status" => "COMMITTED",
                                        "review_period_id" => result[:review_period_id],
                                        "terminal" => result[:terminal] }))
      rescue Runtime::Rejected => e
        MCPServer.rejected(e)
      end
    end

    TOOLS = [ReadTool, WriteTool, CloseoutTool].freeze

    def self.build(store_path)
      self.runtime = Runtime.open(store_path)
      MCP::Server.new(
        name: "omos-personal-memory",
        version: "0.1.0",
        instructions: "本機 Personal Memory Store。所有寫入經 Runtime 治理層，被拒者不落地。",
        tools: TOOLS
      )
    end

    # stdio only —— 契約 invariant NO_REMOTE_PERSONAL_STORE_ACCESS_SURFACE。
    def self.serve_stdio(store_path)
      server = build(store_path)
      MCP::Server::Transports::StdioTransport.new(server).open
    end
  end
end
