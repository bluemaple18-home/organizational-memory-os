# frozen_string_literal: true
#
# conformance 共用支援：檢查收集、測試資料、真的 MCP stdio 用戶端、假 HOME。
#
# 三支 conformance 原本各自重寫了 check/RESULTS、link_body、EMP 與一份幾乎
# 相同的 stdio 用戶端。那正是自己一路在 review 裡被罰的「第二份實作」，
# 只是發生在測試側，所以集中到這裡。

require "json"
require "open3"
require "fileutils"

module Support
  # --- 檢查收集與輸出 --------------------------------------------------

  class Checks
    attr_accessor :group

    def initialize(label)
      @label = label
      @rows = []
      @group = nil
    end

    def check(name, detail, ok, group: @group)
      @rows << [ok ? "PASS" : "FAIL", group, name, detail.to_s]
      ok
    end

    # 期待被治理層拒絕，且**實際資料表不得多出任何一列**。
    def expect_rejected(name, code, store, group: @group)
      before = store.db.get_first_value("SELECT COUNT(*) FROM memory_rows")
      actual = begin
        yield
        nil
      rescue OMOS::Runtime::Rejected => e
        e.code
      end
      after = store.db.get_first_value("SELECT COUNT(*) FROM memory_rows")
      check(name, actual.nil? ? "未被拒絕（預期 #{code}）" : actual.to_s,
            actual == code && before == after, group: group)
    end

    def report!
      width = @rows.map { |_, _, n, _| n.length }.max || 20
      groups = @rows.map { |r| r[1] }.compact.uniq
      ordered = groups.empty? ? @rows : groups.flat_map { |g| @rows.select { |r| r[1] == g } }
      ordered.each do |st, g, n, d|
        prefix = g ? "#{st} #{g}" : st
        puts format("%-6s %-#{width}s  %s", prefix, n, d)
      end
      failed = @rows.count { |st, _, _, _| st == "FAIL" }
      puts "\n#{@label}：#{@rows.size - failed}/#{@rows.size} PASS"
      exit(failed.zero? ? 0 : 1)
    end
  end

  # --- 測試資料：依上游 required_fields 組出真的合法的本體 ---------------

  module Fixtures
    EMP = "urn:omos:employee:emp-001"
    CAND = "urn:omos:personal-memory:candidate:01900000-0000-7000-8000-0000000000c9"

    module_function

    def link_id(suffix) = "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000#{suffix}"
    def record_id(suffix) = "urn:omos:personal-memory:record:01900000-0000-7000-8000-0000000000#{suffix}"
    def candidate_id(suffix) = "urn:omos:personal-memory:candidate:01900000-0000-7000-8000-0000000000#{suffix}"
    def review_period(week) = "urn:omos:personal-memory:review-period:#{week}"

    def link_body(link_id, target)
      { "link_id" => link_id, "tenant_id" => "t-acme", "employee_owner_ref" => EMP,
        "target_ref" => target, "evidence_ref" => "urn:omos:evidence:ev-001",
        "source_anchor_ref" => "urn:omos:source-anchor:sa-001",
        "source_anchor_profile" => "MARKDOWN_TEXT_V1", "relation" => "SUPPORTS",
        "anchor_resolution" => "EXACT_MATCH",
        "provenance" => { "created_by" => EMP, "created_at" => "2026-09-20T09:00:00Z" } }
    end

    def record_body(record_id, link_ref)
      { "record_id" => record_id, "tenant_id" => "t-acme", "employee_owner_ref" => EMP,
        "origin_candidate_ref" => CAND, "memory_kind" => "DECISION",
        "content" => { "statement_or_structured_content" => "改用 WAL 模式以支援並行讀取" },
        "applicability" => { "scope_mode" => "EMPLOYEE_PRIVATE",
                             "applies_to_refs" => ["urn:omos:project:omos"] },
        "validity_interval" => { "effective_from" => "2026-09-01T00:00:00Z" },
        "support_link_refs" => [link_ref],
        "candidate_snapshot" => { "candidate_status" => "ACCEPTED_FOR_RECORD",
                                  "verification_status" => "PASS", "acceptance_status" => "ACCEPTED" },
        "governance" => { "ownership_mode" => "EMPLOYEE_OWNED", "visibility_scope" => "EMPLOYEE_PRIVATE",
                          "verification_status" => "PASS", "acceptance_status" => "ACCEPTED",
                          "verification_receipt_ref" => "urn:omos:verification-receipt:vr-001",
                          "personal_acceptance_ref" => "urn:omos:personal-acceptance:pa-001",
                          "sensitivity" => "NORMAL", "acl_ref" => "urn:omos:acl:acl-001",
                          "freshness" => "CURRENT", "review_due_at" => "2026-12-01T00:00:00Z",
                          "conflict_refs" => [], "supersedes" => [], "superseded_by" => [],
                          "retention_state" => "RETAINED" },
        "chronology" => { "created_at" => "2026-09-20T09:00:00Z",
                          "effective_from" => "2026-09-01T00:00:00Z" },
        "record_status" => "ACTIVE" }
    end

    def closeout(period, item, status, attempt, promotion_key: "pk-001")
      { "review_period_id" => period, "scheduled_review_period_start" => "2026-09-18",
        "scheduled_anchor_at" => "2026-09-18T15:00:00Z", "actual_closeout_at" => "2026-09-18T17:30:00Z",
        "attempt_kind" => attempt, "final_status" => status, "catch_up_deadline_passed" => true,
        "selected_item_refs" => [item],
        "item_dispositions" => { item => { "category" => "MATERIALLY_CHANGED",
                                           "promotion_ref" => "urn:omos:promotion:pr-001",
                                           "promotion_idempotency_key" => promotion_key } } }
    end
  end

  # --- 真的 MCP stdio 子進程（一個實例＝一個進程）-----------------------

  class MCPClient
    EXE = File.expand_path("../exe/omos-personal-memory-mcp", __dir__)

    attr_reader :binding

    def initialize(store, binding: nil, handshake: true)
      @binding = binding
      @in, @out, @err, @wait = Open3.popen3({ "OMOS_PERSONAL_MEMORY_STORE" => store }, EXE)
      @id = 0
      initialize! if handshake
    end

    def initialize!
      name = @binding ? @binding["executor_ref"] : "conformance"
      rpc("initialize", { "protocolVersion" => "2024-11-05", "capabilities" => {},
                          "clientInfo" => { "name" => name, "version" => "0" } })
      notify("notifications/initialized")
    end

    def rpc(method, params = nil)
      @id += 1
      payload = { "jsonrpc" => "2.0", "id" => @id, "method" => method }
      payload["params"] = params if params
      @in.puts(JSON.generate(payload))
      @in.flush
      line = @out.gets
      line && JSON.parse(line)
    end

    def notify(method, params = {})
      @in.puts(JSON.generate({ "jsonrpc" => "2.0", "method" => method, "params" => params }))
      @in.flush
    end

    # 回傳 [原始 response, 解析後的 tool 內容]
    def call_tool(name, args)
      args = args.merge("host_session_binding" => @binding) if @binding
      res = rpc("tools/call", { "name" => name, "arguments" => args })
      text = res&.dig("result", "content", 0, "text")
      [res, text && (begin
        JSON.parse(text)
      rescue JSON::ParserError
        text
      end)]
    end

    def write(kind, resource, key, supersedes = nil)
      args = { "kind" => kind, "resource" => resource, "idempotency_key" => key }
      args["supersedes_ref"] = supersedes if supersedes
      call_tool("personal_memory_write", args).last
    end

    def read = call_tool("personal_memory_read", {}).last
    def closeout(payload) = call_tool("personal_memory_closeout", { "closeout" => payload }).last

    def close
      @in.close
      @wait.value
    rescue IOError
      nil
    end
  end

  # --- 假 HOME：全程不碰使用者的正式設定 --------------------------------

  module FakeHome
    module_function

    def seed(home)
      FileUtils.mkdir_p(File.join(home, ".codex"))
      FileUtils.mkdir_p(File.join(home, ".claude"))
      File.write(File.join(home, ".codex/config.toml"),
                 "# 使用者自己的註解\nmodel = \"gpt-5\"\n\n[mcp_servers.foreign]\ncommand = \"f\"\n")
      File.write(File.join(home, ".claude.json"),
                 "#{JSON.pretty_generate({ 'mcpServers' => { 'relay' => { 'command' => 'r' } },
                                           'userState' => { 'k' => 1 } })}\n")
      File.write(File.join(home, ".claude/settings.json"),
                 "#{JSON.pretty_generate({ 'theme' => 'dark' })}\n")
      home
    end

    def read_all(home)
      { codex: File.read(File.join(home, ".codex/config.toml")),
        claude: File.read(File.join(home, ".claude.json")),
        settings: File.read(File.join(home, ".claude/settings.json")) }
    end
  end
end
