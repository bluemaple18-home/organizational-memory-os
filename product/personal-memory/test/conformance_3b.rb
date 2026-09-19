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

RESULTS = []
def check(name, detail, ok) = RESULTS << [ok ? "PASS" : "FAIL", name, detail.to_s]

EXE = File.expand_path("../exe/omos-personal-memory-mcp", __dir__)
EMP = "urn:omos:employee:emp-001"
L1 = "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000b1"
R1 = "urn:omos:personal-memory:record:01900000-0000-7000-8000-000000000001"

def link_body(link_id, target)
  { "link_id" => link_id, "tenant_id" => "t-acme", "employee_owner_ref" => EMP,
    "target_ref" => target, "evidence_ref" => "urn:omos:evidence:ev-001",
    "source_anchor_ref" => "urn:omos:source-anchor:sa-001",
    "source_anchor_profile" => "MARKDOWN_TEXT_V1", "relation" => "SUPPORTS",
    "anchor_resolution" => "EXACT_MATCH",
    "provenance" => { "created_by" => EMP, "created_at" => "2026-09-20T09:00:00Z" } }
end

# --- 真的 MCP stdio 用戶端 -------------------------------------------------

class StdioClient
  def initialize(exe, store)
    @stdin, @stdout, @stderr, @wait = Open3.popen3({ "OMOS_PERSONAL_MEMORY_STORE" => store }, exe)
    @id = 0
  end

  def request(method, params = nil)
    @id += 1
    payload = { "jsonrpc" => "2.0", "id" => @id, "method" => method }
    payload["params"] = params if params
    @stdin.puts(JSON.generate(payload))
    @stdin.flush
    line = @stdout.gets
    line && JSON.parse(line)
  end

  def notify(method, params = {})
    @stdin.puts(JSON.generate({ "jsonrpc" => "2.0", "method" => method, "params" => params }))
    @stdin.flush
  end

  def call_tool(name, args)
    res = request("tools/call", { "name" => name, "arguments" => args })
    text = res&.dig("result", "content", 0, "text")
    [res, text && (JSON.parse(text) rescue text)]
  end

  def close
    @stdin.close
    @wait.value
  rescue IOError
    nil
  end

  def stderr_text
    @stderr.read_nonblock(8192)
  rescue StandardError
    ""
  end
end

