# frozen_string_literal: true
#
# 切片 3c conformance：主卡三組驗收，全部對實物。
#
#   A 安裝與復原      在隔離 HOME 實際 install / reinstall / upgrade / uninstall；
#                     保留非本產品設定與個人資料；中途失敗必須完全復原。
#   B Doctor 與失敗診斷 讀實際設定、實際啟動目標、實際開 store；
#                     「設定存在」「程序能啟動」「Store 能用」是三種不同結果。
#   C 跨 Host 與跨專案  真的同時跑兩個 MCP 進程對同一個 store 往返；
#                     切換專案不得擴權；retry／重啟不得產生第二筆。
#
# 全程不碰使用者的正式設定——所有操作都在 Dir.mktmpdir 的假 HOME 內。

require "json"
require "tmpdir"
require "fileutils"
require "open3"
require "sqlite3"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "omos/version_guard"
OMOS::VersionGuard.assert!
require "omos/installer"
require "omos/doctor"
require "omos/session_start"

RESULTS = []
def check(group, name, detail, ok) = RESULTS << [ok ? "PASS" : "FAIL", group, name, detail.to_s]

PRODUCT_ROOT = File.expand_path("..", __dir__)
MCP_EXE = File.join(PRODUCT_ROOT, "exe/omos-personal-memory-mcp")
EMP = "urn:omos:employee:emp-001"

def link_body(link_id, target)
  { "link_id" => link_id, "tenant_id" => "t-acme", "employee_owner_ref" => EMP,
    "target_ref" => target, "evidence_ref" => "urn:omos:evidence:ev-001",
    "source_anchor_ref" => "urn:omos:source-anchor:sa-001",
    "source_anchor_profile" => "MARKDOWN_TEXT_V1", "relation" => "SUPPORTS",
    "anchor_resolution" => "EXACT_MATCH",
    "provenance" => { "created_by" => EMP, "created_at" => "2026-09-20T09:00:00Z" } }
end

def closeout_payload(period, item, status, attempt)
  { "review_period_id" => period, "scheduled_review_period_start" => "2026-09-18",
    "scheduled_anchor_at" => "2026-09-18T15:00:00Z", "actual_closeout_at" => "2026-09-18T17:30:00Z",
    "attempt_kind" => attempt, "final_status" => status, "catch_up_deadline_passed" => true,
    "selected_item_refs" => [item],
    "item_dispositions" => { item => { "category" => "MATERIALLY_CHANGED",
                                       "promotion_ref" => "urn:omos:promotion:pr-001",
                                       "promotion_idempotency_key" => "pk-001" } } }
end

# 一個真的 MCP stdio 用戶端（每個實例 = 一個獨立子進程）
class Host
  attr_reader :binding

  def initialize(store, binding)
    @binding = binding
    @in, @out, @err, @wait = Open3.popen3({ "OMOS_PERSONAL_MEMORY_STORE" => store }, MCP_EXE)
    @id = 0
    rpc("initialize", { "protocolVersion" => "2024-11-05", "capabilities" => {},
                        "clientInfo" => { "name" => binding["executor_ref"], "version" => "0" } })
    @in.puts(JSON.generate({ "jsonrpc" => "2.0", "method" => "notifications/initialized", "params" => {} }))
    @in.flush
  end

  def rpc(method, params)
    @id += 1
    @in.puts(JSON.generate({ "jsonrpc" => "2.0", "id" => @id, "method" => method, "params" => params }))
    @in.flush
    JSON.parse(@out.gets.to_s)
  end

  def call(tool, args)
    res = rpc("tools/call", { "name" => tool, "arguments" => args.merge("host_session_binding" => @binding) })
    text = res.dig("result", "content", 0, "text")
    text ? (JSON.parse(text) rescue text) : res
  end

  def write(kind, resource, key, supersedes = nil)
    args = { "kind" => kind, "resource" => resource, "idempotency_key" => key }
    args["supersedes_ref"] = supersedes if supersedes
    call("personal_memory_write", args)
  end

  def read = call("personal_memory_read", {})
  def closeout(payload) = call("personal_memory_closeout", { "closeout" => payload })

  def close
    @in.close
    @wait.value
  rescue IOError
    nil
  end
