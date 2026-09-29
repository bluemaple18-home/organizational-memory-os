# frozen_string_literal: true
#
# 切片 3b conformance：對**實物**驗收。
#
# 不是模擬 MCP、不是直接呼叫 server 物件——這裡真的 spawn 一個
# omos-personal-memory-mcp 子進程，用真的 stdio JSON-RPC 跟它講話，
# 寫進真的 SQLite，再用**獨立的連線**把資料讀回來確認。
#
# Host 設定探索一律在假 HOME 進行，不碰使用者的正式設定（3b 唯讀，
# 連寫入路徑都還不存在——安裝是 3c）。

require "json"
require "tmpdir"
require "fileutils"
require "open3"
require "sqlite3"
require "rbconfig"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "omos/version_guard"
OMOS::VersionGuard.assert!
require "omos/host_config"
require "omos/session_start"
require_relative "support"

C = Support::Checks.new("3b conformance")
F = Support::Fixtures
L1 = F.link_id("b1")
R1 = F.record_id("01")


Dir.mktmpdir("omos-3b") do |dir|
  store = File.join(dir, "personal.db")

  # --- SessionStart 產出 binding（推導委派切片 2 evaluator）---
  binding = OMOS::SessionStart.produce(
    host: "Claude Code", native_session_id: "claude-session-3b", cwd: File.join(dir, "projA"),
    project_ref: "urn:omos:project:a", runtime_scope_mode: "EMPLOYEE_PRIVATE"
  )
  C.check("SessionStart 產出 binding", binding["effective_scope"], binding["effective_scope"] == "SELF_ONLY")

  codex_binding = OMOS::SessionStart.produce(
    host: "Codex", native_session_id: "codex-session-3b", cwd: File.join(dir, "projA"),
    project_ref: "urn:omos:project:a", runtime_scope_mode: "EMPLOYEE_PRIVATE"
  )
  C.check("Codex 重新納入 delivered host，SessionStart 可產 binding",
          codex_binding["executor_ref"].to_s, codex_binding["executor_ref"] == "Codex")

  unknown = begin
    OMOS::SessionStart.produce(host: "DeepSeek Harness", native_session_id: "s", cwd: dir,
                               project_ref: "p", runtime_scope_mode: "EMPLOYEE_PRIVATE")
    nil
  rescue OMOS::SessionStart::Refused => e
    e.code
  end
  C.check("完全不認識的 Host 回的是 HOST_NOT_SUPPORTED，與 blocked 分得開", unknown.to_s,
          unknown == "HBV1_HOST_NOT_SUPPORTED")

  widened = begin
    OMOS::SessionStart.produce(host: "Claude Code", native_session_id: "s", cwd: dir,
                               project_ref: "p", runtime_scope_mode: "EMPLOYEE_PRIVATE",
                               project_visibility_scope: "WORK_CONTEXT_PARTICIPANTS")
    nil
  rescue OMOS::SessionStart::Refused => e
    e.code
  end
  C.check("專案不得擴權", widened, widened == "HBV1_PROJECT_SCOPE_WIDENS_BASELINE")

  # --- 真的跑 SessionStart hook（真 Host 的 stdin 形狀），再 spawn MCP server ---
  #
  # Claude Code 的既有 PROCESS_ENV happy path 保留；Codex 的 MCP_REQUEST_META
  # 路徑在後段以真 JSON-RPC `_meta.threadId` 另外驗。
  state_dir = File.join(dir, "state")
  proj = File.join(dir, "projA")
  FileUtils.mkdir_p(proj)
  sid = "claude-session-3b"
  hook_out, _hook_err, hook_st = Support.run_session_start(
    host: "Claude Code", session_id: sid, cwd: proj, state_dir: state_dir
  )
  C.check("SessionStart hook 吃真 Host stdin 並成功", "exit=#{hook_st.exitstatus}",
          hook_st.success? && hook_out.include?("hookSpecificOutput"))

  no_sid_out, no_sid_err, no_sid_st = Support.run_session_start(
    host: "Claude Code", session_id: "", cwd: proj, state_dir: state_dir
  )
  C.check("stdin 缺 session_id 時 hook 明確拒絕", (no_sid_err + no_sid_out).strip[0, 40],
          !no_sid_st.success? && (no_sid_err + no_sid_out).include?("MISSING_HOST_SESSION_ID"))

  client = Support::MCPClient.new(store, host: "Claude Code", cwd: proj, state_dir: state_dir,
                                  session_id: sid, handshake: false)
  init = client.rpc("initialize", { "protocolVersion" => "2024-11-05",
                                        "capabilities" => {},
                                        "clientInfo" => { "name" => "conformance", "version" => "0" } })
  C.check("MCP initialize 握手", init&.dig("result", "serverInfo", "name").to_s,
        init&.dig("result", "serverInfo", "name") == "omos-personal-memory")
  client.notify("notifications/initialized")

  tools = client.rpc("tools/list")
  names = (tools&.dig("result", "tools") || []).map { |t| t["name"] }.sort
  C.check("tools/list 暴露三個 tool", names.inspect,
        names == %w[personal_memory_closeout personal_memory_read personal_memory_write])

  # binding 不再是 tool 參數——模型連提供的欄位都沒有。
  write_schema = (tools&.dig("result", "tools") || []).find { |t| t["name"] == "personal_memory_write" }
  schema_props = (write_schema&.dig("inputSchema", "properties") || {}).keys.sort
  C.check("tool schema 不含 host_session_binding（模型無從提供）", schema_props.inspect,
          !schema_props.include?("host_session_binding"))

  _, wrote = client.call_tool("personal_memory_write",
                              { "kind" => "MemorySupportLink",
                                "resource" => F.link_body(L1, R1), "idempotency_key" => "k-l1" })
  C.check("MCP 合法寫入", wrote.is_a?(Hash) ? wrote["status"] : wrote.to_s,
        wrote.is_a?(Hash) && wrote["status"] == "WROTE")

  # 本體不合既有 resource 契約 → 被拒
  bad = F.link_body("urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000b9", R1)
  bad["anchor_resolution"] = "AMBIGUOUS"
  _, refused = client.call_tool("personal_memory_write",
                                { "kind" => "MemorySupportLink",
                                  "resource" => bad, "idempotency_key" => "k-bad" })
  C.check("MCP 寫入被既有治理 evaluator 拒絕",
        refused.is_a?(Hash) ? refused["code"] : refused.to_s,
        refused.is_a?(Hash) && refused["code"] == "PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT")

  # 模型即使硬塞 binding 參數也無效：schema 未宣告，server 一律用自己建構的。
  _, ignored = client.call_tool("personal_memory_read",
                                { "host_session_binding" => { "executor_ref" => "Hermes",
                                                              "executor_session_ref" => "forged" } })
  C.check("模型硬塞的 binding 參數被忽略（server 用自己建構的）",
          ignored.is_a?(Array) ? "以 server binding 正常回應" : ignored.to_s,
          ignored.is_a?(Array))

  _, rows = client.call_tool("personal_memory_read", {})
  C.check("MCP 讀回", rows.is_a?(Array) ? rows.size : rows.to_s, rows.is_a?(Array) && rows.size == 1)

  client.close

  # 沒有 session 記錄（有 native session id，但 hook 沒落地過這一個）：
  # server 建不出 binding，必須 fail closed。
  other = File.join(dir, "no-session")
  FileUtils.mkdir_p(other)
  lone = Support::MCPClient.new(store, host: "Claude Code", cwd: other, state_dir: state_dir,
                                session_id: "claude-session-3b-no-record")
  lone_res = lone.read
  lone.close
  C.check("無 SessionStart 記錄的 native session 一律 fail closed",
          lone_res.is_a?(Hash) ? lone_res["code"] : lone_res.to_s,
          lone_res.is_a?(Hash) && lone_res["code"] == "MCP_NO_SESSION_RECORD")

  # Codex：command SessionStart 先落 state；MCP server 啟動後仍 fail closed，
  # 直到 trusted SessionStart mcp_tool call 帶 Host 注入的 `_meta.threadId`。
  codex_sid = "codex-session-3b"
  codex_hook_out, _codex_hook_err, codex_hook_st = Support.run_session_start(
    host: "Codex", session_id: codex_sid, cwd: proj, state_dir: state_dir
  )
  C.check("Codex command SessionStart 先落可信 session state",
          "exit=#{codex_hook_st.exitstatus}", codex_hook_st.success? && codex_hook_out.include?("hookSpecificOutput"))

  codex_client = Support::MCPClient.new(store, host: "Codex", cwd: proj, state_dir: state_dir,
                                        handshake: false)
  codex_init = codex_client.rpc("initialize", { "protocolVersion" => "2024-11-05",
                                                 "capabilities" => {},
                                                 "clientInfo" => { "name" => "Codex", "version" => "0" } })
  codex_client.notify("notifications/initialized")
  C.check("Codex MCP initialize 握手", codex_init&.dig("result", "serverInfo", "name").to_s,
          codex_init&.dig("result", "serverInfo", "name") == "omos-personal-memory")

  codex_tools = codex_client.rpc("tools/list")
  codex_names = (codex_tools&.dig("result", "tools") || []).map { |t| t["name"] }.sort
  C.check("Codex 額外暴露 SessionStart bind tool", codex_names.inspect,
          codex_names == %w[personal_memory_bind_session personal_memory_closeout personal_memory_read personal_memory_write])

  pre_bind = codex_client.read
  C.check("Codex bind 前 read fail closed", pre_bind.is_a?(Hash) ? pre_bind["code"] : pre_bind.to_s,
          pre_bind.is_a?(Hash) && pre_bind["code"] == "MCP_HOST_BIND_REQUIRED")

  _, missing_meta = codex_client.call_tool("personal_memory_bind_session", {})
  C.check("Codex bind 缺 Host request metadata 明確拒絕",
          missing_meta.is_a?(Hash) ? missing_meta["code"] : missing_meta.to_s,
          missing_meta.is_a?(Hash) && missing_meta["code"] == "MCP_REQUEST_THREAD_ID_MISSING")

  # 這條是整張 EMEM-11b 的核心威脅：**模型不得自報 session 身分**。
  # 9/20 擋下 Codex 的理由就是「server 無從分辨呼叫來源」；現在的隔離靠的是
  # bind tool 的 input_schema 為空——模型連一個可以塞 session id 的欄位都沒有，
  # threadId 只能來自 Host 注入的 `_meta`。
  #
  # 反證：若日後有人為了方便在 schema 加一個 threadId 參數，或讓 call 去讀
  # arguments，這條會轉紅。
  bind_schema = (codex_tools&.dig("result", "tools") || [])
                .find { |t| t["name"] == "personal_memory_bind_session" }
                &.dig("inputSchema")
  C.check("bind tool 不接受任何參數（模型沒有地方可以塞 session id）",
          bind_schema.inspect,
          bind_schema.is_a?(Hash) &&
          (bind_schema["properties"] || {}).empty? &&
          (bind_schema["required"] || []).empty?)

  _, self_reported = codex_client.call_tool("personal_memory_bind_session",
                                            { "threadId" => codex_sid,
                                              "session_id" => codex_sid })
  C.check("模型把 threadId 塞進 arguments 不會被採信（仍要求 Host 注入的 _meta）",
          self_reported.is_a?(Hash) ? self_reported["code"] : self_reported.to_s,
          self_reported.is_a?(Hash) && self_reported["code"] == "MCP_REQUEST_THREAD_ID_MISSING")

  _, forged = codex_client.call_tool("personal_memory_bind_session",
                                     { "threadId" => codex_sid },
                                     meta: { "threadId" => "codex-session-does-not-exist" })
  C.check("arguments 不得覆寫 Host 注入的 _meta.threadId",
          forged.is_a?(Hash) ? forged["code"] : forged.to_s,
          forged.is_a?(Hash) && forged["code"] == "MCP_NO_SESSION_RECORD")

  _, wrong_meta = codex_client.call_tool("personal_memory_bind_session", {},
                                          meta: { "threadId" => "codex-session-does-not-exist" })
  C.check("Codex bind 的 threadId 找不到同 session state 時 fail closed",
          wrong_meta.is_a?(Hash) ? wrong_meta["code"] : wrong_meta.to_s,
          wrong_meta.is_a?(Hash) && wrong_meta["code"] == "MCP_NO_SESSION_RECORD")

  _, bound = codex_client.call_tool("personal_memory_bind_session", {},
                                     meta: { "threadId" => codex_sid })
  C.check("Codex 以 Host 注入 _meta.threadId 建立 binding",
          bound.is_a?(Hash) ? bound["status"] : bound.to_s,
          bound.is_a?(Hash) && bound["status"] == "BOUND" && bound["executor_ref"] == "Codex")

  codex_link = "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000bb"
  _, codex_write = codex_client.call_tool("personal_memory_write",
                                          { "kind" => "MemorySupportLink",
                                            "resource" => F.link_body(codex_link, R1),
                                            "idempotency_key" => "k-codex-write" })
  codex_read = codex_client.read
  codex_client.close
  C.check("Codex bind 後可經同一 Runtime 寫入",
          codex_write.is_a?(Hash) ? codex_write["status"] : codex_write.to_s,
          codex_write.is_a?(Hash) && codex_write["status"] == "WROTE")
  C.check("Codex bind 後可讀回自己寫入的 same-store 資料",
          codex_read.is_a?(Array) ? codex_read.size : codex_read.to_s,
          codex_read.is_a?(Array) && codex_read.any? { |r| r["row_id"] == codex_link })
  C.check("cross-host：Codex 可讀到 Claude Code 先前寫入", "",
          codex_read.is_a?(Array) && codex_read.any? { |r| r["row_id"] == L1 })

  claude_again = Support::MCPClient.new(store, host: "Claude Code", cwd: proj, state_dir: state_dir,
                                        session_id: sid)
  claude_after_codex = claude_again.read
  claude_again.close
  C.check("cross-host：Claude Code 重連後可讀到 Codex 寫入", "",
          claude_after_codex.is_a?(Array) && claude_after_codex.any? { |r| r["row_id"] == codex_link })

  # Runtime 層的保證（不依賴 tool schema）：MCP surface 少了 binding 必須以
  # 契約錯誤碼拒絕。
  require "omos/runtime"
  rt_probe = OMOS::Runtime.open(File.join(dir, "probe.db"))
  runtime_missing = begin
    rt_probe.read_rows(surface: OMOS::Runtime::SURFACES[:mcp])
    nil
  rescue OMOS::Runtime::Rejected => e
    e.code
  end
  C.check("Runtime 層：MCP surface 無 binding 被拒", runtime_missing.to_s,
        runtime_missing == "PMR_MCP_OPERATION_MISSING_HOST_BINDING")

  # Codex 解封後，Runtime 授權集合與 bootstrap delivery 集合重新一致。
  codex_runtime_binding = {
    "executor_ref" => "Codex", "executor_session_ref" => "codex-probe-001",
    "cwd" => proj, "project_ref" => "urn:omos:project:a", "effective_scope" => "SELF_ONLY"
  }
  codex_runtime_problem = OMOS::Contract.binding_problem(codex_runtime_binding)
  rt_probe.store.close
  C.check("Runtime 層：Codex 合法 binding 已重新納入授權集合", codex_runtime_problem.inspect,
          codex_runtime_problem.nil?)

  # --- 以獨立連線直接查資料庫確認（不信 server 的自我回報）---
  db = SQLite3::Database.new(store)
  landed = db.execute("SELECT row_id FROM memory_rows ORDER BY rowid").flatten
  surfaces = db.execute("SELECT DISTINCT surface FROM operation_journal").flatten.sort
  db.close
  # repair-04 P2：事後 conformance oracle 必須與 Runtime 授權閘用**同一組**
  # host set。先前 oracle 吃 known_hosts，於是把這份 journal 的 MCP binding
  # 換成 blocked host 之後仍被判合法——真正的 Runtime 早就擋住了，但「證據」
  # 與「授權」對不起來，事後看 journal 會得到錯的結論。
  mcp_log = OMOS::Runtime.open(store)
  real_log = mcp_log.operation_log
  mcp_log.store.close
  C.check("真實 MCP journal 通過事後 oracle", OMOS::Contract.runtime_log_problem(real_log).inspect,
          OMOS::Contract.runtime_log_problem(real_log).nil?)

  codex_log = JSON.parse(JSON.generate(real_log))
  rewritten = 0
  codex_log.fetch("operations").each do |op|
    next unless op["host_session_binding"].is_a?(Hash)

    op["host_session_binding"]["executor_ref"] = "Codex"
    rewritten += 1
  end
  codex_log_problem = OMOS::Contract.runtime_log_problem(codex_log)
  C.check("Codex journal 已被事後 oracle 接受（與 Runtime 授權同一組 host set）",
          "改寫 #{rewritten} 筆 binding → #{codex_log_problem.inspect}",
          rewritten.positive? && codex_log_problem.nil?)

  C.check("獨立連線查資料表：Claude + Codex 兩筆合法寫入都落地", landed.inspect,
          landed == [L1, codex_link])
  rejected_id = "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000b9"
  C.check("被拒絕的治理負例完全沒落地", landed.inspect, !landed.include?(rejected_id))
  C.check("journal 記錄的 surface 為 LOCAL_STDIO_MCP", surfaces.inspect, surfaces == ["LOCAL_STDIO_MCP"])

  # --- CLI 與 MCP 共用同一個 store、同一套治理 ---
  cli = File.expand_path("../exe/omos-personal-memory", __dir__)
  out, _err, status = Open3.capture3(cli, "read", "--store", store)
  C.check("CLI 讀得到 MCP 寫入的那一列", out.strip.split("\t").last.to_s,
        status.success? && out.include?(L1))

  # --- Host 設定探索：假 HOME，不碰使用者正式設定 ---
  fake_home = File.join(dir, "home")
  FileUtils.mkdir_p(File.join(fake_home, ".codex"))
  FileUtils.mkdir_p(File.join(fake_home, ".claude"))
  # Host 原生形狀：hook 是 event → matcher group → handler[]，handler 無 id。
  File.write(File.join(fake_home, ".codex/config.toml"), <<~TOML)
    [mcp_servers.foreign-tool]
    command = "foreign"

    [[hooks.SessionStart]]

    [[hooks.SessionStart.hooks]]
    type = "command"
    command = "foreign-boot"
  TOML
  File.write(File.join(fake_home, ".claude.json"),
             JSON.generate({ "mcpServers" => { "foreign-tool" => { "command" => "foreign" } } }))
  File.write(File.join(fake_home, ".claude/settings.json"),
             JSON.generate({ "hooks" => { "SessionStart" =>
                             [{ "hooks" => [{ "type" => "command", "command" => "foreign-boot" }] }] } }))

  codex = OMOS::HostConfig.new("Codex", home: fake_home)
  snap = codex.snapshot
  C.check("Codex 設定探索讀到實際 TOML 的 mcp_servers", snap["mcp_entries"].keys.inspect,
        snap["mcp_entries"].keys == ["foreign-tool"])
  C.check("Codex 設定探索讀到三層 [[hooks.SessionStart.hooks]]",
        snap["session_start_hooks"].map { |h| h["command_ref"] }.inspect,
        snap["session_start_hooks"].map { |h| h["command_ref"] } == ["foreign-boot"])
  C.check("未安裝時既有 evaluator 回報 MCP 缺漏", codex.own_registration_problem.to_s,
        codex.own_registration_problem == "HBV1_EFFECTIVE_MCP_MISSING_OR_DRIFTED")

  claude = OMOS::HostConfig.new("Claude Code", home: fake_home)
  csnap = claude.snapshot
  C.check("Claude Code 的 MCP 與 hook 在不同檔案，兩者都讀到",
        "#{csnap["mcp_entries"].keys.inspect} / #{csnap["session_start_hooks"].map { |h| h["command_ref"] }.inspect}",
        csnap["mcp_entries"].keys == ["foreign-tool"] &&
        csnap["session_start_hooks"].map { |h| h["command_ref"] } == ["foreign-boot"])

  # 設定壞掉要明確失敗，不得 silent fallback 成「沒有註冊」
  File.write(File.join(fake_home, ".claude.json"), "{ this is not json")
  broken = begin
    OMOS::HostConfig.new("Claude Code", home: fake_home).snapshot
    nil
  rescue OMOS::HostConfig::DiscoveryError => e
    e.message
  end
  C.check("設定檔壞掉會明確失敗", broken.to_s[0, 40], !broken.nil?)

  # --- 回歸檢查：入口不得依賴使用者的 PATH ---
  #
  # 實測過的失敗模式：`#!/usr/bin/env ruby` 在乾淨 PATH 下會找到 macOS 系統
  # Ruby 2.6，載入為 3.4 編譯的原生 gem 後 SIGILL（exit 132）且毫無輸出；
  # 而 Ruby 端的版本守衛救不了，因為含新語法的檔案在 2.6 會先 parse 失敗，
  # 守衛沒有機會執行。Host 啟動 MCP server 用的就是這樣一條命令，所以
  # 版本解析必須發生在 Ruby 之外。
  clean = { "PATH" => "/usr/bin:/bin", "HOME" => ENV["HOME"] }
  cli_exe = File.expand_path("../exe/omos-personal-memory", __dir__)
  out_clean, _e, st_clean = Open3.capture3(clean, cli_exe, "--help", unsetenv_others: true)
  C.check("CLI 入口在乾淨 PATH 下可用", "exit=#{st_clean.exitstatus}",
        st_clean.success? && out_clean.include?("用法"))

  mcp_exe = File.expand_path("../exe/omos-personal-memory-mcp", __dir__)
  handshake = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                              "params" => { "protocolVersion" => "2024-11-05", "capabilities" => {},
                                            "clientInfo" => { "name" => "t", "version" => "0" } } })
  mcp_out, = Open3.capture3(clean.merge("OMOS_PERSONAL_MEMORY_STORE" => File.join(dir, "clean.db")),
                            mcp_exe, stdin_data: handshake + "\n", unsetenv_others: true)
  C.check("MCP 入口在乾淨 PATH 下完成握手",
        (JSON.parse(mcp_out.lines.first.to_s)["result"] || {}).dig("serverInfo", "name").to_s,
        mcp_out.lines.first.to_s.include?("omos-personal-memory"))

  bad_out, bad_err, bad_st = Open3.capture3(clean.merge("OMOS_RUBY" => "/usr/bin/ruby"),
                                            cli_exe, "--help", unsetenv_others: true)
  # Slice B repair-01：呼叫端的 bundler 環境不得影響 ABI probe。
  #
  # sanitization 原本放在 wrapper source pinned-ruby.sh **之後**，但 ABI probe
  # 就在那支腳本裡執行——於是 caller 的 RUBYOPT=-rbundler/setup 與
  # BUNDLE_GEMFILE 會讓 probe 在別人的 bundler 環境下啟動，產生**假的 ABI
  # 不符**。修復前實測輸出正是「找不到 ABI 相容的 Ruby」。
  hostile_dir = File.join(dir, "hostile-bundler")
  FileUtils.mkdir_p(hostile_dir)
  File.write(File.join(hostile_dir, "Gemfile"),
             "source \"https://rubygems.org\"\ngem \"this_gem_does_not_exist_anywhere\"\n")
  hostile_env = { "RUBYOPT" => "-rbundler/setup",
                  "BUNDLE_GEMFILE" => File.join(hostile_dir, "Gemfile") }
  h_out, h_err, h_st = Open3.capture3(hostile_env, cli_exe, "--help")
  C.check("繼承的敵意 RUBYOPT／BUNDLE_GEMFILE 不影響 ABI probe 與執行",
        h_st.success? ? "exit=0" : (h_err + h_out).lines.first.to_s.strip[0, 50],
        h_st.success? && h_out.include?("用法"))

  # Slice B：判準由版本字串改為 ABI 相容，訊息也必須說明**實際**的不符原因，
  # 並帶出 artifact 需要的 ABI——只說「版本不對」對使用者沒有幫助。
  C.check("指定不合格的 OMOS_RUBY 會當場失敗，不靜默改用別的",
        "exit=#{bad_st.exitstatus}",
        !bad_st.success? && (bad_err + bad_out).include?("ABI 與本 artifact 不符") &&
        (bad_err + bad_out).include?("ABI #{RbConfig::CONFIG["ruby_version"]}"))

  # --- 3b 邊界：唯讀，不得有任何 Host 設定寫入路徑 ---
  src = File.read(File.expand_path("../lib/omos/host_config.rb", __dir__))
  writes = src.scan(/File\.(write|open)\(|FileUtils\.(mv|cp|rm)/).flatten.compact
  C.check("host_config 無任何寫入呼叫（安裝屬 3c）", writes.inspect, writes.empty?)
end

C.report!
