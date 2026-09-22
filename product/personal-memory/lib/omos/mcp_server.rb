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
# **HostSessionBinding 不是 tool 參數**（review P1-C）。
# 原本它是 tool argument，等於模型可以自己組一份形狀合法的 binding 再呼叫工具，
# 與契約宣告的「native session 是 authority」矛盾。現在 binding 由 server 自己
# 從兩個模型碰不到的來源建構：
#   1. installer 寫進 MCP 註冊的 env（OMOS_HOST / OMOS_RUNTIME_SCOPE_MODE）
#   2. SessionStart hook 落地的 session 記錄（session_id / cwd，Host 原生事實）
# 任一缺漏就 fail closed，不猜、不降級。

require "json"
require "mcp"
require_relative "runtime"
require_relative "session_start"
require_relative "session_state"

module OMOS
  class MCPServer
    SURFACE = Runtime::SURFACES[:mcp]

    class << self
      attr_accessor :runtime, :binding, :binding_problem
    end

    # server 必須能**獨立**得知自己屬於哪個 native session。來源由契約的
    # native_session_id_source 宣告，各 Host 不同；取不到就 fail closed，
    # 不用 cwd 之類的代理鍵去猜（repair-02 P1-1/P1-2）。
    def self.native_session_id(host)
      source = Contract.spec.dig("personal_memory_host_binding_v1", "bootstrap_contract",
                                 "native_session_id_source", host) || {}
      case source["mechanism"]
      when "PROCESS_ENV" then ENV[source.fetch("env_var")]
      end
    end

    # 由可信來源建構 binding。模型既不經手也無法改寫。
    def self.establish_binding!
      host = ENV["OMOS_HOST"]
      scope_mode = ENV["OMOS_RUNTIME_SCOPE_MODE"]
      if host.nil? || scope_mode.nil?
        self.binding_problem = "MCP_MISSING_TRUSTED_AUTHORITY_ENV"
        return
      end

      session_id = native_session_id(host)
      if session_id.nil? || session_id.to_s.strip.empty?
        # 例如 Codex：目前沒有任何機制讓 MCP server 得知 native session id，
        # 契約標為 UNDECIDED。在決定之前一律拒絕，不退回 cwd 猜測。
        self.binding_problem = "MCP_NATIVE_SESSION_ID_UNAVAILABLE"
        return
      end

      record = SessionState.read(host, session_id)
      if record.nil?
        self.binding_problem = "MCP_NO_SESSION_RECORD"
        return
      end

      self.binding = SessionStart.produce(
        host: host, native_session_id: session_id,
        cwd: record.fetch("cwd"), project_ref: SessionStart.project_ref_for(record.fetch("cwd")),
        runtime_scope_mode: scope_mode
      )
    rescue SessionStart::Refused => e
      self.binding_problem = e.code
    end

    def self.refuse_no_binding
      reply(JSON.generate({ "status" => "REFUSED", "code" => binding_problem,
                            "detail" => "此 session 沒有可信的 HostSessionBinding；" \
                                        "請確認 installer 已註冊且 SessionStart hook 已執行。" }))
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
      input_schema(properties: {}, required: [])
      define_singleton_method(:call) do |server_context: nil, **|
        return MCPServer.refuse_no_binding if MCPServer.binding.nil?

        rows = MCPServer.runtime.read_rows(surface: MCPServer::SURFACE, binding: MCPServer.binding)
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
          "kind" => { type: "string" },
          "resource" => { type: "object" },
          "idempotency_key" => { type: "string" },
          "supersedes_ref" => { type: "string" }
        },
        required: %w[kind resource idempotency_key]
      )
      define_singleton_method(:call) do |kind: nil, resource: nil, idempotency_key: nil,
                                         supersedes_ref: nil, server_context: nil, **|
        return MCPServer.refuse_no_binding if MCPServer.binding.nil?

        result = MCPServer.runtime.write_row(
          kind: kind, resource: MCPServer.stringify(resource), idempotency_key: idempotency_key,
          supersedes_ref: supersedes_ref, surface: MCPServer::SURFACE,
          binding: MCPServer.binding
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
        properties: { "closeout" => { type: "object" } },
        required: %w[closeout]
      )
      define_singleton_method(:call) do |closeout: nil, server_context: nil, **|
        return MCPServer.refuse_no_binding if MCPServer.binding.nil?

        result = MCPServer.runtime.commit_closeout(
          closeout: MCPServer.stringify(closeout), surface: MCPServer::SURFACE,
          binding: MCPServer.binding
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
      establish_binding!
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