end

def seed_home(home)
  FileUtils.mkdir_p(File.join(home, ".codex"))
  FileUtils.mkdir_p(File.join(home, ".claude"))
  File.write(File.join(home, ".codex/config.toml"),
             "# 使用者自己的註解\nmodel = \"gpt-5\"\n\n[mcp_servers.foreign]\ncommand = \"f\"\n")
  File.write(File.join(home, ".claude.json"),
             "#{JSON.pretty_generate({ 'mcpServers' => { 'relay' => { 'command' => 'r' } }, 'userState' => { 'k' => 1 } })}\n")
  File.write(File.join(home, ".claude/settings.json"),
             "#{JSON.pretty_generate({ 'theme' => 'dark' })}\n")
end

def read_all(home)
  { codex: File.read(File.join(home, ".codex/config.toml")),
    claude: File.read(File.join(home, ".claude.json")),
    settings: File.read(File.join(home, ".claude/settings.json")) }
end

# ===========================================================================
# A 安裝與復原
# ===========================================================================
Dir.mktmpdir("omos-3c-a") do |dir|
  home = File.join(dir, "home")
  seed_home(home)
  store = File.join(dir, "p.db")
  before = read_all(home)
  inst = OMOS::Installer.new(home: home, store_path: store)

  inst.install
  check("A", "install 後兩個 Host 都判定未漂移", "",
        OMOS::HostConfig.hosts.all? do |h|
          OMOS::HostConfig.new(h, home: home, command_map: inst.command_map).own_registration_problem.nil?
        end)
  check("A", "install 保留使用者註解與他人 mcp", "",
        File.read(File.join(home, ".codex/config.toml")).include?("使用者自己的註解") &&
        File.read(File.join(home, ".codex/config.toml")).include?("[mcp_servers.foreign]"))
  check("A", "install 保留 Claude 使用者狀態", "",
        JSON.parse(File.read(File.join(home, ".claude.json")))["userState"] == { "k" => 1 })

  # 個人資料：安裝後寫一筆，之後所有操作都不得動到它
  rt = OMOS::Runtime.open(store)
  link = "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000a1"
  rec = "urn:omos:personal-memory:record:01900000-0000-7000-8000-0000000000a2"
  rt.write_row(kind: "MemorySupportLink", resource: link_body(link, rec), idempotency_key: "k-a1",
               surface: OMOS::Runtime::SURFACES[:cli])
  rt.store.close

  inst.install # reinstall（idempotent）
  inst.upgrade
  check("A", "reinstall / upgrade 後仍未漂移", "",
        OMOS::HostConfig.hosts.all? do |h|
          OMOS::HostConfig.new(h, home: home, command_map: inst.command_map).own_registration_problem.nil?
        end)
  db = SQLite3::Database.new(store)
  survived = db.get_first_value("SELECT COUNT(*) FROM memory_rows")
  db.close
  check("A", "reinstall / upgrade 不動個人資料", "rows=#{survived}", survived == 1)

  inst.uninstall
  after = read_all(home)
  check("A", "uninstall 後 Codex 設定位元組完全相同", "#{before[:codex].bytesize}→#{after[:codex].bytesize}",
        after[:codex] == before[:codex])
  check("A", "uninstall 後他人 Claude mcp 保留", "",
        JSON.parse(after[:claude])["mcpServers"].keys == ["relay"])
  check("A", "uninstall 預設保留 Personal Store", "", File.exist?(store))

  # 中途失敗必須完全復原
  pre_fail = read_all(home)
  code = begin
    inst.install(fail_after: "Codex")
    nil
  rescue OMOS::Installer::Failed => e
    e.code
  end
  post_fail = read_all(home)
  check("A", "注入的中途失敗被回報", code.to_s, code == "INSTALL_INJECTED_FAILURE")
  check("A", "中途失敗後所有設定完全復原", "", post_fail == pre_fail)
  check("A", "中途失敗後沒有留下 receipt", "", !File.exist?(inst.receipt_path))
