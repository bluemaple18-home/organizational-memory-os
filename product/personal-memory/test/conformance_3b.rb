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
    host: "Codex", native_session_id: "codex-session-3b", cwd: File.join(dir, "projA"),
    project_ref: "urn:omos:project:a", runtime_scope_mode: "EMPLOYEE_PRIVATE"
  )
  C.check("SessionStart 產出 binding", binding["effective_scope"], binding["effective_scope"] == "SELF_ONLY")

  widened = begin
    OMOS::SessionStart.produce(host: "Codex", native_session_id: "s", cwd: dir,
                               project_ref: "p", runtime_scope_mode: "EMPLOYEE_PRIVATE",
                               project_visibility_scope: "WORK_CONTEXT_PARTICIPANTS")
    nil
  rescue OMOS::SessionStart::Refused => e
    e.code
  end
  C.check("專案不得擴權", widened, widened == "HBV1_PROJECT_SCOPE_WIDENS_BASELINE")

  # --- 真的跑 SessionStart hook（真 Host 的 stdin 形狀），再 spawn MCP server ---
  #
  # repair-02：MCP server 的 binding 需要獨立得知 native session id，目前只有
  # Claude Code 有官方管道（PROCESS_ENV）；Codex 一律 fail closed
  # （MCP_NATIVE_SESSION_ID_UNAVAILABLE，見本檔案後段獨立驗證）。這裡的
  # 「MCP 真的能寫能讀」happy path 因此改用 Claude Code。
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

  # repair-02 的產品裁決：Codex 目前沒有官方管道讓 MCP server 獨立得知
  # native session id，因此一律 fail closed，不退回 cwd 或任何代理鍵猜測。
  codex_client = Support::MCPClient.new(store, host: "Codex", cwd: proj, state_dir: state_dir)
  codex_res = codex_client.read
  codex_client.close
  C.check("Codex 目前無可信 native session 管道，MCP 一律 fail closed",
          codex_res.is_a?(Hash) ? codex_res["code"] : codex_res.to_s,
          codex_res.is_a?(Hash) && codex_res["code"] == "MCP_NATIVE_SESSION_ID_UNAVAILABLE")

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
  rt_probe.store.close
  C.check("Runtime 層：MCP surface 無 binding 被拒", runtime_missing.to_s,
        runtime_missing == "PMR_MCP_OPERATION_MISSING_HOST_BINDING")

  # --- 以獨立連線直接查資料庫確認（不信 server 的自我回報）---
  db = SQLite3::Database.new(store)
  landed = db.execute("SELECT row_id FROM memory_rows ORDER BY rowid").flatten
  surfaces = db.execute("SELECT DISTINCT surface FROM operation_journal").flatten.sort
  db.close
  C.check("獨立連線查資料表：合法那筆真的落地", landed.inspect, landed == [L1])
  C.check("被拒絕的那筆完全沒落地", landed.size, landed.size == 1)
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
  C.check("指定不合格的 OMOS_RUBY 會當場失敗，不靜默改用別的",
        "exit=#{bad_st.exitstatus}",
        !bad_st.success? && (bad_err + bad_out).include?("不是"))

  # --- 3b 邊界：唯讀，不得有任何 Host 設定寫入路徑 ---
  src = File.read(File.expand_path("../lib/omos/host_config.rb", __dir__))
  writes = src.scan(/File\.(write|open)\(|FileUtils\.(mv|cp|rm)/).flatten.compact
  C.check("host_config 無任何寫入呼叫（安裝屬 3c）", writes.inspect, writes.empty?)
end

C.report!
