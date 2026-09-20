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

    # 這台機器上**無法驗證**的命題。
    #
    # 只有兩種合法用法，且都必須說清楚由誰負責：workspace B 沒有 repo
    # 原件可比對（由 repo 側的 drift gate 負責），以及需要真 Host 才能觀測
    # 的項目。一律印成 N/A 而不是 PASS——把驗不到的東西報成通過，正是
    # 本產品一路在防的「假成功」。N/A 不影響離開碼，但會出現在報表上。
    def skip(name, reason, group: @group)
      @rows << ["N/A", group, name, reason.to_s]
      nil
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
      skipped = @rows.count { |st, _, _, _| st == "N/A" }
      suffix = skipped.zero? ? "" : "（#{skipped} 項本環境無法驗證，見上方 N/A）"
      puts "\n#{@label}：#{@rows.size - failed - skipped}/#{@rows.size - skipped} PASS#{suffix}"
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

  # 真的跑 SessionStart hook executable，餵真 Host 的 stdin 形狀。
  # 測試不自己捏造 binding——binding 只能由 hook 落地、由 server 讀回。
  HOOK_EXE = File.expand_path("../exe/omos-personal-memory-session-start", __dir__)

  module_function

  def run_session_start(host:, session_id:, cwd:, state_dir:, scope_mode: "EMPLOYEE_PRIVATE",
                        source: "startup")
    payload = JSON.generate({ "session_id" => session_id, "cwd" => cwd,
                              "hook_event_name" => "SessionStart", "source" => source })
    out, err, st = Open3.capture3({ "OMOS_SESSION_STATE_DIR" => state_dir },
                                  HOOK_EXE, "--host", host, "--runtime-scope-mode", scope_mode,
                                  stdin_data: payload)
    [out, err, st]
  end

  class MCPClient
    EXE = File.expand_path("../exe/omos-personal-memory-mcp", __dir__)

    def initialize(store, host: nil, cwd: nil, state_dir: nil, session_id: nil,
                   scope_mode: "EMPLOYEE_PRIVATE", handshake: true)
      env = { "OMOS_PERSONAL_MEMORY_STORE" => store }
      # installer 會把這兩個寫進 MCP 註冊的 env 表；測試照做。
      env["OMOS_HOST"] = host if host
      env["OMOS_RUNTIME_SCOPE_MODE"] = scope_mode if host
      env["OMOS_SESSION_STATE_DIR"] = state_dir if state_dir
      # repair-02：server 自己找 native session id 的來源。目前唯一有官方管道
      # 的是 Claude Code（PROCESS_ENV），測試比照真 Host 把它放進子行程環境。
      env["CLAUDE_CODE_SESSION_ID"] = session_id if session_id && host == "Claude Code"
      @host = host
      opts = cwd ? { chdir: cwd } : {}
      @in, @out, @err, @wait = Open3.popen3(env, EXE, **opts)
      @id = 0
      initialize! if handshake
    end

    def initialize!
      rpc("initialize", { "protocolVersion" => "2024-11-05", "capabilities" => {},
                          "clientInfo" => { "name" => @host || "conformance", "version" => "0" } })
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

  # repo 原件的所在。workspace B（無 source checkout）沒有這個目錄，此時
  # 「package 與原件位元組相同」在本機無從驗證——由 repo 側的
  # validate_packaged_governance_drift.rb 負責，**不得**改成與自己比對。
  def repo_originals
    root = OMOS::Contract::REPO_ROOT
    Dir.exist?(File.join(root, "規格/v0.1")) ? root : nil
  end

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