end

# ===========================================================================
# B Doctor 與失敗診斷
# ===========================================================================
Dir.mktmpdir("omos-3c-b") do |dir|
  home = File.join(dir, "home")
  seed_home(home)
  proj = File.join(dir, "proj")
  FileUtils.mkdir_p(proj)
  store = File.join(dir, "p.db")
  inst = OMOS::Installer.new(home: home, store_path: store)

  # 未安裝：三種結果必須分得開
  pre = OMOS::Doctor.new(home: home, store_path: store, cwd: proj).run.to_h { |r| [r.id, r.status] }
  check("B", "未安裝時：程序叫得起來（PROCESS_OK）", pre["mcp_handshake"], pre["mcp_handshake"] == "OK")
  check("B", "未安裝時：設定不存在（CONFIG 缺）", pre["codex_mcp_visible"], pre["codex_mcp_visible"] == "FAIL")
  check("B", "未安裝時：store 不能用（STORE 缺）", pre["store_exists"], pre["store_exists"] == "FAIL")
  check("B", "三者確實獨立（程序 OK 但另兩者 FAIL）", "",
        pre["mcp_handshake"] == "OK" && pre["codex_mcp_visible"] == "FAIL" && pre["store_exists"] == "FAIL")

  inst.install
  post = OMOS::Doctor.new(home: home, store_path: store, cwd: proj).run
  post_fail = post.select { |r| r.status == "FAIL" }
  post_warn = post.select { |r| r.status == "WARN" }
  check("B", "安裝後無任何 FAIL",
        "#{post.count(&:ok?)} OK / #{post_warn.size} WARN / #{post_fail.size} FAIL", post_fail.empty?)
  check("B", "唯一的 WARN 是 Codex 遮蔽無法觀測（照實回報，不假裝 OK）",
        post_warn.map(&:id).inspect, post_warn.map(&:id) == ["codex_no_shadow"])

  # 被同名專案設定遮蔽 → 必須明確失敗
  File.write(File.join(proj, ".mcp.json"),
             JSON.generate({ "mcpServers" => { "omos.personal-memory" => { "command" => "hijack" } } }))
  shadowed = OMOS::Doctor.new(home: home, store_path: store, cwd: proj).run
                         .find { |r| r.id == "claude_code_no_shadow" }
  check("B", "專案 .mcp.json 同名遮蔽被偵測", shadowed.detail[0, 30], shadowed.status == "FAIL")

  # 即使 payload 與本產品完全相同也必須報（看的是 id 與優先序，不是內容）
  File.write(File.join(proj, ".mcp.json"),
             JSON.generate({ "mcpServers" => { "omos.personal-memory" =>
                             { "command" => inst.mcp_command, "transport" => "STDIO" } } }))
  same_payload = OMOS::Doctor.new(home: home, store_path: store, cwd: proj).run
                             .find { |r| r.id == "claude_code_no_shadow" }
  check("B", "payload 完全相同的遮蔽仍被偵測", same_payload.detail[0, 30], same_payload.status == "FAIL")
  FileUtils.rm_f(File.join(proj, ".mcp.json"))

  # hook 被移除 → 必須明確失敗（而不是靠 caller 自報健康）
  settings = JSON.parse(File.read(File.join(home, ".claude/settings.json")))
  settings["hooks"]["SessionStart"] = []
  File.write(File.join(home, ".claude/settings.json"), "#{JSON.pretty_generate(settings)}\n")
  hook_gone = OMOS::Doctor.new(home: home, store_path: store, cwd: proj).run
                          .find { |r| r.id == "claude_code_session_start_hook_active" }
  check("B", "SessionStart hook 被移除會明確失敗", hook_gone.detail[0, 30], hook_gone.status == "FAIL")

  # executable 不存在 → 必須明確失敗
  missing = OMOS::Doctor.new(home: home, store_path: store, cwd: proj,
                             product_root: File.join(dir, "nowhere")).run
                        .find { |r| r.id == "mcp_executable" }
  check("B", "MCP executable 不存在會明確失敗", missing.detail[0, 30], missing.status == "FAIL")

  # SQLite 版本比較：低於修復版本必須判為不安全
  s = OMOS::Store.new(store)
  check("B", "SQLite 版本比較：3.51.0 判為不安全", "",
        !s.version_at_least?("3.51.0", OMOS::Store::WAL_RESET_FIX))
  check("B", "SQLite 版本比較：3.51.3 判為安全", "",
        s.version_at_least?("3.51.3", OMOS::Store::WAL_RESET_FIX))