Dir.mktmpdir("omos-3b") do |dir|
  store = File.join(dir, "personal.db")

  # --- SessionStart 產出 binding（推導委派切片 2 evaluator）---
  binding = OMOS::SessionStart.produce(
    host: "Codex", native_session_id: "codex-session-3b", cwd: File.join(dir, "projA"),
    project_ref: "urn:omos:project:a", runtime_scope_mode: "EMPLOYEE_PRIVATE"
  )
  check("SessionStart 產出 binding", binding["effective_scope"], binding["effective_scope"] == "SELF_ONLY")

  widened = begin
    OMOS::SessionStart.produce(host: "Codex", native_session_id: "s", cwd: dir,
                               project_ref: "p", runtime_scope_mode: "EMPLOYEE_PRIVATE",
                               project_visibility_scope: "WORK_CONTEXT_PARTICIPANTS")
    nil
  rescue OMOS::SessionStart::Refused => e
    e.code
  end
  check("專案不得擴權", widened, widened == "HBV1_PROJECT_SCOPE_WIDENS_BASELINE")

  # --- 真的 spawn MCP server，走真的 stdio JSON-RPC ---
  client = StdioClient.new(EXE, store)
  init = client.request("initialize", { "protocolVersion" => "2024-11-05",
                                        "capabilities" => {},
                                        "clientInfo" => { "name" => "conformance", "version" => "0" } })
  check("MCP initialize 握手", init&.dig("result", "serverInfo", "name").to_s,
        init&.dig("result", "serverInfo", "name") == "omos-personal-memory")
  client.notify("notifications/initialized")

  tools = client.request("tools/list")
  names = (tools&.dig("result", "tools") || []).map { |t| t["name"] }.sort
  check("tools/list 暴露三個 tool", names.inspect,
        names == %w[personal_memory_closeout personal_memory_read personal_memory_write])

  # 缺 binding 必須明確失敗。tool schema 會先擋下來（更早的拒絕，合格），
  # 但真正的保證在 Runtime，所以另外直接驗 Runtime 那一層。
  res_missing, missing = client.call_tool("personal_memory_write",
                                          { "kind" => "MemorySupportLink", "resource" => link_body(L1, R1),
                                            "idempotency_key" => "k-l1" })
  protocol_refused = !res_missing.nil? &&
                     (!res_missing["error"].nil? || missing.to_s.include?("Missing required arguments"))
  check("MCP 呼叫缺 host_session_binding 被 tool schema 擋下",
        missing.to_s[0, 50], protocol_refused)

  # 帶 binding 的合法寫入
  _, wrote = client.call_tool("personal_memory_write",
                              { "host_session_binding" => binding, "kind" => "MemorySupportLink",
                                "resource" => link_body(L1, R1), "idempotency_key" => "k-l1" })
  check("MCP 合法寫入", wrote.is_a?(Hash) ? wrote["status"] : wrote.to_s,
        wrote.is_a?(Hash) && wrote["status"] == "WROTE")

  # 本體不合既有 resource 契約 → 被拒
  bad = link_body("urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000b9", R1)
  bad["anchor_resolution"] = "AMBIGUOUS"
  _, refused = client.call_tool("personal_memory_write",
                                { "host_session_binding" => binding, "kind" => "MemorySupportLink",
                                  "resource" => bad, "idempotency_key" => "k-bad" })
  check("MCP 寫入被既有治理 evaluator 拒絕",
        refused.is_a?(Hash) ? refused["code"] : refused.to_s,
        refused.is_a?(Hash) && refused["code"] == "PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT")

  # 偽造 binding（塞第二套身分欄位）
  shadow = binding.merge("host" => "Codex")
  _, shadowed = client.call_tool("personal_memory_read", { "host_session_binding" => shadow })
  check("MCP 帶第二套身分欄位的 binding 被拒",
        shadowed.is_a?(Hash) ? shadowed["code"] : shadowed.to_s,
        shadowed.is_a?(Hash) && shadowed["code"] == "PMR_HOST_BINDING_SHADOW_IDENTITY_FIELD")

  _, rows = client.call_tool("personal_memory_read", { "host_session_binding" => binding })
  check("MCP 讀回", rows.is_a?(Array) ? rows.size : rows.to_s, rows.is_a?(Array) && rows.size == 1)

  client.close

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
  check("Runtime 層：MCP surface 無 binding 被拒", runtime_missing.to_s,
        runtime_missing == "PMR_MCP_OPERATION_MISSING_HOST_BINDING")

  # --- 以獨立連線直接查資料庫確認（不信 server 的自我回報）---
  db = SQLite3::Database.new(store)
  landed = db.execute("SELECT row_id FROM memory_rows ORDER BY rowid").flatten
  surfaces = db.execute("SELECT DISTINCT surface FROM operation_journal").flatten.sort
  db.close
  check("獨立連線查資料表：合法那筆真的落地", landed.inspect, landed == [L1])
  check("被拒絕的那筆完全沒落地", landed.size, landed.size == 1)
  check("journal 記錄的 surface 為 LOCAL_STDIO_MCP", surfaces.inspect, surfaces == ["LOCAL_STDIO_MCP"])

  # --- CLI 與 MCP 共用同一個 store、同一套治理 ---
  cli = File.expand_path("../exe/omos-personal-memory", __dir__)
  out, _err, status = Open3.capture3(cli, "read", "--store", store)
  check("CLI 讀得到 MCP 寫入的那一列", out.strip.split("\t").last.to_s,
        status.success? && out.include?(L1))

  # --- Host 設定探索：假 HOME，不碰使用者正式設定 ---
  fake_home = File.join(dir, "home")
  FileUtils.mkdir_p(File.join(fake_home, ".codex"))
  FileUtils.mkdir_p(File.join(fake_home, ".claude"))
  File.write(File.join(fake_home, ".codex/config.toml"), <<~TOML)
    [mcp_servers.foreign-tool]
    command = "foreign"
    [[hooks.SessionStart]]
    id = "foreign.bootstrap"
    command = "foreign-boot"
  TOML
  File.write(File.join(fake_home, ".claude.json"),
             JSON.generate({ "mcpServers" => { "foreign-tool" => { "command" => "foreign" } } }))
  File.write(File.join(fake_home, ".claude/settings.json"),
             JSON.generate({ "hooks" => { "SessionStart" => [{ "id" => "foreign.bootstrap",
                                                               "command" => "foreign-boot" }] } }))

  codex = OMOS::HostConfig.new("Codex", home: fake_home)
  snap = codex.snapshot
  check("Codex 設定探索讀到實際 TOML 的 mcp_servers", snap["mcp_entries"].keys.inspect,
        snap["mcp_entries"].keys == ["foreign-tool"])
  check("Codex 設定探索讀到 [[hooks.SessionStart]]",
        snap["session_start_hooks"].map { |h| h["id"] }.inspect,
        snap["session_start_hooks"].map { |h| h["id"] } == ["foreign.bootstrap"])
  check("未安裝時既有 evaluator 回報 MCP 缺漏", codex.own_registration_problem.to_s,
        codex.own_registration_problem == "HBV1_EFFECTIVE_MCP_MISSING_OR_DRIFTED")

  claude = OMOS::HostConfig.new("Claude Code", home: fake_home)
  csnap = claude.snapshot
  check("Claude Code 的 MCP 與 hook 在不同檔案，兩者都讀到",
        "#{csnap["mcp_entries"].keys.inspect} / #{csnap["session_start_hooks"].map { |h| h["id"] }.inspect}",
        csnap["mcp_entries"].keys == ["foreign-tool"] &&
        csnap["session_start_hooks"].map { |h| h["id"] } == ["foreign.bootstrap"])

  # 設定壞掉要明確失敗，不得 silent fallback 成「沒有註冊」
  File.write(File.join(fake_home, ".claude.json"), "{ this is not json")
  broken = begin
    OMOS::HostConfig.new("Claude Code", home: fake_home).snapshot
    nil
  rescue OMOS::HostConfig::DiscoveryError => e
    e.message
  end
  check("設定檔壞掉會明確失敗", broken.to_s[0, 40], !broken.nil?)

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
  check("CLI 入口在乾淨 PATH 下可用", "exit=#{st_clean.exitstatus}",
        st_clean.success? && out_clean.include?("用法"))

  mcp_exe = File.expand_path("../exe/omos-personal-memory-mcp", __dir__)
  handshake = JSON.generate({ "jsonrpc" => "2.0", "id" => 1, "method" => "initialize",
                              "params" => { "protocolVersion" => "2024-11-05", "capabilities" => {},
                                            "clientInfo" => { "name" => "t", "version" => "0" } } })
  mcp_out, = Open3.capture3(clean.merge("OMOS_PERSONAL_MEMORY_STORE" => File.join(dir, "clean.db")),
                            mcp_exe, stdin_data: handshake + "\n", unsetenv_others: true)
  check("MCP 入口在乾淨 PATH 下完成握手",
        (JSON.parse(mcp_out.lines.first.to_s)["result"] || {}).dig("serverInfo", "name").to_s,
        mcp_out.lines.first.to_s.include?("omos-personal-memory"))

  bad_out, bad_err, bad_st = Open3.capture3(clean.merge("OMOS_RUBY" => "/usr/bin/ruby"),
                                            cli_exe, "--help", unsetenv_others: true)
  check("指定不合格的 OMOS_RUBY 會當場失敗，不靜默改用別的",
        "exit=#{bad_st.exitstatus}",
        !bad_st.success? && (bad_err + bad_out).include?("不是"))

  # --- 3b 邊界：唯讀，不得有任何 Host 設定寫入路徑 ---
  src = File.read(File.expand_path("../lib/omos/host_config.rb", __dir__))
  writes = src.scan(/File\.(write|open)\(|FileUtils\.(mv|cp|rm)/).flatten.compact
  check("host_config 無任何寫入呼叫（安裝屬 3c）", writes.inspect, writes.empty?)
end

width = RESULTS.map { |_, n, _| n.length }.max
RESULTS.each { |st, n, d| puts format("%-4s %-#{width}s  %s", st, n, d) }
failed = RESULTS.count { |st, _, _| st == "FAIL" }
puts "\n3b conformance：#{RESULTS.size - failed}/#{RESULTS.size} PASS"
exit(failed.zero? ? 0 : 1)