end

# ===========================================================================
# C 跨 Host 與跨專案
# ===========================================================================
Dir.mktmpdir("omos-3c-c") do |dir|
  home = File.join(dir, "home")
  seed_home(home)
  store = File.join(dir, "shared.db")
  OMOS::Installer.new(home: home, store_path: store).install

  proj_a = File.join(dir, "projA")
  proj_b = File.join(dir, "projB")
  FileUtils.mkdir_p(proj_a)
  FileUtils.mkdir_p(proj_b)

  codex_binding = OMOS::SessionStart.produce(
    host: "Codex", native_session_id: "codex-1", cwd: proj_a,
    project_ref: "urn:omos:project:a", runtime_scope_mode: "EMPLOYEE_PRIVATE"
  )
  claude_binding = OMOS::SessionStart.produce(
    host: "Claude Code", native_session_id: "claude-1", cwd: proj_a,
    project_ref: "urn:omos:project:a", runtime_scope_mode: "EMPLOYEE_PRIVATE"
  )

  codex = Host.new(store, codex_binding)
  claude = Host.new(store, claude_binding)

  l1 = "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000c1"
  r1 = "urn:omos:personal-memory:record:01900000-0000-7000-8000-0000000000c2"
  l2 = "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000c3"
  r2 = "urn:omos:personal-memory:record:01900000-0000-7000-8000-0000000000c4"

  # Codex 寫 → Claude Code 讀同一個 store
  wrote = codex.write("MemorySupportLink", link_body(l1, r1), "k-c1")
  seen_by_claude = claude.read
  check("C", "Codex 寫入成功", wrote["status"].to_s, wrote["status"] == "WROTE")
  check("C", "Claude Code 從同一個 store 讀到 Codex 寫的列", "",
        seen_by_claude.is_a?(Array) && seen_by_claude.any? { |r| r["row_id"] == l1 })

  # Claude Code 寫 → Codex 讀（反向）
  wrote2 = claude.write("MemorySupportLink", link_body(l2, r2), "k-c2")
  seen_by_codex = codex.read
  check("C", "Claude Code 寫入成功", wrote2["status"].to_s, wrote2["status"] == "WROTE")
  check("C", "Codex 反向讀到 Claude Code 寫的列", "",
        seen_by_codex.is_a?(Array) && seen_by_codex.any? { |r| r["row_id"] == l2 })
  check("C", "兩邊看到的是同一份資料（不是各自的 store）", "",
        seen_by_codex.map { |r| r["row_id"] }.sort == seen_by_claude.map { |r| r["row_id"] }.sort + [l2].sort - [])

  # 跨專案：切到 projB 不得擴權
  widened = begin
    OMOS::SessionStart.produce(host: "Codex", native_session_id: "codex-2", cwd: proj_b,
                               project_ref: "urn:omos:project:b", runtime_scope_mode: "EMPLOYEE_PRIVATE",
                               project_visibility_scope: "WORK_CONTEXT_PARTICIPANTS")
    nil
  rescue OMOS::SessionStart::Refused => e
    e.code
  end
  check("C", "切換專案不得擴權", widened.to_s, widened == "HBV1_PROJECT_SCOPE_WIDENS_BASELINE")

  narrowed = OMOS::SessionStart.produce(host: "Codex", native_session_id: "codex-3", cwd: proj_b,
                                        project_ref: "urn:omos:project:b",
                                        runtime_scope_mode: "EMPLOYEE_PRIVATE",
                                        project_visibility_scope: "SELF_ONLY")
  check("C", "切換專案可維持同等收窄", narrowed["effective_scope"], narrowed["effective_scope"] == "SELF_ONLY")
  check("C", "切換專案不重建 store", "", File.exist?(store))

  # 週期：同一 review period 跨 Host 仍是同一身分，且只能收一次 terminal
  period = "urn:omos:personal-memory:review-period:2026-W38"
  item = "urn:omos:personal-memory:candidate:01900000-0000-7000-8000-0000000000d1"
  first = codex.closeout(closeout_payload(period, item, "FAILED", "SCHEDULED"))
  second = claude.closeout(closeout_payload(period, item, "COMPLETE", "RETRY"))
  third = codex.closeout(closeout_payload(period, item, "NO_PROMOTION", "RETRY"))
  check("C", "Codex 開的週期，Claude Code 可以接續收尾", second["status"].to_s,
        first["status"] == "COMMITTED" && second["status"] == "COMMITTED")
  check("C", "第二次 terminal closeout 被拒", third["code"].to_s,
        third["status"] == "REJECTED" && third["code"] == "PMR_CLOSEOUT_FAILS_WEEKLY_CYCLE_CONTRACT")

  # promotion identity 在 retry 間漂移 → 被拒
  drift_payload = closeout_payload("#{period}-b", item, "COMPLETE", "SCHEDULED")
  codex.closeout(drift_payload)
  drifted = closeout_payload("#{period}-b", item, "COMPLETE", "RETRY")
  drifted["item_dispositions"][item]["promotion_idempotency_key"] = "pk-999"
  drift_res = claude.closeout(drifted)
  check("C", "跨 Host 的 retry 換掉 promotion identity 被拒", drift_res["code"].to_s,
        drift_res["status"] == "REJECTED")

  # 重啟：關掉兩個進程再開，重放同一筆寫入不得產生第二列
  codex.close
  claude.close
  db = SQLite3::Database.new(store)
  rows_before_restart = db.get_first_value("SELECT COUNT(*) FROM memory_rows")
  terminal_before = db.get_first_value("SELECT COUNT(*) FROM closeouts WHERE is_terminal = 1")
  db.close

  codex2 = Host.new(store, codex_binding)
  replay = codex2.write("MemorySupportLink", link_body(l1, r1), "k-c1")
  codex2.close
  db = SQLite3::Database.new(store)
  rows_after_restart = db.get_first_value("SELECT COUNT(*) FROM memory_rows")
  terminal_after = db.get_first_value("SELECT COUNT(*) FROM closeouts WHERE is_terminal = 1")
  db.close
  check("C", "重啟後重放同一筆是 no-op", replay["status"].to_s, replay["status"] == "REPLAYED")
  check("C", "重啟不產生第二列", "#{rows_before_restart}→#{rows_after_restart}",
        rows_before_restart == rows_after_restart)
  check("C", "重啟不產生第二次 terminal closeout", "#{terminal_before}→#{terminal_after}",
        terminal_before == terminal_after && terminal_before == 2)

  # install → upgrade → uninstall → reinstall 不破壞 Personal Store truth
  inst = OMOS::Installer.new(home: home, store_path: store)
  inst.upgrade
  inst.uninstall
  inst.install
  db = SQLite3::Database.new(store)
  rows_final = db.get_first_value("SELECT COUNT(*) FROM memory_rows")
  terminal_final = db.get_first_value("SELECT COUNT(*) FROM closeouts WHERE is_terminal = 1")
  db.close
  check("C", "install→upgrade→uninstall→reinstall 後資料不變",
        "rows=#{rows_final} terminal=#{terminal_final}",
        rows_final == rows_after_restart && terminal_final == terminal_after)
end

width = RESULTS.map { |_, _, n, _| n.length }.max
%w[A B C].each do |group|
  RESULTS.select { |r| r[1] == group }.each { |st, g, n, d| puts format("%-4s %s  %-#{width}s  %s", st, g, n, d) }
end
failed = RESULTS.count { |st, _, _, _| st == "FAIL" }
puts "\n3c conformance：#{RESULTS.size - failed}/#{RESULTS.size} PASS"
exit(failed.zero? ? 0 : 1)
