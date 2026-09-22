# frozen_string_literal: true
#
# 切片 3c conformance：主卡三組驗收，全部對實物。
#
#   A 安裝與復原      在隔離 HOME 實際 install / reinstall / upgrade / uninstall；
#                     保留非本產品設定與個人資料；中途失敗必須完全復原。
#   B Doctor 與失敗診斷 讀實際設定、實際啟動目標、實際開 store；
#                     「設定存在」「程序能啟動」「Store 能用」是三種不同結果。
#   C 並行 session 與跨專案  真的同時跑兩個 MCP 進程對同一個 store 往返
#                     （Codex 目前無官方 native session id 管道，一律 fail
#                     closed，見 3b；這裡改測同 Host 兩個並行 session）；
#                     切換專案不得擴權；retry／重啟不得產生第二筆。
#
# 全程不碰使用者的正式設定——所有操作都在 Dir.mktmpdir 的假 HOME 內。

require "json"
require "stringio"
require "tmpdir"
require "fileutils"
require "open3"
require "sqlite3"
require "digest"
require "shellwords"
require "rbconfig"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "omos/version_guard"
OMOS::VersionGuard.assert!
require "omos/artifact"
require "omos/installer"
require "omos/doctor"
require "omos/session_start"
require_relative "support"

C = Support::Checks.new("3c conformance")
F = Support::Fixtures


# ===========================================================================
# A 安裝與復原
# ===========================================================================
C.group = "A"
Dir.mktmpdir("omos-3c-a") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  store = File.join(dir, "p.db")
  before = Support::FakeHome.read_all(home)
  inst = OMOS::Installer.new(home: home, store_path: store)

  inst.install
  C.check("install 後已交付 Host 判定未漂移", "",
        OMOS::Contract.supported_hosts.all? do |h|
          OMOS::HostConfig.new(h, home: home, command_map: inst.command_map).own_registration_problem.nil?
        end)
  # repair-03 P2：v1 的 delivery scope 只有 Claude Code，預設安裝不得再往
  # blocked host 寫一套必定不能使用的 MCP + hook。
  codex_cfg_after_install = File.read(File.join(home, ".codex/config.toml"))
  C.check("install 預設不碰 blocked host（Codex 設定位元組不變）",
        "#{before[:codex].bytesize}→#{codex_cfg_after_install.bytesize}",
        codex_cfg_after_install == before[:codex])
  C.check("receipt 只記錄已交付 Host", inst.receipt["hosts"].keys.inspect,
        inst.receipt["hosts"].keys == OMOS::Contract.supported_hosts)
  C.check("install 保留使用者註解與他人 mcp", "",
        File.read(File.join(home, ".codex/config.toml")).include?("使用者自己的註解") &&
        File.read(File.join(home, ".codex/config.toml")).include?("[mcp_servers.foreign]"))
  C.check("install 保留 Claude 使用者狀態", "",
        JSON.parse(File.read(File.join(home, ".claude.json")))["userState"] == { "k" => 1 })

  # 個人資料：安裝後寫一筆，之後所有操作都不得動到它
  rt = OMOS::Runtime.open(store)
  link = "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000a1"
  rec = "urn:omos:personal-memory:record:01900000-0000-7000-8000-0000000000a2"
  rt.write_row(kind: "MemorySupportLink", resource: F.link_body(link, rec), idempotency_key: "k-a1",
               surface: OMOS::Runtime::SURFACES[:cli])
  rt.store.close

  inst.install # reinstall（idempotent）
  inst.upgrade
  C.check("reinstall / upgrade 後仍未漂移", "",
        OMOS::Contract.supported_hosts.all? do |h|
          OMOS::HostConfig.new(h, home: home, command_map: inst.command_map).own_registration_problem.nil?
        end)
  C.check("upgrade 同樣不會把 blocked host 補裝回去", "",
        File.read(File.join(home, ".codex/config.toml")) == before[:codex])
  db = SQLite3::Database.new(store)
  survived = db.get_first_value("SELECT COUNT(*) FROM memory_rows")
  db.close
  C.check("reinstall / upgrade 不動個人資料", "rows=#{survived}", survived == 1)

  inst.uninstall
  after = Support::FakeHome.read_all(home)
  C.check("uninstall 後 Codex 設定位元組完全相同", "#{before[:codex].bytesize}→#{after[:codex].bytesize}",
        after[:codex] == before[:codex])
  C.check("uninstall 後他人 Claude mcp 保留", "",
        JSON.parse(after[:claude])["mcpServers"].keys == ["relay"])
  C.check("uninstall 預設保留 Personal Store", "", File.exist?(store))

  # --- Host 端驗證：用真的 codex CLI 讀我們寫出的設定 ---
  #
  # 這一項回答 review 的核心質疑：post-write 複驗只能證明「我讀得回我寫的」，
  # 不能證明 Host 接受。這裡把假 HOME 交給實際安裝的 codex CLI 去解析。
  # repair-03 P2：Codex 已非預設安裝對象，這裡**明確指名**才裝——保留「我們
  # 寫出的形狀真的被 Host 解析得了」這項實證（EMEM-11b 解除時還要用），同時
  # 不讓它偷偷變回預設交付。
  if system("command -v codex >/dev/null 2>&1")
    OMOS::Installer.new(home: home, store_path: store).install(hosts: ["Codex"])
    out, _err, st = Open3.capture3({ "HOME" => home }, "codex", "mcp", "get", "omos.personal-memory")
    parsed = out.include?("transport: stdio") && out.include?("omos-personal-memory-mcp")
    C.check("真的 codex CLI 解析我們寫出的 MCP 註冊", st.success? ? out.lines.grep(/transport/).first.to_s.strip : "失敗",
            st.success? && parsed)
    C.check("codex 自行判定 transport（我們不寫該欄位）", "",
            !File.read(File.join(home, ".codex/config.toml")).include?("transport ="))
    # uninstall 依 receipt 的 hosts 清理——receipt 這時記的是 ["Codex"]，
    # 所以殘件清得掉。這正是「先前版本曾裝過 Codex」的回收路徑。
    OMOS::Installer.new(home: home, store_path: store).uninstall
    C.check("uninstall 依 receipt 清掉明確指名安裝的 blocked host，位元組復原", "",
            File.read(File.join(home, ".codex/config.toml")) == before[:codex])
  else
    C.check("真的 codex CLI 解析我們寫出的 MCP 註冊", "本機無 codex CLI，略過", true)
  end

  # 中途失敗必須完全復原。跨 Host 原子性要有兩個 Host 才驗得出來，而預設
  # 交付只剩一個，所以這裡明確指名兩個 Host——驗的是 installer 的回復機制，
  # 不是「Codex 是交付對象」。
  pre_fail = Support::FakeHome.read_all(home)
  code = begin
    inst.install(hosts: OMOS::HostConfig.hosts, fail_after: "Codex")
    nil
  rescue OMOS::Installer::Failed => e
    e.code
  end
  post_fail = Support::FakeHome.read_all(home)
  C.check("注入的中途失敗被回報", code.to_s, code == "INSTALL_INJECTED_FAILURE")
  C.check("中途失敗後所有設定完全復原", "", post_fail == pre_fail)
  C.check("中途失敗後沒有留下 receipt", "", !File.exist?(inst.receipt_path))
end

# --- repair-02 P2：hook 辨識改精確相等，collision-adjacent 的第三方 hook 不得被誤認 ---
#
# reviewer 實測過的失敗模式：舊版用 start_with? 前綴命中，會把
# "<本產品 hook 命令>-foreign ..." 誤判成自己的註冊，導致 install 少加一組、
# uninstall 誤刪別人的 hook。這裡直接構造這種「以本產品命令當前綴」的第三方
# hook，驗證 install/uninstall/doctor 都不會認錯。
Dir.mktmpdir("omos-3c-a-hook-identity") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  proj = File.join(dir, "proj")
  FileUtils.mkdir_p(proj)
  store = File.join(dir, "p.db")
  inst = OMOS::Installer.new(home: home, store_path: store)

  foreign_command = "#{inst.hook_command}-foreign --host \"Claude Code\" --runtime-scope-mode EMPLOYEE_PRIVATE"
  settings = JSON.parse(File.read(File.join(home, ".claude/settings.json")))
  settings["hooks"] = { "SessionStart" => [{ "hooks" => [{ "type" => "command", "command" => foreign_command }] }] }
  File.write(File.join(home, ".claude/settings.json"), "#{JSON.pretty_generate(settings)}\n")

  inst.install
  installed = JSON.parse(File.read(File.join(home, ".claude/settings.json")))
  groups = installed.dig("hooks", "SessionStart") || []
  commands = groups.flat_map { |g| Array(g["hooks"]).map { |h| h["command"] } }
  C.check("install 後 collision-adjacent 第三方 hook 與本產品 hook 並存（沒被誤認合併）",
        commands.inspect, commands.include?(foreign_command) && commands.size == 2)

  inst.uninstall
  uninstalled = JSON.parse(File.read(File.join(home, ".claude/settings.json")))
  after_commands = (uninstalled.dig("hooks", "SessionStart") || []).flat_map do |g|
    Array(g["hooks"]).map { |h| h["command"] }
  end
  C.check("uninstall 只移除本產品自己那組，collision-adjacent 第三方 hook 原樣保留",
        after_commands.inspect, after_commands == [foreign_command])

  inst.install
  doctor_with_collision = OMOS::Doctor.new(home: home, store_path: store, cwd: proj).run
                                      .find { |r| r.id == "claude_code_session_start_hook_present" }
  # 這一項本來就是既有已知 WARN（見 3b：形狀寫對了，但尚未由真 Host 觸發過），
  # collision 不該把它拖成 FAIL（=「以為 hook 沒寫入」，其實是把本產品的 hook
  # 和第三方那組搞混、比對不到自己）。
  C.check("doctor 在 collision-adjacent 第三方 hook 存在下仍認得出本產品自己的 hook（維持既有 WARN，不退化成 FAIL）",
        "#{doctor_with_collision.status}: #{doctor_with_collision.detail}",
        doctor_with_collision.status == "WARN" && doctor_with_collision.detail.include?("已依官方 schema 寫入"))
end

# --- Slice A：activation substrate（固定 launcher → current → versions/<id>）---
#
# Q7 §0.1 凍結的三層分離。這一組驗的是：Host 只認固定 launcher、artifact 由
# 內容識別、原本的 stale-hook 缺陷歸零、舊形狀安裝可被遷移、證據不足時不猜。
Dir.mktmpdir("omos-3c-a-activation") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  store = File.join(dir, "p.db")
  settings = File.join(home, ".claude/settings.json")
  omos = File.join(home, ".omos/personal-memory")
  hooks = lambda do
    (JSON.parse(File.read(settings)).dig("hooks", "SessionStart") || [])
      .flat_map { |g| Array(g["hooks"]).map { |h| h["command"] } }
  end

  inst = OMOS::Installer.new(home: home, store_path: store)
  first = inst.install

  C.check("Host 只寫固定 launcher，且不含任何版本字樣",
        hooks.call.first.to_s.sub(home, "~"),
        hooks.call.size == 1 &&
        hooks.call.first.start_with?(File.join(omos, "bin/omos-personal-memory-session-start")) &&
        !hooks.call.first.include?("versions/"))

  C.check("hook 的 argv authority 注入未被 launcher 吃掉", "",
        hooks.call.first.include?("--host \"Claude Code\"") &&
        hooks.call.first.include?("--runtime-scope-mode EMPLOYEE_PRIVATE"))

  C.check("current 是 symlink 且指向 versions/<artifact-id>",
        File.readlink(File.join(omos, "current")).sub(home, "~"),
        File.symlink?(File.join(omos, "current")) &&
        File.readlink(File.join(omos, "current")) == File.join(omos, "versions", first[:artifact_id]))

  C.check("artifact 自帶 2 份 spec ＋ 7 支 evaluator（materialize）",
        "#{Dir.glob(File.join(omos, "current/governance/規格/v0.1/*.yaml")).size} spec / " \
        "#{Dir.glob(File.join(omos, "current/governance/scripts/lib/*.rb")).size} evaluator",
        Dir.glob(File.join(omos, "current/governance/規格/v0.1/*.yaml")).size == 2 &&
        Dir.glob(File.join(omos, "current/governance/scripts/lib/*.rb")).size == 7)

  # materialize 必須 byte-identical，否則 artifact 與 repo 判定依據會不同
  if (repo = Support.repo_originals)
    drifted = OMOS::Installer::GOVERNANCE_FILES.reject do |rel|
      Digest::SHA256.file(File.join(repo, rel)).hexdigest ==
        Digest::SHA256.file(File.join(omos, "current/governance", rel)).hexdigest
    end
    C.check("materialize 的 9 個治理檔與 repo 原件 byte-identical", drifted.inspect, drifted.empty?)
  else
    C.skip("materialize 的 9 個治理檔與 repo 原件 byte-identical",
           "workspace B 無 repo 原件可比對；由 repo 側 validate_packaged_governance_drift.rb 負責")
  end

  # 透過固定 launcher 實際執行——證明 artifact 離開 repo 也跑得起來
  state_dir = File.join(dir, "state")
  payload = JSON.generate({ "session_id" => "slice-a-1", "cwd" => dir,
                            "hook_event_name" => "SessionStart", "source" => "startup" })
  lout, lerr, lst = Open3.capture3({ "OMOS_SESSION_STATE_DIR" => state_dir },
                                   File.join(omos, "bin/omos-personal-memory-session-start"),
                                   "--host", "Claude Code",
                                   "--runtime-scope-mode", "EMPLOYEE_PRIVATE", stdin_data: payload)
  C.check("固定 launcher 可實際執行，且 artifact 用自己的治理檔",
        lst.success? ? "exit=0" : (lerr + lout)[0, 60],
        lst.success? && lout.include?("hookSpecificOutput") &&
        Dir.glob(File.join(state_dir, "*.json")).size == 1)

  # --- artifact identity 的 deterministic semantics（reviewer P2）---
  Dir.mktmpdir("omos-ident") do |idd|
    mk = lambda do |root|
      FileUtils.mkdir_p(File.join(root, "lib"))
      File.write(File.join(root, "lib/a.rb"), "puts 1\n")
      File.write(File.join(root, "top.txt"), "x\n")
    end
    a = File.join(idd, "a")
    b = File.join(idd, "b-different-path")
    mk.call(a)
    mk.call(b)
    id_a = OMOS::Artifact.identity(a)
    C.check("identity：同內容不同安裝位置 → 同一個 id", id_a[0, 12], id_a == OMOS::Artifact.identity(b))
    FileUtils.touch(File.join(a, "lib/a.rb"), mtime: Time.now - 86_400)
    C.check("identity：mtime 改變不影響 id", "", id_a == OMOS::Artifact.identity(a))
    File.write(File.join(b, "lib/a.rb"), "puts 99\n")
    C.check("identity：payload 改變 → id 改變", "", id_a != OMOS::Artifact.identity(b))
  end
  C.check("identity：receipt 等 activation metadata 不影響 id（安裝後重算相同）",
        "", OMOS::Artifact.identity(File.join(omos, "versions", first[:artifact_id])) == first[:artifact_id])

  # --- 原 stale-hook 缺陷：換 product_root 後仍只有一組註冊 ---
  relocated = File.join(dir, "relocated-product")
  FileUtils.mkdir_p(relocated)
  OMOS::Installer::PAYLOAD_ENTRIES.each do |entry|
    src = File.join(OMOS::Contract::ARTIFACT_ROOT, entry)
    File.symlink(src, File.join(relocated, entry)) if File.exist?(src)
  end
  second = OMOS::Installer.new(home: home, product_root: relocated, store_path: store).upgrade
  C.check("換 product_root 升級後，Host 內仍只有一組註冊（原 stale-hook 歸零）",
        "#{hooks.call.size} 組", hooks.call.size == 1)
  C.check("同一份 payload → 同一個 artifact_id（install 具 idempotency）",
        second[:artifact_id] == first[:artifact_id] ? "相同" : "不同",
        second[:artifact_id] == first[:artifact_id])

  OMOS::Installer.new(home: home, product_root: relocated, store_path: store).uninstall
  C.check("uninstall 後 Host 零殘留", "#{hooks.call.size} 組", hooks.call.empty?)
  C.check("uninstall 清掉 launcher／current／versions，但保留 Personal Store", "",
        !File.exist?(File.join(omos, "current")) &&
        !Dir.exist?(File.join(omos, "versions")) &&
        !File.exist?(File.join(omos, "bin/omos-personal-memory-mcp")) &&
        File.exist?(store))
end

# --- Slice A：production native dependency manifest ---
#
# Slice B 的 runtime profile guard 要消費這份宣告（對「全部 production native
# dependencies」驗 loader resolution、做真實 load probe）。宣告若與實況脫節，
# guard 就會驗錯東西，因此這裡對**實際載入的結果**逐項比對。
Dir.mktmpdir("omos-3c-a-manifest") do |dir|
  root = OMOS::Contract::ARTIFACT_ROOT
  manifest = JSON.parse(File.read(File.join(root, "native-dependencies.json")))
  declared = manifest.fetch("production_native_dependencies")

  # 在乾淨子行程裡載入 production 進入點，取實際載入的原生擴充
  probe = <<~RUBY
    require "omos/cli"; require "omos/runtime"; require "omos/mcp_server"
    root = #{root.dump}
    puts $LOADED_FEATURES.grep(/\\.bundle$/).select { |f| f.start_with?(root) }.sort.join("\\n")
  RUBY
  out, err, st = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(root, "Gemfile") },
                                RbConfig.ruby, "-rbundler/setup", "-I#{File.join(root, "lib")}",
                                "-e", probe)
  loaded = out.lines.map(&:strip).reject(&:empty?)
  C.check("能取得 production 實際載入的原生擴充", st.success? ? "#{loaded.size} 個" : err[0, 60],
          st.success? && !loaded.empty?)

  actual_names = loaded.map { |p| File.basename(p, ".bundle") }.sort
  C.check("manifest 宣告的 extension 與實際載入完全一致（不多不少）",
        "宣告=#{declared.map { |e| e["extension"] }.sort.inspect} 實際=#{actual_names.inspect}",
        declared.map { |e| e["extension"] }.sort == actual_names)

  # 每一項宣告的 require 名稱必須真的能載入，且 non_system_libraries 與 otool 一致
  mismatched = declared.reject do |entry|
    abs = loaded.find { |p| File.basename(p, ".bundle") == entry["extension"] }
    next false if abs.nil?

    libs = `otool -L #{Shellwords.escape(abs)} 2>/dev/null`.lines.drop(1)
           .map { |l| l.strip.sub(/ \(.*/, "") }.reject { |l| l.start_with?("/usr/lib/") }.sort
    libs == entry["non_system_libraries"]
  end
  C.check("manifest 記錄的 non_system_libraries 與 otool 實況一致",
        mismatched.map { |e| e["extension"] }.inspect, mismatched.empty?)

  # Q6 Part 1 的結論要留在可執行的證據裡：只有 bigdecimal 依賴 libruby
  libruby_dependents = declared.select { |e| e["non_system_libraries"].any? { |l| l.include?("libruby") } }
  C.check("只有 bigdecimal 依賴 libruby（Q6 Part 1 的 ABI 邊界）",
        libruby_dependents.map { |e| e["extension"] }.inspect,
        libruby_dependents.map { |e| e["extension"] } == ["bigdecimal"])

  # manifest 必須隨 artifact 一起配送，否則 Slice B 在已安裝的 artifact 上讀不到
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  OMOS::Installer.new(home: home, store_path: File.join(dir, "p.db")).install
  C.check("manifest 隨 artifact 一起配送（已安裝的 artifact 讀得到）", "",
        File.file?(File.join(home, ".omos/personal-memory/current/native-dependencies.json")))
end

# --- Slice B：runtime profile guard ---
#
# 取代 RUBY_VERSION == "3.4.10"。Q6 Part 1 證明版本字串同時過嚴與過鬆，真正的
# 約束是 native linkage 可解析 ＋ ABI 相容。
Dir.mktmpdir("omos-3c-b-runtime-profile") do |dir|
  root = OMOS::Contract::ARTIFACT_ROOT

  # (0) reviewer P2：manifest 的 require 欄位必須被真正使用。
  #     mutation proof——把某一項的 require 改成不存在的名稱，guard 必須轉紅；
  #     不得被「該 extension 其實已被別的路徑載入」的證據掩蓋。
  mutated = File.join(dir, "mutated-manifest.json")
  man = JSON.parse(File.read(File.join(root, "native-dependencies.json")))
  man["production_native_dependencies"] = man["production_native_dependencies"].map do |e|
    e["extension"] == "bigdecimal" ? e.merge("require" => "bigdecimal_typo_does_not_exist") : e
  end
  File.write(mutated, JSON.generate(man))
  probe = <<~RUBY
    require "omos/runtime_profile"
    OMOS::RuntimeProfile.send(:remove_instance_variable, :@manifest) rescue nil
    OMOS::RuntimeProfile.define_singleton_method(:manifest) do
      JSON.parse(File.read(#{mutated.dump})).fetch("production_native_dependencies")
    end
    begin
      puts OMOS::RuntimeProfile.verify!
    rescue OMOS::RuntimeProfile::Unsupported => e
      puts e.code
    end
  RUBY
  out, _err, = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(root, "Gemfile") },
                              RbConfig.ruby, "-rbundler/setup", "-I#{File.join(root, "lib")}",
                              "-e", probe)
  C.check("manifest 的 require 被真正使用：拼錯的 require 會讓 guard 轉紅",
        out.strip, out.strip == "OMOS_NATIVE_REQUIRE_FAILED")

  # (1) 正常情況：四項檢查全過，且回報 QUALIFIED
  ok_out, ok_err, ok_st = Open3.capture3(
    { "BUNDLE_GEMFILE" => File.join(root, "Gemfile") }, RbConfig.ruby, "-rbundler/setup",
    "-I#{File.join(root, "lib")}", "-e",
    'require "omos/runtime_profile"; puts OMOS::RuntimeProfile.verify!'
  )
  C.check("已 qualification 的組合回報 QUALIFIED",
        ok_st.success? ? ok_out.strip : ok_err[0, 60], ok_out.strip == "QUALIFIED")

  # (2) 宣告的 native 相依解析不到 → 當場擋下，並指出缺的是什麼
  broken = File.join(dir, "broken-manifest.json")
  man2 = JSON.parse(File.read(File.join(root, "native-dependencies.json")))
  man2["production_native_dependencies"] = man2["production_native_dependencies"].map do |e|
    e["extension"] == "bigdecimal" ? e.merge("non_system_libraries" => ["/nonexistent/libruby.3.4.dylib"]) : e
  end
  File.write(broken, JSON.generate(man2))
  probe2 = <<~RUBY
    require "omos/runtime_profile"
    OMOS::RuntimeProfile.define_singleton_method(:manifest) do
      JSON.parse(File.read(#{broken.dump})).fetch("production_native_dependencies")
    end
    begin
      OMOS::RuntimeProfile.verify!
      puts "NO_ERROR"
    rescue OMOS::RuntimeProfile::Unsupported => e
      puts "#{"#{'#'}"}{e.code}|#{"#{'#'}"}{e.detail}"
    end
  RUBY
  out2, = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(root, "Gemfile") },
                         RbConfig.ruby, "-rbundler/setup", "-I#{File.join(root, "lib")}", "-e", probe2)
  code2, detail2 = out2.strip.split("|", 2)
  C.check("宣告的 native 相依解析不到 → guard 擋下", code2.to_s,
        code2 == "OMOS_NATIVE_DEPENDENCY_UNRESOLVED")
  C.check("錯誤訊息指出實際缺的是哪個函式庫（不是只說版本不符）",
        detail2.to_s[0, 50], detail2.to_s.include?("/nonexistent/libruby.3.4.dylib"))

  # (3) 能跑但未 qualified → 不擋，但必須是明確可辨識的狀態
  unqual = File.join(dir, "unqualified-profile.json")
  File.write(unqual, JSON.generate({ "qualified_profiles" => [{ "host_os" => "someother" }] }))
  probe3 = <<~RUBY
    require "omos/runtime_profile"
    OMOS::RuntimeProfile.define_singleton_method(:qualified_profiles) do
      JSON.parse(File.read(#{unqual.dump})).fetch("qualified_profiles")
    end
    status = OMOS::RuntimeProfile.assert_supported!
    puts "status=#{"#{'#'}"}{status} env=#{"#{'#'}"}{ENV["OMOS_RUNTIME_PROFILE_STATUS"]}"
  RUBY
  out3, err3, st3 = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(root, "Gemfile") },
                                   RbConfig.ruby, "-rbundler/setup",
                                   "-I#{File.join(root, "lib")}", "-e", probe3)
  C.check("未 qualified 但能跑 → 不擋下（仍可執行）", "exit=#{st3.exitstatus}", st3.success?)
  C.check("未 qualified 必須明確可辨識（stderr 通知 ＋ 狀態變數）",
        out3.strip[0, 60],
        out3.include?("status=UNQUALIFIED_RUNTIME_PROFILE") &&
        out3.include?("env=UNQUALIFIED_RUNTIME_PROFILE") &&
        err3.include?("UNQUALIFIED_RUNTIME_PROFILE"))

  # (4) 判準不再是版本字串：ABI 目錄由 artifact 自己的 vendor 佈局推導
  abi_dirs = Dir.children(File.join(root, "vendor/bundle/ruby"))
  C.check("ABI 判準來自 artifact 自身內容（vendor/bundle/ruby/<ABI>）",
        abi_dirs.inspect,
        abi_dirs.size == 1 && abi_dirs.first == RbConfig::CONFIG["ruby_version"])
  guard_src = File.read(File.join(root, "bin/pinned-ruby.sh"))
  C.check("選擇器不再以 RUBY_VERSION 字串相等為判準", "",
        !guard_src.include?('print RUBY_VERSION') &&
        guard_src.include?('RbConfig::CONFIG["ruby_version"]'))

  # (5) 完全不相容的 Ruby 仍當場失敗，不靜默改用別的
  bad_out, bad_err, bad_st = Open3.capture3({ "OMOS_RUBY" => "/usr/bin/ruby" },
                                            File.join(root, "exe/omos-personal-memory"), "status")
  C.check("不相容的 Ruby 當場失敗且訊息完整（含實際 ABI 值）",
        "exit=#{bad_st.exitstatus}",
        !bad_st.success? && (bad_err + bad_out).include?("ABI #{RbConfig::CONFIG["ruby_version"]}"))
end

# --- Slice A repair-01 P1-1：升級失敗必須把 activation 一起回滾 ---
#
# 先前只還原 Host 設定：升級失敗後 current 已指向新版、舊 receipt 還被刪掉，
# 違反 Q7 的 atomic activation/rollback。這一組驗整筆交易。
Dir.mktmpdir("omos-3c-a-rollback") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  store = File.join(dir, "p.db")
  omos = File.join(home, ".omos/personal-memory")
  settings = File.join(home, ".claude/settings.json")

  first = OMOS::Installer.new(home: home, store_path: store).install
  good_current = File.readlink(File.join(omos, "current"))
  good_receipt = File.read(File.join(omos, "install-receipt.json"))
  good_settings = File.read(settings)

  # 造一份內容不同的 artifact 來源（多一個檔案 → 不同 artifact_id）
  altered = File.join(dir, "altered-product")
  FileUtils.mkdir_p(File.join(altered, "lib/omos"))
  OMOS::Installer::PAYLOAD_ENTRIES.each do |entry|
    src = File.join(OMOS::Contract::ARTIFACT_ROOT, entry)
    next unless File.exist?(src)
    next if entry == "lib"

    File.symlink(src, File.join(altered, entry))
  end
  FileUtils.cp_r(File.join(OMOS::Contract::ARTIFACT_ROOT, "lib/."), File.join(altered, "lib"))
  File.write(File.join(altered, "lib/omos/slice_a_marker.rb"), "# 僅用於改變 artifact 內容\n")

  # repair-02：模擬「前一版的 launcher 內容與新版不同」。只記錄存在與否是
  # 不夠的——write_launchers 會覆寫，失敗後若不還原原始位元組，就會出現
  # old current + old receipt + old Host config + NEW launcher 的半套狀態。
  launcher_paths = OMOS::Installer::LAUNCHER_NAMES.map { |n| File.join(omos, "bin", n) }
  launcher_paths.each { |p| File.write(p, "#!/bin/sh\n# previous-version launcher\nexec true\n") }
  # 刻意用與新版不同的模式（0700 vs 0755），否則這條對 mode 沒有鑑別力
  FileUtils.chmod(0o700, launcher_paths)
  good_launchers = launcher_paths.to_h { |p| [p, File.binread(p)] }
  good_modes = launcher_paths.to_h { |p| [p, File.stat(p).mode & 0o7777] }

  code = begin
    OMOS::Installer.new(home: home, product_root: altered, store_path: store)
                   .install(fail_after: "Claude Code")
    nil
  rescue OMOS::Installer::Failed => e
    e.code
  end
  C.check("升級中途失敗被回報", code.to_s, code == "INSTALL_INJECTED_FAILURE")
  C.check("失敗後 launcher 還原成前一版的位元組（不是留下新版）",
        launcher_paths.all? { |p| File.binread(p) == good_launchers[p] } ? "byte-identical" : "被新版覆蓋",
        launcher_paths.all? { |p| File.binread(p) == good_launchers[p] })
  C.check("失敗後 launcher 的模式也精確還原（0700，非新版的 0755）",
        launcher_paths.map { |p| format("%o", File.stat(p).mode & 0o7777) }.uniq.inspect,
        launcher_paths.all? { |p| (File.stat(p).mode & 0o7777) == good_modes[p] })
  C.check("失敗後 current 切回舊 artifact",
        File.readlink(File.join(omos, "current")) == good_current ? "已還原" : "仍指向新版",
        File.readlink(File.join(omos, "current")) == good_current)
  C.check("失敗後 receipt 還原成舊那份（不是被刪掉）",
        File.exist?(File.join(omos, "install-receipt.json")) ? "存在" : "不見了",
        File.exist?(File.join(omos, "install-receipt.json")) &&
        File.read(File.join(omos, "install-receipt.json")) == good_receipt)
  C.check("失敗後 Host 設定完全還原", "", File.read(settings) == good_settings)
  orphans = Dir.children(File.join(omos, "versions")) - [first[:artifact_id]]
  C.check("失敗交易新建的孤兒 artifact 已清除", orphans.inspect, orphans.empty?)
  C.check("舊 artifact 仍可用（current 指得到實體）", "",
        File.directory?(File.readlink(File.join(omos, "current"))))
end

# --- Slice A repair-01 P1-2：已安裝的 artifact 必須能自我安裝／升級 ---
#
# governance 來源若寫死 repo，standalone artifact 一安裝就
# INSTALL_GOVERNANCE_SOURCE_MISSING——那等於「搬得出去但不能當 artifact 用」。
Dir.mktmpdir("omos-3c-a-selfhost") do |dir|
  home_a = File.join(dir, "home-a")
  home_b = File.join(dir, "home-b")
  Support::FakeHome.seed(home_a)
  Support::FakeHome.seed(home_b)

  OMOS::Installer.new(home: home_a, store_path: File.join(dir, "a.db")).install
  installed_cli = File.join(home_a, ".omos/personal-memory/current/exe/omos-personal-memory")

  # 用**已安裝的 artifact**（不是 repo）對第二個乾淨 HOME 安裝
  out, err, st = Open3.capture3({ "HOME" => home_b }, installed_cli, "install",
                                "--store", File.join(dir, "b.db"))
  C.check("已安裝的 artifact 可對另一個 HOME 執行 install（不依賴 repo）",
        st.success? ? "exit=0" : (err + out)[0, 70], st.success?)

  gov_b = File.join(home_b, ".omos/personal-memory/current/governance")
  if (repo = Support.repo_originals)
    drifted = OMOS::Installer::GOVERNANCE_FILES.reject do |rel|
      File.file?(File.join(gov_b, rel)) &&
        Digest::SHA256.file(File.join(repo, rel)).hexdigest ==
          Digest::SHA256.file(File.join(gov_b, rel)).hexdigest
    end
    C.check("自我安裝產生的 artifact，9 個治理檔仍與原件 byte-identical",
          drifted.inspect, drifted.empty?)
  else
    # 原件不在，但「自我安裝有沒有把 9 份都帶過去」仍然驗得到，照驗。
    missing = OMOS::Installer::GOVERNANCE_FILES.reject { |rel| File.file?(File.join(gov_b, rel)) }
    C.check("自我安裝產生的 artifact 仍帶齊 9 份治理檔", missing.inspect, missing.empty?)
    C.skip("自我安裝產生的 artifact，9 個治理檔仍與原件 byte-identical",
           "workspace B 無 repo 原件可比對；由 repo 側 drift gate 負責")
  end
end

# --- Slice A：舊形狀（pre-launcher）安裝的遷移 ---
Dir.mktmpdir("omos-3c-a-migration") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  store = File.join(dir, "p.db")
  settings = File.join(home, ".claude/settings.json")
  product = OMOS::Contract::ARTIFACT_ROOT
  legacy_hook = "#{product}/exe/omos-personal-memory-session-start " \
                "--host \"Claude Code\" --runtime-scope-mode EMPLOYEE_PRIVATE"
  hooks = lambda do
    (JSON.parse(File.read(settings)).dig("hooks", "SessionStart") || [])
      .flat_map { |g| Array(g["hooks"]).map { |h| h["command"] } }
  end

  # 手工重建舊形狀：Host 直接指向 repo 內 exe/，receipt 記著那兩條命令
  File.write(settings, "#{JSON.pretty_generate({ "hooks" => { "SessionStart" =>
    [{ "hooks" => [{ "type" => "command", "command" => legacy_hook }] }] } })}\n")
  claude_json = JSON.parse(File.read(File.join(home, ".claude.json")))
  claude_json["mcpServers"] = (claude_json["mcpServers"] || {}).merge(
    "omos.personal-memory" => { "command" => "#{product}/exe/omos-personal-memory-mcp", "env" => {} }
  )
  File.write(File.join(home, ".claude.json"), "#{JSON.pretty_generate(claude_json)}\n")
  FileUtils.mkdir_p(File.join(home, ".omos/personal-memory"))
  File.write(File.join(home, ".omos/personal-memory/install-receipt.json"),
             "#{JSON.pretty_generate({ "product_root" => product, "hosts" => { "Claude Code" => {} },
                                       "commands" => {
                                         "OMOS_PERSONAL_MEMORY_MCP" => "#{product}/exe/omos-personal-memory-mcp",
                                         "OMOS_PERSONAL_MEMORY_SESSION_START" => legacy_hook
                                       } })}\n")

  OMOS::Installer.new(home: home, store_path: store).install
  migrated = hooks.call
  C.check("舊形狀安裝被遷移成 launcher 形狀，且不留舊註冊",
        "#{migrated.size} 組", migrated.size == 1 && !migrated.first.include?("#{product}/exe/"))
  C.check("遷移後 MCP 也指向固定 launcher", "",
        JSON.parse(File.read(File.join(home, ".claude.json")))
            .dig("mcpServers", "omos.personal-memory", "command")
            .start_with?(File.join(home, ".omos/personal-memory/bin/")))
  C.check("遷移保留第三方 mcp 設定", "",
        JSON.parse(File.read(File.join(home, ".claude.json")))["mcpServers"].key?("relay"))
end

# --- Slice A：證據不足時不得用猜的 ---
Dir.mktmpdir("omos-3c-a-noevidence") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  product = OMOS::Contract::ARTIFACT_ROOT
  # Host 裡有一條「執行檔名正好是我們的、但路徑不是 launcher」的註冊，
  # 而且**沒有 receipt** 可以證明那是我們寫的。
  File.write(File.join(home, ".claude/settings.json"), "#{JSON.pretty_generate({ "hooks" =>
    { "SessionStart" => [{ "hooks" => [{ "type" => "command",
                                         "command" => "#{product}/exe/omos-personal-memory-session-start --host \"Claude Code\" --runtime-scope-mode EMPLOYEE_PRIVATE" }] }] } })}\n")
  code = begin
    OMOS::Installer.new(home: home, store_path: File.join(dir, "p.db")).install
    nil
  rescue OMOS::Installer::Failed => e
    e.code
  end
  C.check("無 receipt 佐證的疑似舊註冊 → 當場失敗，不自行刪除",
        code.to_s[0, 45], code.to_s.start_with?("INSTALL_UNKNOWN_LEGACY_REGISTRATION"))
end

# --- Slice C：packaged governance 隨 artifact 走，且**只**認自己那一份 ---
Dir.mktmpdir("omos-3c-a-governance") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  inst = OMOS::Installer.new(home: home, store_path: File.join(dir, "p.db"))
  result = inst.install
  artifact = File.readlink(File.join(home, ".omos/personal-memory/current"))

  # 9 份治理檔（2 spec ＋ 7 evaluator）必須在 artifact 內。
  total = OMOS::Installer::GOVERNANCE_FILES.size
  present = OMOS::Installer::GOVERNANCE_FILES.count { |rel| File.file?(File.join(artifact, "governance", rel)) }
  C.check("artifact 內帶齊 #{total} 份治理檔", "#{present}/#{total}", present == total)
  if (repo = Support.repo_originals)
    mismatched = OMOS::Installer::GOVERNANCE_FILES.reject do |rel|
      pkg = File.join(artifact, "governance", rel)
      File.file?(pkg) && Digest::SHA256.file(pkg).hexdigest ==
        Digest::SHA256.file(File.join(repo, rel)).hexdigest
    end
    C.check("且與 repo 原件逐位元組相同", "#{total - mismatched.size}/#{total}", mismatched.empty?)
  else
    C.skip("且與 repo 原件逐位元組相同",
           "workspace B 無 repo 原件可比對；由 repo 側 drift gate 負責")
  end

  # receipt 綁的是 Slice A 定義的那一份 artifact identity——不是安裝時間、
  # 不是 schema_version、也不是「上次裝的那個目錄名」而已：這裡重算一次。
  receipt = inst.receipt
  C.check("receipt 的 artifact_id 等於 current 指向的目錄名",
          receipt["artifact_id"], receipt["artifact_id"] == File.basename(artifact))
  C.check("receipt 的 artifact_id 等於對實物重算的 content identity",
          OMOS::Artifact.identity(artifact)[0, 12],
          receipt["artifact_id"] == OMOS::Artifact.identity(artifact))
  C.check("install 回傳值與 receipt 記的是同一個 artifact", result[:artifact_id][0, 12],
          result[:artifact_id] == receipt["artifact_id"])

  # 缺檔 → fail closed。關鍵在於**不得**因為 repo 還在就靜默改用 repo 的治理：
  # 那會讓一份壞掉的 package 看起來完全健康。
  victim = File.join(artifact, "governance/scripts/lib/personal_memory_host_binding.rb")
  FileUtils.mv(victim, "#{victim}.away")
  out, err, st = Open3.capture3({ "OMOS_PERSONAL_MEMORY_STORE" => File.join(dir, "p.db") },
                                File.join(artifact, "exe/omos-personal-memory"), "status")
  C.check("artifact 少一份治理檔 → 直接失敗，不回退 repo",
          (err + out)[/PACKAGED_GOVERNANCE_MISSING[^\n]{0,40}/].to_s,
          !st.success? && (err + out).include?("PACKAGED_GOVERNANCE_MISSING"))
  FileUtils.mv("#{victim}.away", victim)

  # 被竄改 → artifact identity 立刻不等於 receipt 記的那一份。identity 是
  # 內容決定的，所以「改一個位元組」與「多一個檔案」都會被同一條規則抓到。
  File.write(victim, "#{File.read(victim, encoding: "UTF-8")}\n# tampered\n")
  C.check("治理檔被竄改 → 重算的 identity 不再等於 receipt", "",
          OMOS::Artifact.identity(artifact) != receipt["artifact_id"])
end

# --- Slice C：rollback 只切 pointer ---
Dir.mktmpdir("omos-3c-a-rollback") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  store = File.join(dir, "p.db")

  # 兩個內容不同的來源樹 → 兩個不同的 artifact identity。
  src_v1 = File.join(dir, "src-v1")
  src_v2 = File.join(dir, "src-v2")
  FileUtils.cp_r(OMOS::Contract::ARTIFACT_ROOT, src_v1)
  FileUtils.cp_r(src_v1, src_v2)
  # 只需要「內容不同」——寫一個不會被 require 的標記檔即可。identity 是對
  # artifact **整體內容**取的，任何一個位元組不同就是另一個版本。
  File.write(File.join(src_v2, "lib/omos/.build-variant"), "v2\n")

  v1 = OMOS::Installer.new(home: home, product_root: src_v1, store_path: store).install
  v2_inst = OMOS::Installer.new(home: home, product_root: src_v2, store_path: store)
  v2 = v2_inst.install
  C.check("兩次安裝產生兩個不同的 artifact", "#{v1[:artifact_id][0, 8]}→#{v2[:artifact_id][0, 8]}",
          v1[:artifact_id] != v2[:artifact_id])

  # 「沒碰」要用**可以分辨重寫的**指標。只比內容不行：writer.install 是
  # idempotent 的，一次多餘的重寫會產生位元組完全相同的檔案，內容比對抓不到。
  # 因此連 mtime 與 inode 一起指紋化——in-place 重寫一定會動到 mtime。
  host_files = %w[.codex/config.toml .claude.json .claude/settings.json]
                 .map { |rel| File.join(home, rel) }
  fingerprint = lambda do
    host_files.to_h do |f|
      st = File.stat(f)
      [f, [File.binread(f), st.ino, st.mtime.to_f, st.mode]]
    end
  end
  # 同時把三個設定檔設成唯讀：rollback 若真的去重寫 Host 設定就會 EACCES。
  # 這不只是加強檢查——「Host 設定不可寫時 rollback 仍然要能成功」本身就是
  # pointer-only 的意義：回退不該依賴寫得進使用者的設定檔。
  # chmod 本身會動到 mode，所以基準線要在 chmod **之後**才取。
  host_files.each { |f| File.chmod(0o444, f) }
  before = fingerprint.call
  launchers_before = OMOS::Installer::LAUNCHER_NAMES.to_h do |n|
    p = File.join(home, ".omos/personal-memory/bin", n)
    [n, [File.binread(p), File.stat(p).mode]]
  end

  # 包起來的理由：唯讀守衛若被觸發，錯誤是 EACCES 例外而不是 false。
  # 讓它變成一列具名的 FAIL，而不是整個 suite 中止。
  rolled, rollback_error = begin
    [v2_inst.rollback, nil]
  rescue StandardError => e
    [nil, "#{e.class}: #{e.message}"]
  end
  after = fingerprint.call
  host_files.each { |f| File.chmod(0o644, f) }
  launchers_after = OMOS::Installer::LAUNCHER_NAMES.to_h do |n|
    p = File.join(home, ".omos/personal-memory/bin", n)
    [n, [File.binread(p), File.stat(p).mode]]
  end
  current_target = File.readlink(File.join(home, ".omos/personal-memory/current"))

  C.check("rollback 後 current 指向前一版", File.basename(current_target)[0, 8],
          File.basename(current_target) == v1[:artifact_id])
  C.check("rollback 回傳值與實物一致", rolled.to_h[:artifact_id].to_s[0, 8],
          rolled.to_h[:artifact_id] == v1[:artifact_id] &&
          rolled.to_h[:previous_artifact_id] == v2[:artifact_id])
  # 驗收項 4：**不重寫 Host 設定**。Host 認的是固定 launcher，與版本無關。
  C.check("rollback 完全沒碰三個 Host 設定檔（內容／inode／mtime 皆不變）", "", before == after)
  C.check("Host 設定唯讀時 rollback 仍然成功（回退不依賴寫得進 Host）",
          rollback_error.to_s[0, 60], rollback_error.nil? && !rolled.nil?)
  C.check("rollback 完全沒碰 launcher（位元組與模式都不變）", "",
          launchers_before == launchers_after)
  C.check("rollback 後 receipt 交換 current／previous，可再切回去",
          v2_inst.receipt["previous_artifact_id"].to_s[0, 8],
          v2_inst.receipt["artifact_id"] == v1[:artifact_id] &&
          v2_inst.receipt["previous_artifact_id"] == v2[:artifact_id])
  # 不得靠重新下載或猜 SHA：目標只能是 receipt 記下的那一個，而且實物要在。
  C.check("rollback 的目標來自 receipt，且實物存在於 versions/", "",
          Dir.exist?(File.join(home, ".omos/personal-memory/versions", v1[:artifact_id])))

  # 切回去（rollback 是對稱的）
  v2_inst.rollback
  C.check("再 rollback 一次切回 v2", "",
          File.basename(File.readlink(File.join(home, ".omos/personal-memory/current"))) == v2[:artifact_id])

  # 目標實物被刪 → 明確失敗，不得重新下載、不得猜、更不得留在半途
  FileUtils.rm_rf(File.join(home, ".omos/personal-memory/versions", v1[:artifact_id]))
  code = begin
    v2_inst.rollback
    nil
  rescue OMOS::Installer::Failed => e
    e.code
  end
  C.check("previous artifact 不在了 → 明確失敗，不重新下載也不猜",
          code.to_s[0, 30], code.to_s.start_with?("ROLLBACK_ARTIFACT_MISSING"))
  C.check("失敗的 rollback 沒有動到 current", "",
          File.basename(File.readlink(File.join(home, ".omos/personal-memory/current"))) == v2[:artifact_id])
end

# --- Slice C repair-01 P1-1：同內容重裝不得把真正能回退的那一版 GC 掉 ---
#
# reviewer 實測重播：A → B → 再裝一次 B。receipt 正確寫著 current=B /
# previous=A，但 GC 的保留集是另外推導的（上一份 receipt 的 artifact_id，
# 同內容重裝時它就是 B），於是 A 被刪掉，隨後 rollback 撞 ARTIFACT_MISSING。
# 根因是**狀態有兩份來源**；修法是讓 GC 只認 receipt。
Dir.mktmpdir("omos-3c-a-gc-samecontent") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  store = File.join(dir, "p.db")
  src_a = File.join(dir, "src-a")
  src_b = File.join(dir, "src-b")
  FileUtils.cp_r(OMOS::Contract::ARTIFACT_ROOT, src_a)
  FileUtils.cp_r(src_a, src_b)
  File.write(File.join(src_b, "lib/omos/.build-variant"), "b\n")

  a = OMOS::Installer.new(home: home, product_root: src_a, store_path: store).install[:artifact_id]
  inst_b = OMOS::Installer.new(home: home, product_root: src_b, store_path: store)
  b = inst_b.install[:artifact_id]
  inst_b.install   # 同內容重裝：artifact identity 不變

  versions = Dir.children(File.join(home, ".omos/personal-memory/versions")).sort
  C.check("同內容重裝後 receipt 仍指得出 previous", inst_b.receipt["previous_artifact_id"].to_s[0, 8],
          inst_b.receipt["artifact_id"] == b && inst_b.receipt["previous_artifact_id"] == a)
  C.check("同內容重裝不得把 receipt 指得出的 previous GC 掉", versions.map { |i| i[0, 8] }.inspect,
          versions == [a, b].sort)
  rolled = begin
    inst_b.rollback
  rescue OMOS::Installer::Failed => e
    e.code
  end
  C.check("因此同內容重裝之後 rollback 仍然走得通",
          rolled.is_a?(Hash) ? rolled[:artifact_id][0, 8] : rolled.to_s[0, 40],
          rolled.is_a?(Hash) && rolled[:artifact_id] == a)

  # rollback 之後再裝一次，同一個根因不得從另一條路復活
  OMOS::Installer.new(home: home, product_root: src_b, store_path: store).install
  after = Dir.children(File.join(home, ".omos/personal-memory/versions")).sort
  C.check("rollback 後再重裝，保留集仍等於 receipt 的 current ＋ previous",
          after.map { |i| i[0, 8] }.inspect, after == [a, b].sort)
end

# --- Slice C repair-01 P1-2：rollback 自身也是交易 ---
#
# reviewer 實測：先 activate 再寫 receipt，receipt 寫不進去時 pointer 已經
# 切過去，留下 current=A 但 receipt 說 current=B 的分裂狀態——而 receipt 正是
# 下一次 rollback 與 GC 的唯一依據。
#
# 失敗點用注入的（Installer#rollback 的 fail_before_receipt），與
# install(fail_after:) 同一個做法：把 receipt 設成唯讀製造不出這個情境，
# 因為 receipt 是 temp + rename 寫的，rename 看的是目錄權限。
Dir.mktmpdir("omos-3c-a-rollback-txn") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  store = File.join(dir, "p.db")
  src_a = File.join(dir, "src-a")
  src_b = File.join(dir, "src-b")
  FileUtils.cp_r(OMOS::Contract::ARTIFACT_ROOT, src_a)
  FileUtils.cp_r(src_a, src_b)
  File.write(File.join(src_b, "lib/omos/.build-variant"), "b\n")

  a = OMOS::Installer.new(home: home, product_root: src_a, store_path: store).install[:artifact_id]
  inst_b = OMOS::Installer.new(home: home, product_root: src_b, store_path: store)
  b = inst_b.install[:artifact_id]

  hosts_before = Support::FakeHome.read_all(home)
  receipt_before = File.binread(inst_b.receipt_path)
  code = begin
    inst_b.rollback(fail_before_receipt: true)
    nil
  rescue OMOS::Installer::Failed => e
    e.code
  end
  current = File.basename(File.readlink(File.join(home, ".omos/personal-memory/current")))

  C.check("注入的 rollback 失敗確實發生", code.to_s, code == "ROLLBACK_INJECTED_FAILURE")
  C.check("rollback 失敗後 current 復原成失敗前的那一版（不留半套）",
          "#{current[0, 8]}（B=#{b[0, 8]} A=#{a[0, 8]}）", current == b)
  C.check("rollback 失敗後 receipt 位元組不變", "",
          File.binread(inst_b.receipt_path) == receipt_before)
  C.check("rollback 失敗後 pointer 與 receipt 仍然一致", "",
          current == inst_b.receipt["artifact_id"])
  C.check("rollback 失敗也不碰 Host 設定", "", Support::FakeHome.read_all(home) == hosts_before)

  # 復原後必須還能正常 rollback——復原不是把狀態弄壞後的遮羞布
  ok = inst_b.rollback
  C.check("復原後仍可正常 rollback", ok[:artifact_id][0, 8], ok[:artifact_id] == a)
end

# --- Slice C：rollback 的前提不足時一律明確失敗 ---
Dir.mktmpdir("omos-3c-a-rollback-guard") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  inst = OMOS::Installer.new(home: home, store_path: File.join(dir, "p.db"))

  no_receipt = begin
    inst.rollback
    nil
  rescue OMOS::Installer::Failed => e
    e.code
  end
  C.check("沒有 receipt 就 rollback → 明確失敗", no_receipt.to_s, no_receipt == "ROLLBACK_NO_RECEIPT")

  inst.install
  first_install = begin
    inst.rollback
    nil
  rescue OMOS::Installer::Failed => e
    e.code
  end
  C.check("第一次安裝後沒有前一版可回 → 明確失敗", first_install.to_s,
          first_install == "ROLLBACK_NO_PREVIOUS_ARTIFACT")

  # 同內容重裝：artifact identity 不變。此時 previous 不得被填成自己，
  # 否則 rollback 會變成「回報成功卻什麼都沒換」的 no-op。
  inst.install
  C.check("同內容重裝不會把 previous 填成自己", inst.receipt["previous_artifact_id"].inspect,
          inst.receipt["previous_artifact_id"].nil?)
end

# --- Slice C：versions/ GC 只留 current ＋ previous ---
Dir.mktmpdir("omos-3c-a-gc") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  store = File.join(dir, "p.db")
  ids = (1..3).map do |n|
    src = File.join(dir, "src-#{n}")
    FileUtils.cp_r(OMOS::Contract::ARTIFACT_ROOT, src)
    File.write(File.join(src, "lib/omos/.build-variant"), "gen#{n}\n")
    OMOS::Installer.new(home: home, product_root: src, store_path: store).install[:artifact_id]
  end
  kept = Dir.children(File.join(home, ".omos/personal-memory/versions")).sort
  C.check("裝三版後 versions/ 只留 current ＋ previous", "#{kept.size} 版",
          kept == ids.last(2).sort)
  C.check("留下的正是 receipt 指的那兩版", "",
          kept == [ids[-1], ids[-2]].sort)
end

# --- Slice C：workspace B —— 沒有 source checkout 的完整 standalone acceptance ---
#
# 這是本切片真正要證明的事：artifact 安裝完之後，把**整棵來源樹刪掉**，
# 產品的四個交付面（CLI／MCP／SessionStart／doctor）仍然完整可用。
# 來源樹是從 repo 複製到 tmpdir 的副本，所以刪除是真的刪，不是改路徑騙自己。
Dir.mktmpdir("omos-3c-a-standalone") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  store = File.join(dir, "p.db")
  src = File.join(dir, "workspace-a-src")
  FileUtils.cp_r(OMOS::Contract::ARTIFACT_ROOT, src)

  inst = OMOS::Installer.new(home: home, product_root: src, store_path: store)
  artifact_id = inst.install[:artifact_id]

  # 來源樹消失。從這裡開始，任何還依賴 repo／checkout 的東西都會壞。
  FileUtils.rm_rf(src)
  C.check("來源樹已實際刪除", "", !Dir.exist?(src))

  bin = File.join(home, ".omos/personal-memory/bin")
  env = { "OMOS_PERSONAL_MEMORY_STORE" => store,
          "OMOS_HOST" => "Claude Code", "OMOS_RUNTIME_SCOPE_MODE" => "EMPLOYEE_PRIVATE",
          "OMOS_SESSION_STATE_DIR" => File.join(dir, "state"),
          "CLAUDE_CODE_SESSION_ID" => "standalone-1" }

  # 1. CLI（透過 artifact 內的 exe，這是 launcher 實際 exec 的目標）
  cli = File.join(home, ".omos/personal-memory/current/exe/omos-personal-memory")
  cli_out, cli_err, cli_st = Open3.capture3(env, cli, "status", "--store", store)
  C.check("無 source checkout：CLI status 可用",
          cli_st.success? ? cli_out[/schema_version:.*/].to_s : cli_err[0, 80],
          cli_st.success? && cli_out.include?("schema_version"))

  # 2. SessionStart hook（走固定 launcher，authority 由 argv 注入）
  hook_out, hook_err, hook_st = Open3.capture3(env,
                                               File.join(bin, "omos-personal-memory-session-start"),
                                               "--host", "Claude Code",
                                               "--runtime-scope-mode", "EMPLOYEE_PRIVATE",
                                               stdin_data: JSON.generate(
                                                 { "session_id" => "standalone-1", "cwd" => dir,
                                                   "hook_event_name" => "SessionStart", "source" => "startup" }))
  C.check("無 source checkout：SessionStart hook 可用（走固定 launcher）",
          hook_st.success? ? "exit 0" : hook_err[0, 80], hook_st.success?)

  # 3. MCP server（同樣走固定 launcher），真的握手 → 寫 → 讀
  mcp_in, mcp_out, mcp_err, mcp_wait = Open3.popen3(env, File.join(bin, "omos-personal-memory-mcp"))
  rpc = lambda do |id, method, params|
    payload = { "jsonrpc" => "2.0", "id" => id, "method" => method }
    payload["params"] = params if params
    mcp_in.puts(JSON.generate(payload))
    mcp_in.flush
    line = mcp_out.gets
    line && JSON.parse(line)
  end
  init = rpc.call(1, "initialize", { "protocolVersion" => "2024-11-05", "capabilities" => {},
                                     "clientInfo" => { "name" => "standalone", "version" => "0" } })
  mcp_in.puts(JSON.generate({ "jsonrpc" => "2.0", "method" => "notifications/initialized", "params" => {} }))
  mcp_in.flush
  link = F.link_id("e1")
  wrote = rpc.call(2, "tools/call",
                   { "name" => "personal_memory_write",
                     "arguments" => { "kind" => "MemorySupportLink",
                                      "resource" => F.link_body(link, F.record_id("e2")),
                                      "idempotency_key" => "standalone-k1" } })
  wrote_body = JSON.parse(wrote.dig("result", "content", 0, "text"))
  read = rpc.call(3, "tools/call", { "name" => "personal_memory_read", "arguments" => {} })
  read_body = JSON.parse(read.dig("result", "content", 0, "text"))
  mcp_in.close
  mcp_wait.value
  mcp_err_text = begin
    mcp_err.read
  rescue IOError
    ""
  end
  C.check("無 source checkout：MCP server 完成 initialize",
          init&.dig("result", "serverInfo", "name").to_s,
          !init.nil? && init.dig("result", "protocolVersion")
                             .is_a?(String))
  C.check("無 source checkout：MCP 寫入成功（治理 evaluator 來自 artifact 內的副本）",
          wrote_body["status"].to_s, wrote_body["status"] == "WROTE")
  C.check("無 source checkout：MCP 讀得回剛寫的列", "",
          read_body.is_a?(Array) && read_body.any? { |r| r["row_id"] == link })
  C.check("無 source checkout：MCP server 沒有在 stderr 抱怨治理來源",
          mcp_err_text[0, 60], !mcp_err_text.include?("GOVERNANCE"))

  # 4. doctor —— 由 artifact 內的 CLI 自己跑，且探到的是固定 launcher
  doc_out, _doc_err, doc_st = Open3.capture3(env, cli, "doctor", "--home", home, "--store", store)
  C.check("無 source checkout：doctor 無 FAIL",
          doc_out[/doctor: .*/].to_s, doc_st.success? && !doc_out.include?("FAIL "))

  # 5. artifact identity 在來源樹消失後仍可重算（identity 是內容決定的）
  C.check("來源樹消失後 artifact identity 仍可重算且不變", artifact_id[0, 12],
          OMOS::Artifact.identity(File.join(home, ".omos/personal-memory/versions", artifact_id)) == artifact_id)
end

# ===========================================================================
# B Doctor 與失敗診斷
# ===========================================================================
C.group = "B"
Dir.mktmpdir("omos-3c-b") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  proj = File.join(dir, "proj")
  FileUtils.mkdir_p(proj)
  store = File.join(dir, "p.db")
  inst = OMOS::Installer.new(home: home, store_path: store)

  # 未安裝：三種結果必須分得開
  pre = OMOS::Doctor.new(home: home, store_path: store, cwd: proj).run.to_h { |r| [r.id, r.status] }
  C.check("未安裝時：程序叫得起來（PROCESS_OK）", pre["mcp_handshake"], pre["mcp_handshake"] == "OK")
  C.check("未安裝時：設定不存在（CONFIG 缺）", pre["claude_code_mcp_visible"], pre["claude_code_mcp_visible"] == "FAIL")
  C.check("未安裝時：store 不能用（STORE 缺）", pre["store_exists"], pre["store_exists"] == "FAIL")
  C.check("三者確實獨立（程序 OK 但另兩者 FAIL）", "",
        pre["mcp_handshake"] == "OK" && pre["claude_code_mcp_visible"] == "FAIL" && pre["store_exists"] == "FAIL")

  inst.install
  post = OMOS::Doctor.new(home: home, store_path: store, cwd: proj).run
  post_fail = post.select { |r| r.status == "FAIL" }
  post_warn = post.select { |r| r.status == "WARN" }
  C.check("安裝後無任何 FAIL",
        "#{post.count(&:ok?)} OK / #{post_warn.size} WARN / #{post_fail.size} FAIL", post_fail.empty?)
  C.check("WARN 只出現在「無法觀測／未經 Host 驗證」這兩類，且照實回報",
        post_warn.map(&:id).sort.inspect,
        post_warn.map(&:id).sort == ["claude_code_session_start_hook_present", "codex_not_delivered"])

  # 被同名專案設定遮蔽 → 必須明確失敗
  File.write(File.join(proj, ".mcp.json"),
             JSON.generate({ "mcpServers" => { "omos.personal-memory" => { "command" => "hijack" } } }))
  shadowed = OMOS::Doctor.new(home: home, store_path: store, cwd: proj).run
                         .find { |r| r.id == "claude_code_no_shadow" }
  C.check("專案 .mcp.json 同名遮蔽被偵測", shadowed.detail[0, 30], shadowed.status == "FAIL")

  # 即使 payload 與本產品完全相同也必須報（看的是 id 與優先序，不是內容）
  File.write(File.join(proj, ".mcp.json"),
             JSON.generate({ "mcpServers" => { "omos.personal-memory" =>
                             { "command" => inst.mcp_command, "transport" => "STDIO" } } }))
  same_payload = OMOS::Doctor.new(home: home, store_path: store, cwd: proj).run
                             .find { |r| r.id == "claude_code_no_shadow" }
  C.check("payload 完全相同的遮蔽仍被偵測", same_payload.detail[0, 30], same_payload.status == "FAIL")
  FileUtils.rm_f(File.join(proj, ".mcp.json"))

  # hook 被移除 → 必須明確失敗（而不是靠 caller 自報健康）
  settings = JSON.parse(File.read(File.join(home, ".claude/settings.json")))
  settings["hooks"]["SessionStart"] = []
  File.write(File.join(home, ".claude/settings.json"), "#{JSON.pretty_generate(settings)}\n")
  hook_gone = OMOS::Doctor.new(home: home, store_path: store, cwd: proj).run
                          .find { |r| r.id == "claude_code_session_start_hook_present" }
  C.check("SessionStart hook 被移除會明確失敗", hook_gone.detail[0, 30], hook_gone.status == "FAIL")

  # executable 不存在 → 必須明確失敗。
  # Slice A：doctor 已安裝時探的是**固定 launcher**，所以製造方式改成把
  # launcher 移走（並給一個不存在的 product_root，讓未安裝時的後備也落空）。
  launcher = File.join(home, ".omos/personal-memory/bin/omos-personal-memory-mcp")
  FileUtils.mv(launcher, "#{launcher}.away")
  missing = OMOS::Doctor.new(home: home, store_path: store, cwd: proj,
                             product_root: File.join(dir, "nowhere")).run
                        .find { |r| r.id == "mcp_executable" }
  C.check("MCP executable 不存在會明確失敗", missing.detail[0, 30], missing.status == "FAIL")
  FileUtils.mv("#{launcher}.away", launcher)

  # Slice A 新增：launcher 還在、但 current 指向的 artifact 不見了。
  # 這種「殼還在、實體沒了」的狀態必須被抓到——不得因為 launcher 可執行就
  # 判成健康。
  current = File.join(home, ".omos/personal-memory/current")
  target = File.readlink(current)
  FileUtils.mv(target, "#{target}.away")
  broken = OMOS::Doctor.new(home: home, store_path: store, cwd: proj).run
                       .find { |r| r.id == "mcp_handshake" }
  C.check("current 指向的 artifact 消失時 doctor 明確失敗", broken.detail[0, 40],
          broken.status == "FAIL")
  FileUtils.mv("#{target}.away", target)

  # SQLite 版本比較：低於修復版本必須判為不安全
  s = OMOS::Store.new(store)
  C.check("SQLite 版本比較：3.51.0 判為不安全", "",
        !s.version_at_least?("3.51.0", OMOS::Store::WAL_RESET_FIX))
  C.check("SQLite 版本比較：3.51.3 判為安全", "",
        s.version_at_least?("3.51.3", OMOS::Store::WAL_RESET_FIX))
end

# ===========================================================================
# C 同一 Host 的兩個並行 session（同 cwd）與跨專案
# ===========================================================================
#
# repair-02 之前這裡是「Codex 寫、Claude Code 讀」的跨 Host 測試。Codex 目前
# 沒有官方管道讓 MCP server 獨立得知 native session id，一律 fail closed
# （見 3b「Codex 目前無可信 native session 管道」），因此跨 Host 的 MCP 讀寫
# 現在只能由一個 Host 示範。改用兩個**並行的 Claude Code session**、**同一個
# cwd**——這正是 repair-02 P1-1 要修的情境（cwd 不是 session identity，同
# cwd 的兩個並行 session 不得互相覆蓋或誤讀對方的 binding）。
C.group = "C"
Dir.mktmpdir("omos-3c-c") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  store = File.join(dir, "shared.db")
  OMOS::Installer.new(home: home, store_path: store).install

  proj_a = File.join(dir, "projA")
  proj_b = File.join(dir, "projB")
  FileUtils.mkdir_p(proj_a)
  FileUtils.mkdir_p(proj_b)

  # 兩個並行 session 跑真的 SessionStart hook（真 stdin 形狀）落地 session 事實；
  # 同一個 cwd、同一個 state_dir，只有 session_id 不同——測試不捏造 binding，
  # MCP server 自己從 env + session 記錄建構。
  state_dir = File.join(dir, "state")
  _o1, _e1, st1 = Support.run_session_start(host: "Claude Code", session_id: "claude-c1",
                                            cwd: proj_a, state_dir: state_dir)
  _o2, _e2, st2 = Support.run_session_start(host: "Claude Code", session_id: "claude-c2",
                                            cwd: proj_a, state_dir: state_dir)
  C.check("兩個並行 session 的 SessionStart hook 都成功", "#{st1.exitstatus}/#{st2.exitstatus}",
          st1.success? && st2.success?)

  c1 = Support::MCPClient.new(store, host: "Claude Code", cwd: proj_a, state_dir: state_dir,
                              session_id: "claude-c1")
  c2 = Support::MCPClient.new(store, host: "Claude Code", cwd: proj_a, state_dir: state_dir,
                              session_id: "claude-c2")

  l1 = "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000c1"
  r1 = "urn:omos:personal-memory:record:01900000-0000-7000-8000-0000000000c2"
  l2 = "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000c3"
  r2 = "urn:omos:personal-memory:record:01900000-0000-7000-8000-0000000000c4"

  # session 1 寫 → session 2 讀同一個 store（同 cwd，不同 native session）
  wrote = c1.write("MemorySupportLink", F.link_body(l1, r1), "k-c1")
  seen_by_c2 = c2.read
  C.check("session 1 寫入成功", wrote["status"].to_s, wrote["status"] == "WROTE")
  C.check("session 2 從同一個 store 讀到 session 1 寫的列", "",
        seen_by_c2.is_a?(Array) && seen_by_c2.any? { |r| r["row_id"] == l1 })

  # session 2 寫 → session 1 讀（反向）
  wrote2 = c2.write("MemorySupportLink", F.link_body(l2, r2), "k-c2")
  seen_by_c1 = c1.read
  C.check("session 2 寫入成功", wrote2["status"].to_s, wrote2["status"] == "WROTE")
  C.check("session 1 反向讀到 session 2 寫的列", "",
        seen_by_c1.is_a?(Array) && seen_by_c1.any? { |r| r["row_id"] == l2 })
  C.check("兩邊看到的是同一份資料，且各自 binding 沒被同 cwd 的另一個 session 覆蓋", "",
        seen_by_c1.map { |r| r["row_id"] }.sort == (seen_by_c2.map { |r| r["row_id"] } + [l2]).sort)

  # 同一 cwd 換成第三個「從沒跑過 hook」的 session：不得誤讀到前兩個仍在跑的
  # session 留下的任何一份 identity——沒有自己的記錄就是沒有，一律 fail closed
  # （鍵是 (host, native_session_id)，不是 cwd，結構上就不會撿到別人的檔案；
  # 這裡是明確驗證這一點）。
  c3 = Support::MCPClient.new(store, host: "Claude Code", cwd: proj_a, state_dir: state_dir,
                              session_id: "claude-c3-never-started")
  c3_res = c3.read
  c3.close
  C.check("同 cwd 換成沒跑過 hook 的第三個 session，不會讀到其他 session 的 identity",
        c3_res.is_a?(Hash) ? c3_res["code"] : c3_res.to_s,
        c3_res.is_a?(Hash) && c3_res["code"] == "MCP_NO_SESSION_RECORD")

  # 跨專案：切到 projB 不得擴權
  widened = begin
    OMOS::SessionStart.produce(host: "Claude Code", native_session_id: "claude-c4", cwd: proj_b,
                               project_ref: "urn:omos:project:b", runtime_scope_mode: "EMPLOYEE_PRIVATE",
                               project_visibility_scope: "WORK_CONTEXT_PARTICIPANTS")
    nil
  rescue OMOS::SessionStart::Refused => e
    e.code
  end
  C.check("切換專案不得擴權", widened.to_s, widened == "HBV1_PROJECT_SCOPE_WIDENS_BASELINE")

  narrowed = OMOS::SessionStart.produce(host: "Claude Code", native_session_id: "claude-c5", cwd: proj_b,
                                        project_ref: "urn:omos:project:b",
                                        runtime_scope_mode: "EMPLOYEE_PRIVATE",
                                        project_visibility_scope: "SELF_ONLY")
  C.check("切換專案可維持同等收窄", narrowed["effective_scope"], narrowed["effective_scope"] == "SELF_ONLY")
  C.check("切換專案不重建 store", "", File.exist?(store))

  # 週期：同一 review period 跨並行 session 仍是同一身分，且只能收一次 terminal
  period = "urn:omos:personal-memory:review-period:2026-W38"
  item = "urn:omos:personal-memory:candidate:01900000-0000-7000-8000-0000000000d1"
  first = c1.closeout(F.closeout(period, item, "FAILED", "SCHEDULED"))
  second = c2.closeout(F.closeout(period, item, "COMPLETE", "RETRY"))
  third = c1.closeout(F.closeout(period, item, "NO_PROMOTION", "RETRY"))
  C.check("session 1 開的週期，session 2 可以接續收尾", second["status"].to_s,
        first["status"] == "COMMITTED" && second["status"] == "COMMITTED")
  C.check("第二次 terminal closeout 被拒", third["code"].to_s,
        third["status"] == "REJECTED" && third["code"] == "PMR_CLOSEOUT_FAILS_WEEKLY_CYCLE_CONTRACT")

  # promotion identity 在 retry 間漂移 → 被拒
  drift_payload = F.closeout("#{period}-b", item, "COMPLETE", "SCHEDULED")
  c1.closeout(drift_payload)
  drifted = F.closeout("#{period}-b", item, "COMPLETE", "RETRY")
  drifted["item_dispositions"][item]["promotion_idempotency_key"] = "pk-999"
  drift_res = c2.closeout(drifted)
  C.check("跨並行 session 的 retry 換掉 promotion identity 被拒", drift_res["code"].to_s,
        drift_res["status"] == "REJECTED")

  # 重啟：關掉兩個進程再開，重放同一筆寫入不得產生第二列
  c1.close
  c2.close
  db = SQLite3::Database.new(store)
  rows_before_restart = db.get_first_value("SELECT COUNT(*) FROM memory_rows")
  terminal_before = db.get_first_value("SELECT COUNT(*) FROM closeouts WHERE is_terminal = 1")
  db.close

  c1_restarted = Support::MCPClient.new(store, host: "Claude Code", cwd: proj_a, state_dir: state_dir,
                                        session_id: "claude-c1")
  replay = c1_restarted.write("MemorySupportLink", F.link_body(l1, r1), "k-c1")
  c1_restarted.close
  db = SQLite3::Database.new(store)
  rows_after_restart = db.get_first_value("SELECT COUNT(*) FROM memory_rows")
  terminal_after = db.get_first_value("SELECT COUNT(*) FROM closeouts WHERE is_terminal = 1")
  db.close
  C.check("重啟後重放同一筆是 no-op", replay["status"].to_s, replay["status"] == "REPLAYED")
  C.check("重啟不產生第二列", "#{rows_before_restart}→#{rows_after_restart}",
        rows_before_restart == rows_after_restart)
  C.check("重啟不產生第二次 terminal closeout", "#{terminal_before}→#{terminal_after}",
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
  C.check("install→upgrade→uninstall→reinstall 後資料不變",
        "rows=#{rows_final} terminal=#{terminal_final}",
        rows_final == rows_after_restart && terminal_final == terminal_after)
end


# --- qualification key 修正（CARD-EMEM11-QUALIFICATION-KEY-FIX-20260921）---
#
# 實測觸發：同事機 darwin24、本機 darwin25，同一包 artifact、live probe 都過，
# 但同事端每次執行都印 UNQUALIFIED_RUNTIME_PROFILE。host_os 是「編這顆 Ruby
# 的機器」的 darwin build 版本，隨 Homebrew bottle 而異，與我們的原生擴充載
# 不載得動沒有因果關係。把它放進比對等於「一個 macOS build 一列」。
#
# Owner 2026-09-21 裁決：比對 key = os_family + host_cpu + ruby_engine +
# ruby_abi + live native probes；host_os 降為 observation；
# native_linkage_digest 改驗 artifact integrity，不參與機器判定。
Dir.mktmpdir("omos-3c-a-qualkey") do |dir|
  root = OMOS::Contract::ARTIFACT_ROOT

  run = lambda do |src|
    o, e, st = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(root, "Gemfile") },
                              RbConfig.ruby, "-rbundler/setup",
                              "-I#{File.join(root, "lib")}", "-e", src)
    [o.strip, e.strip, st]
  end

  # (1) host_os 不在比對 key 內；它仍被記錄為 observation
  out, = run.call(<<~RUBY)
    require "omos/runtime_profile"
    k = OMOS::RuntimeProfile.qualification_key
    o = OMOS::RuntimeProfile.observation
    puts [k.keys.sort.join(","), o.keys.sort.join(",")].join("|")
  RUBY
  keys, obs = out.split("|", 2)
  C.check("qualification key 不含 host_os 與 linkage digest", keys.to_s,
          keys == "host_cpu,os_family,ruby_abi,ruby_engine")
  C.check("host_os 與 linkage digest 降為 observation", obs.to_s,
          obs == "host_os,native_linkage_digest")

  # (2) darwin99 mutation：只改 OS version，判定結果不得改變。
  #     這是本次修正的主要鑑別力反證——舊實作會在這裡轉成 UNQUALIFIED。
  mutated = <<~RUBY
    require "rbconfig"
    RbConfig::CONFIG["host_os"] = "darwin99"
    require "omos/runtime_profile"
    puts OMOS::RuntimeProfile.assert_supported!
  RUBY
  out2, err2, st2 = run.call(mutated)
  C.check("host_os 換成從未見過的 darwin99，仍判為 QUALIFIED", out2.to_s,
          st2.success? && out2 == "QUALIFIED" && !err2.include?("UNQUALIFIED"))

  # (3) 但 os_family 真的不同（非 darwin）就不該再宣稱 qualified
  out3, = run.call(<<~RUBY)
    require "rbconfig"
    RbConfig::CONFIG["host_os"] = "linux-gnu"
    require "omos/runtime_profile"
    puts OMOS::RuntimeProfile.assert_supported!
  RUBY
  C.check("os_family 真的不同（linux）→ 不得宣稱 qualified", out3.to_s,
          out3 == "UNQUALIFIED_RUNTIME_PROFILE")

  # (4) linkage digest 對同一包 artifact 恆為同值 → 零機器鑑別力，
  #     因此它只能驗 artifact integrity
  declared = JSON.parse(File.read(File.join(root, "runtime-profile.json")))
  C.check("linkage digest 已移出 qualified_profiles", "",
          declared.fetch("qualified_profiles").none? { |p| p.key?("native_linkage_digest") })
  C.check("linkage digest 改列為 artifact integrity 欄位",
          declared["artifact_native_linkage_digest"].to_s[0, 12],
          declared["artifact_native_linkage_digest"].to_s.length == 64)

  # (5) artifact integrity 不符 → fail closed（不是降級成 UNQUALIFIED）
  bad = File.join(dir, "bad-profile.json")
  File.write(bad, JSON.generate(declared.merge("artifact_native_linkage_digest" => "0" * 64)))
  out5, err5, st5 = run.call(<<~RUBY)
    require "omos/runtime_profile"
    OMOS::RuntimeProfile.define_singleton_method(:profile_document) do
      JSON.parse(File.read(#{bad.dump}))
    end
    puts OMOS::RuntimeProfile.assert_supported!
  RUBY
  C.check("artifact linkage digest 不符 → fail closed（exit 78）",
          "exit=#{st5.exitstatus}", st5.exitstatus == 78)
  C.check("且指出是 artifact 完整性問題，不是機器不符",
          (out5 + err5)[0, 60],
          (out5 + err5).include?("OMOS_ARTIFACT_LINKAGE_DIGEST_MISMATCH"))

  # (5b) review P1-1：宣告缺失／格式錯也必須 fail closed。
  #      原本 `return if declared.nil?`，於是把宣告刪掉就能關掉這道 guard。
  [["宣告整個刪掉", declared.reject { |k, _| k == "artifact_native_linkage_digest" },
    "OMOS_ARTIFACT_LINKAGE_DIGEST_MISSING"],
   ["宣告是空字串", declared.merge("artifact_native_linkage_digest" => ""),
    "OMOS_ARTIFACT_LINKAGE_DIGEST_MALFORMED"],
   ["宣告長度不足", declared.merge("artifact_native_linkage_digest" => "abc123"),
    "OMOS_ARTIFACT_LINKAGE_DIGEST_MALFORMED"],
   ["宣告含大寫", declared.merge("artifact_native_linkage_digest" => "A" * 64),
    "OMOS_ARTIFACT_LINKAGE_DIGEST_MALFORMED"],
   ["宣告不是字串", declared.merge("artifact_native_linkage_digest" => 12_345),
    "OMOS_ARTIFACT_LINKAGE_DIGEST_MALFORMED"]].each_with_index do |(label, doc, code), i|
    f = File.join(dir, "integrity-#{i}.json")
    File.write(f, JSON.generate(doc))
    o, e, st = run.call(<<~RUBY)
      require "omos/runtime_profile"
      OMOS::RuntimeProfile.define_singleton_method(:profile_document) do
        JSON.parse(File.read(#{f.dump}))
      end
      puts OMOS::RuntimeProfile.assert_supported!
    RUBY
    C.check("artifact integrity #{label} → fail closed（#{code}）",
            "exit=#{st.exitstatus}",
            st.exitstatus == 78 && (o + e).include?(code))
  end

  # (5c) review P1-2 裁決（Owner 2026-09-21）：兩層要分清楚。
  #
  #   Compatibility / Safety gate —— 實際執行不相容 → fail closed
  #     candidate Ruby ABI 與 artifact vendor ABI 不符／native extension 載不動／
  #     宣告的 native linkage 解析不到
  #
  #   Qualification policy —— key／觀測 metadata 不匹配但 live probe 全過
  #     → UNQUALIFIED_RUNTIME_PROFILE，不阻擋
  #
  # reviewer 前一輪把 RbConfig 的 host_cpu／ruby_version 改掉當成「真的不相容」，
  # 測法不夠準：那只改了回報 metadata，底下仍是原本那支 Ruby、原本那些 arm64
  # extension，所以 live probe 當然照樣成功。兩組各自測。

  # 第一組：metadata-only mismatch → UNQUALIFIED（不得誤當成執行不相容）
  [["host_cpu 回報值不符", 'RbConfig::CONFIG["host_cpu"] = "x86_64"'],
   ["ruby_abi 回報值不符", 'RbConfig::CONFIG["ruby_version"] = "9.9.9"'],
   ["兩者同時不符", 'RbConfig::CONFIG["host_cpu"] = "x86_64"; RbConfig::CONFIG["ruby_version"] = "9.9.9"']]
    .each do |label, mutation|
    o, _, st = run.call(<<~RUBY)
      require "rbconfig"
      #{mutation}
      require "omos/runtime_profile"
      puts OMOS::RuntimeProfile.assert_supported!
    RUBY
    C.check("metadata-only：#{label} → UNQUALIFIED 而非 fail closed", o.to_s,
            st.success? && o == "UNQUALIFIED_RUNTIME_PROFILE")
  end

  # 第二組：實際 runtime incompatibility → exit 78
  #
  # (a) candidate Ruby 的 ABI 與 artifact vendor ABI 不符——由 pinned-ruby.sh
  #     在**進 Ruby 之前**擋下，這才是真正的 ABI 不相容
  abi_out, abi_err, abi_st = Open3.capture3(
    { "OMOS_RUBY" => "/usr/bin/ruby" },
    File.join(root, "exe/omos-personal-memory"), "status"
  )
  C.check("實際不相容：candidate Ruby ABI 與 artifact vendor ABI 不符 → exit 78",
          "exit=#{abi_st.exitstatus}",
          abi_st.exitstatus == 78 && (abi_out + abi_err).include?("ABI"))

  # (b) native extension 真的載不動
  o_b, e_b, st_b = run.call(<<~RUBY)
    require "omos/runtime_profile"
    OMOS::RuntimeProfile.define_singleton_method(:manifest) do
      [{ "extension" => "bigdecimal", "require" => "omos_no_such_extension",
         "non_system_libraries" => [] }]
    end
    puts OMOS::RuntimeProfile.assert_supported!
  RUBY
  C.check("實際不相容：native extension 載不動 → exit 78", "exit=#{st_b.exitstatus}",
          st_b.exitstatus == 78 && (o_b + e_b).include?("OMOS_NATIVE_REQUIRE_FAILED"))

  # (c) 宣告的 native linkage 解析不到（與 (6) 同一類，這裡是分組後的對照）
  o_c, e_c, st_c = run.call(<<~RUBY)
    require "omos/runtime_profile"
    OMOS::RuntimeProfile.define_singleton_method(:manifest) do
      [{ "extension" => "bigdecimal", "require" => "bigdecimal",
         "non_system_libraries" => ["/nonexistent/libruby.3.4.dylib"] }]
    end
    puts OMOS::RuntimeProfile.assert_supported!
  RUBY
  C.check("實際不相容：宣告的 native linkage 解析不到 → exit 78", "exit=#{st_c.exitstatus}",
          st_c.exitstatus == 78 && (o_c + e_c).include?("OMOS_NATIVE_DEPENDENCY_UNRESOLVED"))

  # (6) 移除 host_os 沒有削弱真正的守門人：live probe 仍然 fail closed
  out6, err6, st6 = run.call(<<~RUBY)
    require "omos/runtime_profile"
    OMOS::RuntimeProfile.define_singleton_method(:manifest) do
      [{ "extension" => "bigdecimal", "require" => "bigdecimal",
         "non_system_libraries" => ["/nonexistent/libruby.3.4.dylib"] }]
    end
    puts OMOS::RuntimeProfile.assert_supported!
  RUBY
  C.check("live linkage 真的不符 → 仍 fail closed", "exit=#{st6.exitstatus}",
          st6.exitstatus == 78 &&
          (out6 + err6).include?("OMOS_NATIVE_DEPENDENCY_UNRESOLVED"))
end

# --- Slice A｜Personal Inbox / manual capture ---
#
# 契約早就宣告 manual_capture，缺的是使用面：`write` 只收組好的 resource JSON，
# 一般人手上是一個 .md。這一組驗的是「檔案 → 既有治理物件鏈」這條翻譯，
# 以及它在重放、失敗與來源檔消失時的行為。
Dir.mktmpdir("omos-3c-a-inbox") do |dir|
  C.group = "A"
  require "omos/inbox"

  cli_surface = OMOS::Runtime::SURFACES[:cli]
  store = File.join(dir, "inbox.db")
  owner = Support::Fixtures::EMP
  src = File.join(dir, "note.md")
  File.write(src, "# WAL 決策\n\n改用 WAL 模式以支援並行讀取。\n")

  rt = OMOS::Runtime.open(store)
  imp = lambda do |path, kind|
    OMOS::Inbox.import(rt, store, path, memory_kind: kind, owner_ref: owner, tenant_id: "t-acme")
  end

  # (1) content-addressed snapshot，且追得到 Evidence / SourceAnchor ref
  r1 = imp.call(src, "DECISION")
  digest = r1[:content_sha256]
  snap = OMOS::EvidenceSnapshot.dir_for(store, digest)
  env = JSON.parse(File.read(File.join(snap, "envelope.json")))
  C.check("匯入產生 content-addressed evidence snapshot", digest[0, 12],
          Dir.exist?(snap) && Digest::SHA256.hexdigest(File.binread(File.join(snap, "raw.bin"))) == digest)
  C.check("snapshot 保留原始檔名、capture time 與 admission metadata",
          env.dig("origin", "original_filename").to_s,
          env.dig("origin", "original_filename") == "note.md" &&
          !env["captured_at"].to_s.empty? && env.dig("admission", "capture_scope") == "EMPLOYEE_PRIVATE")
  C.check("candidate 的 support 追得到 Evidence 與 SourceAnchor ref", "",
          env["evidence_ref"].start_with?("urn:omos:evidence:") &&
          env["source_anchor_ref"].start_with?("urn:omos:source-anchor:"))

  # (2) 走既有 evaluator 寫成 SupportLink + Candidate(PROPOSED)，沒有 acceptance authority
  rows = rt.read_rows(surface: cli_surface)
  cand = rows.find { |r| r[:row_id] == r1[:candidate_id] }[:resource]
  link = rows.find { |r| r[:row_id] == r1[:link_id] }[:resource]
  C.check("匯入產生 MemorySupportLink ＋ PersonalMemoryCandidate", r1[:status],
          r1[:status] == "CANDIDATE_PROPOSED" && !cand.nil? && !link.nil?)
  C.check("candidate 初始狀態是 PROPOSED", cand["candidate_status"],
          cand["candidate_status"] == "PROPOSED")
  C.check("匯入不得自帶 verification／acceptance 權威",
          "#{cand.dig("governance", "verification_status")}／#{cand.dig("governance", "acceptance_status")}",
          cand.dig("governance", "verification_status") == "NOT_RUN" &&
          cand.dig("governance", "acceptance_status") == "PENDING")
  C.check("匯入不得建立 PersonalMemoryRecord", "",
          rows.none? { |r| r[:kind] == "PersonalMemoryRecord" })
  C.check("support link 的 target_ref 指回 candidate", link["target_ref"].to_s[-12, 12].to_s,
          link["target_ref"] == r1[:candidate_id])

  # (3) 原始來源檔被移走，support 仍可由 managed snapshot 驗證
  FileUtils.rm_f(src)
  C.check("原始檔移走後 evidence 仍可驗證", "",
          !File.exist?(src) && OMOS::EvidenceSnapshot.verifiable?(store, digest))
  C.check("原始檔移走後 candidate 仍在且 support 未失效", "",
          rt.read_rows(surface: cli_surface).any? { |r| r[:row_id] == r1[:candidate_id] })

  # (4) 重放三次不得增生
  File.write(src, "# WAL 決策\n\n改用 WAL 模式以支援並行讀取。\n")
  before = rt.read_rows(surface: cli_surface).size
  3.times { imp.call(src, "DECISION") }
  after = rt.read_rows(surface: cli_surface).size
  snaps = Dir.children(OMOS::EvidenceSnapshot.root(store))
  C.check("同內容重放 3 次不得新增 row", "#{before}→#{after}", before == after)
  C.check("同內容重放 3 次不得新增 snapshot", snaps.size.to_s, snaps.size == 1)

  # (5) 失敗一律 fail loud，且不得留下半套
  [["不支援的格式", File.join(dir, "x.pdf"), "DECISION", "INBOX_UNSUPPORTED_FORMAT"],
   ["讀不到的檔", File.join(dir, "missing.md"), "DECISION", "INBOX_SOURCE_UNREADABLE"],
   ["空檔", File.join(dir, "empty.md"), "DECISION", "INBOX_SOURCE_EMPTY"],
   ["非 UTF-8", File.join(dir, "bad.txt"), "DECISION", "INBOX_SOURCE_NOT_UTF8"],
   ["預設不長存的 kind", File.join(dir, "ok.md"), "CURRENT_TASK_STATUS",
    "INBOX_MEMORY_KIND_NOT_LONG_LIVED"],
   ["不存在的 kind", File.join(dir, "ok.md"), "NOPE", "INBOX_MEMORY_KIND_UNKNOWN"]].each do |label, path, kind, code|
    File.write(File.join(dir, "x.pdf"), "%PDF-1.4\n")
    File.write(File.join(dir, "empty.md"), "")
    File.binwrite(File.join(dir, "bad.txt"), "\xff\xfe\x00bad".b)
    File.write(File.join(dir, "ok.md"), "# ok\n")
    rows_before = rt.read_rows(surface: cli_surface).size
    actual = begin
      imp.call(path, kind)
      nil
    rescue OMOS::EvidenceSnapshot::Rejected => e
      e.code
    end
    rows_after = rt.read_rows(surface: cli_surface).size
    snaps_before = Dir.children(OMOS::EvidenceSnapshot.root(store)).size
    C.check("匯入失敗：#{label} → #{code}，且不留半套", actual.to_s,
            actual == code && rows_before == rows_after)
    C.check("匯入失敗：#{label} 不得收進未分類的 snapshot", snaps_before.to_s,
            snaps_before == 1)
  end

  # (6) 缺 memory_kind：保留 snapshot、明確回 NEEDS_CANDIDATE_INPUT，不得猜著補成 Record
  pending_src = File.join(dir, "pending.md")
  File.write(pending_src, "# 尚未分類\n\n這段還沒決定 memory_kind。\n")
  before2 = rt.read_rows(surface: cli_surface).size
  r2 = imp.call(pending_src, nil)
  C.check("缺 memory_kind → NEEDS_CANDIDATE_INPUT", r2[:status],
          r2[:status] == "NEEDS_CANDIDATE_INPUT")
  C.check("缺 memory_kind 時 snapshot 仍保留", "",
          OMOS::EvidenceSnapshot.verifiable?(store, r2[:content_sha256]))
  C.check("缺 memory_kind 時不得寫入任何一列", "#{before2}→#{rt.read_rows(surface: cli_surface).size}",
          rt.read_rows(surface: cli_surface).size == before2)

  # (7) 鑑別力反證（卡片 Regression 第 16 項第一條）：
  #     繞過 managed snapshot、只引用原始路徑的 support 必須被 gate 擋下。
  bypass = OMOS::Inbox.link_body(
    OMOS::EvidenceSnapshot.link_ref("f" * 64), Support::Fixtures::CAND,
    env.merge("evidence_ref" => "file://#{File.expand_path(pending_src)}")
  )
  C.expect_rejected("繞過 managed snapshot、只引用原始路徑 → gate 擋下",
                    "PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT", rt.store) do
    rt.write_row(kind: "MemorySupportLink", resource: bypass,
                 idempotency_key: "bypass-1", surface: cli_surface)
  end

  # (7b) 匯入若偷帶 acceptance 權威，既有 evaluator 必須當場擋下。
  #      這條讓「匯入不得自帶 verification／acceptance」成為**可反證**的斷言：
  #      少了它，把 governance 改成 PASS/ACCEPTED 只會讓測試整個炸掉，
  #      而不是某一項轉紅。
  forged = OMOS::Inbox.candidate_body(
    OMOS::EvidenceSnapshot.candidate_ref("e" * 64), r1[:link_id], env, "DECISION", store
  )
  forged["governance"] = forged["governance"].merge("verification_status" => "PASS",
                                                    "acceptance_status" => "ACCEPTED")
  C.expect_rejected("匯入偷帶 acceptance 權威 → evaluator 當場擋下",
                    "PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT", rt.store) do
    rt.write_row(kind: "PersonalMemoryCandidate", resource: forged,
                 idempotency_key: "forged-1", surface: cli_surface)
  end

  # (8) inbox list 由既有事實重算，不新增 table
  entries = OMOS::Inbox.entries(rt, store, surface: cli_surface)
  tables = rt.store.db.execute("SELECT name FROM sqlite_master WHERE type='table'").flatten
  C.check("inbox list 同時列出已成案與待補的匯入", entries.size.to_s,
          entries.size == 2 &&
          entries.map { |e| e["candidate_status"] }.sort == %w[NEEDS_CANDIDATE_INPUT PROPOSED])
  C.check("不得新增 inbox／queue table", tables.sort.inspect[0, 60],
          tables.none? { |t| t.to_s.match?(/inbox|queue/i) })

  rt.store.close
  C.group = nil
end

# --- Slice A｜個人身分解析（Owner 裁決 2026-09-21）---
#
#   明確參數 > install receipt 保存的 > （測試／暫時相容）環境變數 > fail closed
#
# 為什麼不從 SessionStart 推：HostSessionBinding 只有 executor_ref／
# executor_session_ref／cwd／project_ref／effective_scope，沒有
# employee_owner_ref 與 tenant_id。從那裡硬推等於造一份假的 mapping。
Dir.mktmpdir("omos-3c-a-identity") do |dir|
  C.group = "A"
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  exe = File.join(OMOS::Contract::ARTIFACT_ROOT, "exe/omos-personal-memory")
  note = File.join(dir, "note.md")
  File.write(note, "# 決策\n\n改用 WAL。\n")
  receipt = File.join(home, ".omos/personal-memory/install-receipt.json")

  cli = lambda do |args, env = {}|
    o, e, st = Open3.capture3({ "HOME" => home }.merge(env), exe, *args)
    [o, e, st]
  end
  identity = -> { (JSON.parse(File.read(receipt))["personal_identity"] || {}) }

  # (1) install 帶身分 → 寫進 receipt
  cli.call(["install", "--home", home, "--owner", Support::Fixtures::EMP, "--tenant", "t-acme"])
  C.check("install --owner/--tenant 寫進 receipt 的 personal_identity",
          identity.call["employee_owner_ref"].to_s,
          identity.call == { "employee_owner_ref" => Support::Fixtures::EMP,
                             "tenant_id" => "t-acme" })

  # (2) 之後裸跑 import 不必再輸入身分
  out2, _, st2 = cli.call(["import", note, "--memory-kind", "DECISION"])
  C.check("設定過身分後 `import FILE` 裸跑即可", out2.lines.first.to_s.strip,
          st2.success? && out2.include?("CANDIDATE_PROPOSED"))

  # (3) upgrade 不得洗掉身分
  cli.call(["install", "--home", home])
  C.check("upgrade（install 不帶身分）必須原樣保留 identity", identity.call["tenant_id"].to_s,
          identity.call["employee_owner_ref"] == Support::Fixtures::EMP &&
          identity.call["tenant_id"] == "t-acme")

  # (4) 明確參數覆寫 receipt
  other = File.join(dir, "other.md")
  File.write(other, "# 另一份\n\n由別人匯入。\n")
  out4, _, = cli.call(["import", other, "--memory-kind", "LESSON",
                       "--owner", "urn:omos:employee:emp-777", "--tenant", "t-other"])
  store = File.join(home, ".omos/personal-memory/personal.db")
  rt4 = OMOS::Runtime.open(store)
  owners = rt4.read_rows(surface: OMOS::Runtime::SURFACES[:cli])
               .select { |r| r[:kind] == "PersonalMemoryCandidate" }
               .map { |r| r[:resource]["employee_owner_ref"] }.uniq.sort
  rt4.store.close
  C.check("import 的明確參數覆寫 receipt 身分", owners.inspect,
          out4.include?("CANDIDATE_PROPOSED") &&
          owners == [Support::Fixtures::EMP, "urn:omos:employee:emp-777"].sort)

  # (5) 明確重新綁定才覆寫 receipt
  cli.call(["install", "--home", home, "--owner", "urn:omos:employee:emp-999", "--tenant", "t-new"])
  C.check("明確重新指定才覆寫 receipt 身分", identity.call["employee_owner_ref"].to_s,
          identity.call["employee_owner_ref"] == "urn:omos:employee:emp-999")

  # (6) 只給一半是輸入錯誤，不得寫進半組身分
  before6 = identity.call
  _, err6, st6 = cli.call(["install", "--home", home, "--owner", "urn:omos:employee:emp-half"])
  C.check("install 只給 --owner → INSTALL_IDENTITY_INCOMPLETE 且不改 receipt",
          err6.strip[0, 40],
          !st6.success? && err6.include?("INSTALL_IDENTITY_INCOMPLETE") &&
          identity.call == before6)
end

Dir.mktmpdir("omos-3c-a-identity-missing") do |dir|
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  exe = File.join(OMOS::Contract::ARTIFACT_ROOT, "exe/omos-personal-memory")
  note = File.join(dir, "note.md")
  File.write(note, "# 無身分\n\n沒有設定過身分。\n")

  # (7) 完全沒有身分來源 → fail closed，且不得寫入任何東西
  Open3.capture3({ "HOME" => home }, exe, "install", "--home", home)
  out7, err7, st7 = Open3.capture3(
    { "HOME" => home, "OMOS_EMPLOYEE_REF" => "", "OMOS_TENANT_ID" => "" },
    exe, "import", note, "--memory-kind", "DECISION"
  )
  evidence_root = File.join(home, ".omos/personal-memory/evidence")
  C.check("沒有任何身分來源 → INBOX_OWNER_IDENTITY_REQUIRED",
          err7.lines.first.to_s.strip[0, 50],
          !st7.success? && err7.include?("INBOX_OWNER_IDENTITY_REQUIRED"))
  C.check("身分缺失時不得留下 evidence snapshot", "",
          !Dir.exist?(evidence_root) || Dir.children(evidence_root).empty?)
  C.check("身分缺失的錯誤訊息要說得出怎麼補", out7.to_s[0, 20],
          err7.include?("install --owner") && err7.include?("--tenant"))

  # (8) 環境變數只在沒有 receipt 身分時採用，且必須出聲
  out8, err8, st8 = Open3.capture3(
    { "HOME" => home, "OMOS_EMPLOYEE_REF" => Support::Fixtures::EMP, "OMOS_TENANT_ID" => "t-env" },
    exe, "import", note, "--memory-kind", "DECISION"
  )
  C.check("環境變數可作為暫時來源但必須出聲說明", err8.strip[0, 40],
          st8.success? && out8.include?("CANDIDATE_PROPOSED") &&
          err8.include?("環境變數") && err8.include?("install --owner"))
  C.group = nil
end

# --- Slice A repair-01｜收 reviewer 的 3×P1 ＋ 1×P2 ---
#
# 三筆都是既有 suite 沒打到的缺口，不是回歸。
Dir.mktmpdir("omos-3c-a-inbox-repair01") do |dir|
  C.group = "A"
  store = File.join(dir, "r1.db")
  rt = OMOS::Runtime.open(store)
  cli_surface = OMOS::Runtime::SURFACES[:cli]
  a_owner = "urn:omos:employee:emp-A"
  b_owner = "urn:omos:employee:emp-B"
  src = File.join(dir, "note.md")
  File.write(src, "# 決策\n\n用 WAL。\n")

  imp = lambda do |path, owner, tenant, at: Time.now.utc|
    OMOS::Inbox.import(rt, store, path, memory_kind: "DECISION",
                                        owner_ref: owner, tenant_id: tenant,
                                        surface: cli_surface, now: at)
  end
  # 廣捕而不是只捕 Rejected：少了一道保護時，往下走可能撞出別的例外，
  # 那應該讓對應那一項**轉紅**，而不是讓整包測試炸掉——炸掉的反證等於沒有
  # 鑑別力，因為看不出是哪一個不變式壞了。
  caught = lambda do |&blk|
    blk.call
    nil
  rescue OMOS::EvidenceSnapshot::Rejected => e
    e.code
  rescue StandardError => e
    "#{e.class}: #{e.message[0, 40]}"
  end
  snap_count = -> { Dir.exist?(OMOS::EvidenceSnapshot.root(store)) ? Dir.children(OMOS::EvidenceSnapshot.root(store)).size : 0 }

  # P1-1（下半）：身分格式必須在 capture 之前驗，且驗證下沉到 Inbox（P2）
  before = snap_count.call
  C.check("P1-1 owner_ref 不是 urn 形式 → 在 capture 前擋下",
          caught.call { imp.call(src, "NOT-A-URN", "t-A") }.to_s,
          caught.call { imp.call(src, "NOT-A-URN", "t-A") } == "INBOX_OWNER_REF_MALFORMED")
  C.check("P1-1 owner_ref 格式錯時不得留下 snapshot", snap_count.call.to_s,
          snap_count.call == before)
  C.check("P1-1 tenant_id 含空白 → 擋下",
          caught.call { imp.call(src, a_owner, "t A") }.to_s,
          caught.call { imp.call(src, a_owner, "t A") } == "INBOX_TENANT_ID_MALFORMED")
  C.check("P2 身分驗證下沉到 Inbox（不經 CLI 也擋得住）", "",
          caught.call { imp.call(src, "", "t-A") } == "INBOX_OWNER_REF_MALFORMED")

  # P1-2：同一份內容在**不同時間**重匯，必須仍是冪等重放。
  #       原本 chronology.created_at 吃當下的 now，隔幾秒 canonical 就變了，
  #       撞 PMR_IN_PLACE_ROW_OVERWRITE。舊測試三次都落在同一秒，所以假綠。
  # 用自己的檔案：前面那些格式錯的嘗試若因為少了某道保護而意外成功，
  # 不該把這一組的前提污染掉。每個不變式要能被獨立觀察。
  t0 = Time.utc(2026, 9, 21, 10, 0, 0)
  src2 = File.join(dir, "idempotent.md")
  File.write(src2, "# 冪等\n\n這份專供跨時間重匯測試。\n")
  first = imp.call(src2, a_owner, "t-A", at: t0)
  rows_after_first = rt.read_rows(surface: cli_surface).size
  replay_code = caught.call { imp.call(src2, a_owner, "t-A", at: t0 + 3600) }
  second = imp.call(src2, a_owner, "t-A", at: t0 + 86_400)
  C.check("P1-2 跨時間重匯不得撞 PMR_IN_PLACE_ROW_OVERWRITE",
          replay_code.to_s, replay_code.nil?)
  C.check("P1-2 跨時間重匯仍是重放（不新增 row）",
          "#{rows_after_first}→#{rt.read_rows(surface: cli_surface).size}",
          rt.read_rows(surface: cli_surface).size == rows_after_first)
  # 牆上時鐘**完全不得**進入任何一列的 canonical。只斷言「重放不新增 row」
  # 不夠——兩次匯入若落在同一秒，漏掉的 Time.now 也測不出來（reviewer 正是
  # 靠等 2 秒才撞到）。所以直接斷言每個時間欄位都等於第一次 capture 的時間，
  # 而那是一個固定的過去時刻，與執行當下無關。
  first_rows = rt.read_rows(surface: cli_surface)
  first_cand = first_rows.find { |r| r[:row_id] == first[:candidate_id] }[:resource]
  first_link = first_rows.find { |r| r[:row_id] == first[:link_id] }[:resource]
  C.check("P1-2 link.provenance.created_at 取自第一次 capture",
          first_link.dig("provenance", "created_at").to_s,
          first_link.dig("provenance", "created_at") == t0.iso8601)
  C.check("P1-2 candidate.validity_interval.effective_from 取自第一次 capture",
          first_cand.dig("validity_interval", "effective_from").to_s,
          first_cand.dig("validity_interval", "effective_from") == t0.iso8601)
  C.check("P1-2 chronology.created_at 取自第一次 capture，不隨重匯漂移",
          rt.read_rows(surface: cli_surface)
            .find { |r| r[:row_id] == first[:candidate_id] }[:resource]
            .dig("chronology", "created_at").to_s,
          rt.read_rows(surface: cli_surface)
            .find { |r| r[:row_id] == first[:candidate_id] }[:resource]
            .dig("chronology", "created_at") == t0.iso8601 &&
          second[:candidate_id] == first[:candidate_id])

  # P1-3：相同 bytes、不同 provenance 不是重放。不得靜默沿用第一份。
  rows_before = rt.read_rows(surface: cli_surface).size
  owner_conflict = caught.call { imp.call(src2, b_owner, "t-B") }
  C.check("P1-3 相同 bytes 不同 owner/tenant → fail closed",
          owner_conflict.to_s, owner_conflict == "INBOX_EVIDENCE_OWNER_CONFLICT")

  renamed = File.join(dir, "renamed.md")
  FileUtils.cp(src2, renamed)
  source_conflict = caught.call { imp.call(renamed, a_owner, "t-A") }
  C.check("P1-3 相同 bytes 不同來源路徑 → fail closed（錯誤碼分開）",
          source_conflict.to_s, source_conflict == "INBOX_EVIDENCE_SOURCE_CONFLICT")
  C.check("P1-3 衝突時 snapshot 的 provenance 未被覆寫",
          JSON.parse(File.read(File.join(
            OMOS::EvidenceSnapshot.dir_for(store, first[:content_sha256]), "envelope.json"
          )))["employee_owner_ref"].to_s,
          JSON.parse(File.read(File.join(
            OMOS::EvidenceSnapshot.dir_for(store, first[:content_sha256]), "envelope.json"
          )))["employee_owner_ref"] == a_owner)
  C.check("P1-3 衝突時不得寫入任何一列",
          "#{rows_before}→#{rt.read_rows(surface: cli_surface).size}",
          rt.read_rows(surface: cli_surface).size == rows_before)

  rt.store.close
  C.group = nil
end

# P1-1（上半）：身分是一組 tuple，明確參數不得與 receipt 拼接
Dir.mktmpdir("omos-3c-a-identity-splice") do |dir|
  C.group = "A"
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  exe = File.join(OMOS::Contract::ARTIFACT_ROOT, "exe/omos-personal-memory")
  note = File.join(dir, "note.md")
  File.write(note, "# 決策\n\n用 WAL。\n")
  Open3.capture3({ "HOME" => home }, exe, "install", "--home", home,
                 "--owner", "urn:omos:employee:emp-A", "--tenant", "t-A")

  _, err, st = Open3.capture3({ "HOME" => home }, exe, "import", note,
                              "--memory-kind", "DECISION",
                              "--owner", "urn:omos:employee:emp-B")
  store = File.join(home, ".omos/personal-memory/personal.db")
  rt = OMOS::Runtime.open(store)
  owners = rt.read_rows(surface: OMOS::Runtime::SURFACES[:cli])
             .select { |r| r[:kind] == "PersonalMemoryCandidate" }
             .map { |r| [r[:resource]["employee_owner_ref"], r[:resource]["tenant_id"]] }
  rt.store.close
  C.check("P1-1 只覆寫 --owner → 拒絕，不得與 receipt 的 tenant 拼接",
          err.strip[0, 50],
          !st.success? && err.include?("INBOX_OWNER_IDENTITY_INCOMPLETE"))
  C.check("P1-1 拼接被拒後不得寫入任何 Candidate", owners.inspect, owners.empty?)
  C.group = nil
end

# --- Slice A repair-02｜收 reviewer 的 2×P1 ＋ 1×P2 ---
Dir.mktmpdir("omos-3c-a-inbox-repair02") do |dir|
  C.group = "A"
  store = File.join(dir, "r2.db")
  rt = OMOS::Runtime.open(store)
  cli_surface = OMOS::Runtime::SURFACES[:cli]
  owner = "urn:omos:employee:emp-A"

  caught = lambda do |&blk|
    blk.call
    nil
  rescue OMOS::EvidenceSnapshot::Rejected => e
    e.code
  rescue StandardError => e
    "#{e.class}: #{e.message[0, 40]}"
  end
  snap_count = lambda do
    root = OMOS::EvidenceSnapshot.root(store)
    Dir.exist?(root) ? Dir.children(root).reject { |c| c.include?(".writing-") }.size : 0
  end

  # P1-1：id 整段不得含冒號。reviewer 用的是 urn:omos:employee:alpha:extra。
  src = File.join(dir, "a.md")
  File.write(src, "# a\n\n內容 a。\n")
  [["多一段冒號", "urn:omos:employee:alpha:extra"],
   ["結尾冒號", "urn:omos:employee:alpha:"],
   ["只有 kind 沒有 id", "urn:omos:employee:"],
   ["kind 段是空的", "urn:omos::alpha"]].each do |label, bad|
    before = snap_count.call
    code = caught.call do
      OMOS::Inbox.import(rt, store, src, memory_kind: "DECISION",
                                         owner_ref: bad, tenant_id: "t-A", surface: cli_surface)
    end
    C.check("P1-1 owner_ref #{label} → 擋下（#{bad}）", code.to_s,
            code == "INBOX_OWNER_REF_MALFORMED")
    C.check("P1-1 owner_ref #{label} 不得留下 snapshot", snap_count.call.to_s,
            snap_count.call == before)
  end
  C.check("P1-1 合法的 urn:omos:<kind>:<id> 仍可通過", "",
          caught.call do
            OMOS::Inbox.import(rt, store, src, memory_kind: "DECISION",
                                               owner_ref: owner, tenant_id: "t-A",
                                               surface: cli_surface)
          end.nil?)

  # P1-2：跨 process race 的併發版本。
  #
  # 用注入接縫確定性重現：B 在 A 執行 rename **之前**把同一個 digest 的目錄
  # 寫好（不同 owner/tenant/來源），A 於是輸掉 rename 走 rescue。輸的一方
  # 絕不能靜默採用對方的 envelope。
  raced_src = File.join(dir, "raced.md")
  File.write(raced_src, "# raced\n\n兩個 process 同時第一次 capture。\n")
  rival_src = File.join(dir, "rival.md")
  File.write(rival_src, File.read(raced_src))

  planted = lambda do
    OMOS::EvidenceSnapshot.capture(store, rival_src,
                                   owner_ref: "urn:omos:employee:emp-B", tenant_id: "t-B")
  end
  race_code = caught.call do
    OMOS::EvidenceSnapshot.capture(store, raced_src, owner_ref: owner, tenant_id: "t-A",
                                                     before_rename: planted)
  end
  C.check("P1-2 輸掉 rename 的一方不得靜默採用對方的 envelope", race_code.to_s,
          race_code == "INBOX_EVIDENCE_OWNER_CONFLICT")

  landed = JSON.parse(File.read(File.join(
    OMOS::EvidenceSnapshot.dir_for(store, OMOS::EvidenceSnapshot.digest_of(File.binread(raced_src))),
    "envelope.json"
  )))
  C.check("P1-2 先寫入的那一份 provenance 完好，未被輸家覆寫",
          landed["employee_owner_ref"].to_s,
          landed["employee_owner_ref"] == "urn:omos:employee:emp-B" &&
          landed["tenant_id"] == "t-B")
  C.check("P1-2 race 後不得留下 .writing- 暫存目錄",
          Dir.children(OMOS::EvidenceSnapshot.root(store)).grep(/\.writing-/).inspect,
          Dir.children(OMOS::EvidenceSnapshot.root(store)).grep(/\.writing-/).empty?)

  # 同 provenance 的 race 才是真重放
  same_code = caught.call do
    OMOS::EvidenceSnapshot.capture(store, rival_src, owner_ref: "urn:omos:employee:emp-B",
                                                     tenant_id: "t-B")
  end
  C.check("P1-2 同 provenance 的既有 snapshot 仍正常重放", same_code.to_s, same_code.nil?)

  # P2（repair-02 re-review residual）：不能只驗 tmp **名字的形狀**——那對
  # 「同 process 併發」幾乎沒有鑑別力。改成真正開兩個 thread，用 barrier 讓
  # 它們同時進入 capture，然後斷言兩邊都得到一致的結果、且沒有任何一邊因為
  # 共用暫存目錄而炸掉。
  tmp_src = File.join(dir, "tmp.md")
  File.write(tmp_src, "# tmp\n\n併發暫存目錄。\n")

  barrier = Queue.new
  results = Queue.new
  threads = 2.times.map do
    Thread.new do
      barrier.pop                       # 兩條都就位才一起衝
      results << begin
        env, replayed = OMOS::EvidenceSnapshot.capture(
          store, tmp_src, owner_ref: owner, tenant_id: "t-A"
        )
        [:ok, env["content_sha256"], replayed]
      rescue StandardError => e
        [:error, "#{e.class}: #{e.message[0, 60]}", nil]
      end
    end
  end
  2.times { barrier << :go }
  threads.each(&:join)
  outcomes = 2.times.map { results.pop }

  C.check("P2 同 process 兩 thread 併發 capture：兩邊都不得失敗",
          outcomes.map { |o| o[0] == :ok ? "ok" : o[1] }.inspect,
          outcomes.all? { |o| o[0] == :ok })
  C.check("P2 兩 thread 得到同一個 digest（不得各寫一份）",
          outcomes.map { |o| o[1].to_s[0, 12] }.uniq.inspect,
          outcomes.map { |o| o[1] }.uniq.size == 1)
  C.check("P2 併發後恰好一份 snapshot，且無 .writing- 殘骸",
          Dir.children(OMOS::EvidenceSnapshot.root(store)).grep(/\.writing-/).inspect,
          Dir.children(OMOS::EvidenceSnapshot.root(store)).grep(/\.writing-/).empty? &&
          Dir.exist?(OMOS::EvidenceSnapshot.dir_for(
            store, OMOS::EvidenceSnapshot.digest_of(File.binread(tmp_src))
          )))

  rt.store.close
  C.group = nil
end

# --- Slice B1｜Weekly review queue 是 projection ---
#
# 契約最硬的一條：同一個排定週期的每一次嘗試都必須帶**同一個**
# review_period_id，而且明文禁止「用工作實際發生在哪一天重新推導身分」。
# 週五排定的週期，在下週一 catch-up 時今天的 ISO 週已經是下一週了——拿今天
# 去算就會憑空生出新週期，把這一期的工作記到下一期頭上。
Dir.mktmpdir("omos-3c-a-reviewqueue") do |dir|
  C.group = "A"
  require "omos/review_queue"
  store = File.join(dir, "rq.db")
  rt = OMOS::Runtime.open(store)
  cli_surface = OMOS::Runtime::SURFACES[:cli]
  owner = Support::Fixtures::EMP

  # (1) 週期身分沿用既有資料的形狀，不新造
  # anchor 是**牆上時間**的概念，測試也必須用本機時間表達——用 Time.utc 會
  # 在非 UTC 機器上表達出另一個時刻，那正是這次 P1 的同一種混淆。
  anchor_friday = Time.new(2026, 9, 18, 16, 0, 0)
  p38 = OMOS::ReviewQueue.period_for(anchor_friday)
  C.check("review_period_id 沿用既有形狀（urn:…:review-period:<ISO 年週>）",
          p38[:id],
          p38[:id] == "urn:omos:personal-memory:review-period:2026-W38" &&
          p38[:scheduled_review_period_start] == "2026-09-18")

  # (2) anchor 之前仍屬上一期——這一期的 anchor 還沒到
  C.check("週五 anchor 之前仍屬上一期",
          OMOS::ReviewQueue.period_for(Time.new(2026, 9, 18, 15, 0, 0))[:id].split(":").last,
          OMOS::ReviewQueue.period_for(Time.new(2026, 9, 18, 15, 0, 0))[:id].end_with?("2026-W37"))

  # (3) **契約核心**：catch-up 當天算出來必須是同一個 id，不得變成下一期
  [["週六", Time.new(2026, 9, 19, 9, 0, 0)],
   ["週日", Time.new(2026, 9, 20, 9, 0, 0)],
   ["週一（catch-up 日，ISO 週已跳到 W39）", Time.new(2026, 9, 21, 9, 0, 0)],
   ["週四", Time.new(2026, 9, 24, 9, 0, 0)]].each do |label, t|
    got = OMOS::ReviewQueue.period_for(t)
    C.check("catch-up 不得重推身分：#{label} 仍是 W38", got[:id].split(":").last,
            got[:id] == p38[:id] &&
            got[:scheduled_review_period_start] == p38[:scheduled_review_period_start])
  end
  C.check("週一本身的 ISO 週確實已是 W39（證明上一條不是巧合）",
          Date.new(2026, 9, 21).strftime("%G-W%V"),
          Date.new(2026, 9, 21).strftime("%G-W%V") == "2026-W39")

  # (3b) review P1（B1 repair）：週期推導必須以**本機時區**為準，與 launchd 的
  #      Friday 16:00 同一個時鐘。台北的週五 16:00 local 是 08:00 UTC，原本
  #      直接看傳進來的 Time 的 hour，於是 8 < 16 往回退一週算成 W37——
  #      launchd 在週五 16:00 叫醒時會拿到錯的 review period。
  #      跨時區必須在子行程驗，TZ 要在 Ruby 啟動前就設好。
  tz_probe = <<~RUBY
    require "omos/review_queue"
    t = Time.new(2026, 9, 18, 16, 0, 0).utc
    p_ = OMOS::ReviewQueue.period_for(t)
    puts [p_[:id].split(":").last, p_[:scheduled_review_period_start],
          p_[:scheduled_anchor_at]].join("|")
  RUBY
  { "Asia/Taipei" => "+08:00", "UTC" => "+00:00", "America/Los_Angeles" => "-07:00" }
    .each do |tz, offset|
    o, = Open3.capture3({ "BUNDLE_GEMFILE" => File.join(OMOS::Contract::ARTIFACT_ROOT, "Gemfile"),
                          "TZ" => tz },
                        RbConfig.ruby, "-rbundler/setup",
                        "-I#{File.join(OMOS::Contract::ARTIFACT_ROOT, "lib")}", "-e", tz_probe)
    week, start, anchor = o.strip.split("|")
    C.check("本機時區 #{tz} 的週五 16:00 仍算成 W38（不得因 UTC 偏移退一週）",
            "#{week} #{anchor}",
            week == "2026-W38" && start == "2026-09-18")
    C.check("#{tz} 的 anchor 序列化帶本機偏移 #{offset}", anchor.to_s,
            anchor.to_s.end_with?(offset))
  end

  # (4) catch-up 截止在下一個工作日
  C.check("catch-up 截止落在下一個工作日（週一）", p38[:catch_up_deadline_at],
          p38[:catch_up_deadline_at].start_with?("2026-09-21"))

  # (5) 時間窗硬性：下一期的證據不得混進這一期
  before_anchor = File.join(dir, "before.md")
  after_anchor = File.join(dir, "after.md")
  File.write(before_anchor, "# 本期\n\nanchor 之前匯入。\n")
  File.write(after_anchor, "# 下一期\n\nanchor 之後匯入。\n")
  r_before = OMOS::Inbox.import(rt, store, before_anchor, memory_kind: "DECISION",
                                           owner_ref: owner, tenant_id: "t-acme",
                                           surface: cli_surface, now: anchor_friday - 3600)
  r_after = OMOS::Inbox.import(rt, store, after_anchor, memory_kind: "LESSON",
                                          owner_ref: owner, tenant_id: "t-acme",
                                          surface: cli_surface, now: anchor_friday + 3600)
  q = OMOS::ReviewQueue.due(rt, now: Time.new(2026, 9, 21, 9, 0, 0), surface: cli_surface)
  ids = q[:items].map { |i| i["candidate_id"] }
  C.check("anchor 之前的 candidate 進本期 queue", ids.size.to_s,
          ids.include?(r_before[:candidate_id]))
  C.check("anchor 之後的 candidate 不得混進本期 queue", ids.size.to_s,
          !ids.include?(r_after[:candidate_id]))

  # (6) review due 是純讀：不得寫入任何一列、不得產生 closeout
  rows_before = rt.read_rows(surface: cli_surface).size
  closeouts_before = rt.store.db.get_first_value("SELECT COUNT(*) FROM closeouts").to_i
  3.times { OMOS::ReviewQueue.due(rt, now: Time.new(2026, 9, 21, 9, 0, 0), surface: cli_surface) }
  C.check("review due 不得寫入任何一列",
          "#{rows_before}→#{rt.read_rows(surface: cli_surface).size}",
          rt.read_rows(surface: cli_surface).size == rows_before)
  C.check("review due 不得產生 closeout（排程不是 acceptance）",
          rt.store.db.get_first_value("SELECT COUNT(*) FROM closeouts").to_s,
          rt.store.db.get_first_value("SELECT COUNT(*) FROM closeouts").to_i == closeouts_before)
  C.check("review due 不得宣稱本期已 terminal closeout", q[:terminal_closeout].to_s,
          q[:terminal_closeout] == false)

  # (7) queue 是 projection，不得新增 table
  tables = rt.store.db.execute("SELECT name FROM sqlite_master WHERE type='table'").flatten
  C.check("不得新增 review_queue table", tables.sort.inspect[0, 70],
          tables.none? { |t| t.to_s.match?(/queue/i) })

  # (8) 已在本期 closeout 裡被處置過的項目要退出 queue
  disposed = OMOS::Inbox.import(
    rt, store, File.join(dir, "disposed.md").tap { |f| File.write(f, "# 已處置\n\n本期已處理。\n") },
    memory_kind: "RULE", owner_ref: owner, tenant_id: "t-acme",
    surface: cli_surface, now: anchor_friday - 7200
  )
  in_queue_before = OMOS::ReviewQueue.due(rt, now: Time.new(2026, 9, 21, 9, 0, 0), surface: cli_surface)[:items]
                                     .map { |i| i["candidate_id"] }
  rt.commit_closeout(closeout: Support::Fixtures.closeout(p38[:id], disposed[:candidate_id],
                                                         "COMPLETE", "SCHEDULED"),
                     surface: cli_surface)
  in_queue_after = OMOS::ReviewQueue.due(rt, now: Time.new(2026, 9, 21, 9, 0, 0), surface: cli_surface)[:items]
                                    .map { |i| i["candidate_id"] }
  C.check("已被本期 closeout 處置過的項目退出 queue",
          "#{in_queue_before.size}→#{in_queue_after.size}",
          in_queue_before.include?(disposed[:candidate_id]) &&
          !in_queue_after.include?(disposed[:candidate_id]))

  # (9) 0 due items 必須明確回報，不得偽造 terminal receipt
  empty = OMOS::ReviewQueue.due(rt, now: Time.new(2026, 1, 9, 17, 0, 0), surface: cli_surface)
  C.check("0 due items 明確回 0，且不得偽造 terminal closeout",
          "#{empty[:items].size}／terminal=#{empty[:terminal_closeout]}",
          empty[:items].empty? && empty[:terminal_closeout] == false)

  rt.store.close
  C.group = nil
end

# --- Slice B2｜Friday trigger（launchd）＋ 提醒 ---
#
# 這一組最重要的不變式是「排程不是 acceptance」：週五有跑 job 不等於這週
# review 已完成，逾期也不等於 SKIPPED。契約把 terminal disposition 留給人的
# closeout，所以任何一條自動化路徑都不得產生 closeout／Record／Promotion。
#
# **launchctl 一律注入替身。** 用真的 launchctl 會把 job 載進執行測試那個人
# 的 session，而且指向 tmpdir 裡馬上就會消失的路徑——那是會留在機器上的外部
# 副作用。交付方在 repair-01 實作時就真的踩到過一次：整包測試跑完之後，
# `launchctl print gui/<uid>/com.omos.personal-memory.weekly-review` 確實存在。
Dir.mktmpdir("omos-3c-a-schedule") do |dir|
  C.group = "A"
  require "omos/schedule"
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  store = File.join(home, ".omos/personal-memory/personal.db")
  exe = File.join(OMOS::Contract::ARTIFACT_ROOT, "exe/omos-personal-memory")
  Open3.capture3({ "HOME" => home }, exe, "install", "--home", home,
                 "--owner", Support::Fixtures::EMP, "--tenant", "t-acme")

  # 假的 launchctl：記錄呼叫、以內部狀態模擬 loaded/not loaded。
  calls = []
  loaded = { on: false }
  fake_launchctl = lambda do |*args|
    calls << args
    case args.first
    when "bootstrap" then loaded[:on] = true; { ok: true, status: 0, out: "", err: "" }
    when "bootout"   then was = loaded[:on]; loaded[:on] = false
                          { ok: was, status: was ? 0 : 3, out: "", err: "" }
    when "print"     then { ok: loaded[:on], status: loaded[:on] ? 0 : 113, out: "", err: "" }
    else { ok: false, status: 1, out: "", err: "unknown" }
    end
  end
  lc = { launchctl: fake_launchctl }

  agents = File.join(home, "Library/LaunchAgents")
  FileUtils.mkdir_p(agents)
  foreign = File.join(agents, "com.someoneelse.weekly-review.plist")
  File.write(foreign, "<plist><dict/></plist>")
  foreign_bytes = File.binread(foreign)

  try_install = lambda do |**kw|
    OMOS::Schedule.install(home: home, **lc, **kw)
  rescue StandardError => e
    { plist: OMOS::Schedule.plist_path(home), replaced: nil, loaded: nil,
      error: "#{e.class}: #{e.message[0, 60]}" }
  end

  # (1) plist 合法，且帶 Friday 16:00 ＋ RunAtLoad（D4 裁決）
  r = try_install.call
  plist = r[:plist]
  C.check("schedule install 成功", r[:error].to_s, r[:error].nil?)
  lint_out, _, lint_st = Open3.capture3("/usr/bin/plutil", "-lint", plist)
  C.check("產生的是合法 plist（plutil -lint）", lint_out.strip[-6, 6].to_s, lint_st.success?)
  doc = OMOS::Schedule.plutil_json(plist) || {}
  C.check("StartCalendarInterval 是週五 16:00", doc["StartCalendarInterval"].inspect,
          doc.dig("StartCalendarInterval", "Weekday") == 5 &&
          doc.dig("StartCalendarInterval", "Hour") == 16)
  C.check("RunAtLoad 為 true（錯過後在下次登入補喚醒）", doc["RunAtLoad"].to_s,
          doc["RunAtLoad"] == true)

  args = doc["ProgramArguments"] || []
  C.check("LaunchAgent 走 current/，不得 pin artifact-id", args.first.to_s[-40, 40].to_s,
          args.first.to_s.include?("/.omos/personal-memory/current/") &&
          !args.first.to_s.match?(%r{/versions/[0-9a-f]+}))
  C.check("LaunchAgent 呼叫的是 review due（不是任何會寫入的指令）", args.inspect,
          args[1].to_s == "review" && args[2].to_s == "due")

  # (2) repair-01 P1-1：install 必須真的 bootstrap，status 要反映實際載入狀態
  C.check("P1-1 install 真的呼叫 launchctl bootstrap",
          calls.map(&:first).inspect,
          calls.any? { |c| c.first == "bootstrap" && c.last == plist })
  C.check("P1-1 install 回報實際載入狀態", r[:loaded].to_s, r[:loaded] == true)
  st_loaded = OMOS::Schedule.status(home: home, **lc)
  C.check("P1-1 status 反映 job 已載入", st_loaded[:installed].to_s,
          st_loaded[:installed] == true && st_loaded[:loaded] == true)

  # plist 在、但 job 沒載入 → 不得報「已安裝」
  loaded[:on] = false
  st_unloaded = OMOS::Schedule.status(home: home, **lc)
  C.check("P1-1 plist 在但 job 未載入 → 不得當成已安裝",
          "present=#{st_unloaded[:plist_present]} loaded=#{st_unloaded[:loaded]} installed=#{st_unloaded[:installed]}",
          st_unloaded[:plist_present] == true && st_unloaded[:loaded] == false &&
          st_unloaded[:installed] == false)
  loaded[:on] = true

  # (3) repair-01 P1-2：自訂 anchor 必須完整傳遞，不得 split-brain
  r15 = try_install.call(anchor_hour: 15)
  doc15 = OMOS::Schedule.plutil_json(plist) || {}
  args15 = doc15["ProgramArguments"] || []
  ai = args15.index("--anchor-hour")
  C.check("P1-2 anchor 同時進 StartCalendarInterval 與 ProgramArguments",
          "cal=#{doc15.dig("StartCalendarInterval", "Hour")} args=#{ai && args15[ai + 1]}",
          doc15.dig("StartCalendarInterval", "Hour") == 15 &&
          ai && args15[ai + 1].to_s == "15" && r15[:anchor_hour] == 15)
  st15 = OMOS::Schedule.status(home: home, now: Time.new(2026, 9, 18, 15, 30, 0), **lc)
  C.check("P1-2 status 讀回已安裝的 anchor，15:00 的排程在週五 15:30 算成 W38",
          "#{st15[:anchor_hour]}／#{st15[:period].split(":").last}",
          st15[:anchor_hour] == 15 && st15[:period].end_with?("2026-W38"))
  st16 = OMOS::Schedule.status(home: home, now: Time.new(2026, 9, 18, 15, 30, 0),
                               **lc).tap { try_install.call(anchor_hour: 16) }
  st16b = OMOS::Schedule.status(home: home, now: Time.new(2026, 9, 18, 15, 30, 0), **lc)
  C.check("P1-2 換回 16:00 後，同一時刻改算成 W37（證明 anchor 真的生效）",
          "#{st16b[:anchor_hour]}／#{st16b[:period].split(":").last}",
          st16b[:anchor_hour] == 16 && st16b[:period].end_with?("2026-W37"))
  C.check("P1-2 非法 anchor 一律拒絕", try_install.call(anchor_hour: 99)[:error].to_s[0, 40],
          try_install.call(anchor_hour: 99)[:error].to_s.include?("SCHEDULE_ANCHOR_HOUR_INVALID"))

  # (4) repair-01 P1-3：ownership 看 plist 內部 Label，不是檔名
  impostor_dir = File.join(dir, "impostor")
  FileUtils.mkdir_p(File.join(impostor_dir, "Library/LaunchAgents"))
  impostor = File.join(impostor_dir, "Library/LaunchAgents/#{OMOS::Schedule::LABEL}.plist")
  File.write(impostor, <<~XML)
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict><key>Label</key><string>com.foreign.job</string></dict></plist>
  XML
  impostor_bytes = File.binread(impostor)
  rm_impostor = OMOS::Schedule.remove(home: impostor_dir, **lc)
  C.check("P1-3 同檔名但 plist 內 Label 是別人的 → 不得刪除",
          "#{rm_impostor[:removed]}／#{rm_impostor[:reason]}／#{rm_impostor[:found_label]}",
          rm_impostor[:removed] == false && rm_impostor[:reason] == "NOT_OURS" &&
          rm_impostor[:found_label] == "com.foreign.job")
  C.check("P1-3 冒名 plist 逐位元組不受影響", "",
          File.file?(impostor) && File.binread(impostor) == impostor_bytes)
  impostor_install = begin
    OMOS::Schedule.install(home: impostor_dir, **lc)
    nil
  rescue OMOS::Schedule::Failed => e
    e.code
  end
  C.check("P1-3 install 不得覆寫我們路徑上的第三方 plist", impostor_install.to_s,
          impostor_install == "SCHEDULE_FOREIGN_PLIST_AT_OUR_PATH" &&
          File.binread(impostor) == impostor_bytes)

  # (5) 重跑不得產生第二份；remove 要 bootout ＋ 刪檔，且不碰第三方
  r2 = try_install.call
  ours = Dir.children(agents).select { |f| f.include?("omos") }
  C.check("schedule install 重跑不產生第二份 LaunchAgent",
          "#{ours.size} 份／replaced=#{r2[:replaced]}",
          ours.size == 1 && r2[:replaced] == true)
  # 重裝順序：bootout → bootstrap。中間夾著 print 是 repair-04 加的驗證
  # （bootout 回 0 不代表真的停了），所以比對時把 print 濾掉——要鎖的是
  # 「停掉再載入」這個順序，不是「中間不准有任何呼叫」。
  mutating = calls.map(&:first).reject { |c| c == "print" }
  C.check("重裝先 bootout 再 bootstrap（launchd 不收同 Label 重複載入）",
          mutating.inspect,
          mutating.each_cons(2).any? { |a, b| a == "bootout" && b == "bootstrap" })
  C.check("repair-04：每次 bootout 之後都緊接一次 loaded? 複查",
          calls.map(&:first).inspect,
          calls.each_cons(2).select { |a, _| a.first == "bootout" }
               .all? { |_, b| b.first == "print" })

  removed = OMOS::Schedule.remove(home: home, **lc)
  C.check("schedule remove 真的 bootout 並刪除自己的 plist",
          "#{removed[:removed]}／loaded=#{removed[:loaded]}",
          removed[:removed] == true && !File.exist?(plist) && removed[:loaded] == false)
  C.check("第三方 LaunchAgent 逐位元組不受影響", "",
          File.file?(foreign) && File.binread(foreign) == foreign_bytes)
  C.check("未安裝時 remove 明確回 NOT_INSTALLED，不誤刪別人",
          OMOS::Schedule.remove(home: home, **lc)[:reason].to_s,
          OMOS::Schedule.remove(home: home, **lc)[:reason] == "NOT_INSTALLED" && File.file?(foreign))

  # (6) 逾期只是狀態，不得自動 SKIPPED，也不得產生 closeout
  try_install.call
  rt = OMOS::Runtime.open(store)
  cli_surface = OMOS::Runtime::SURFACES[:cli]
  rows_before = rt.read_rows(surface: cli_surface).size
  closeouts_before = rt.store.db.get_first_value("SELECT COUNT(*) FROM closeouts").to_i

  overdue_now = Time.new(2026, 9, 22, 9, 0, 0)      # 週二：catch-up 截止已過
  st = OMOS::Schedule.status(home: home, now: overdue_now, runtime: rt,
                             surface: cli_surface, **lc)
  C.check("超過 catch-up 截止 → 呈現逾期", st[:overdue].to_s, st[:overdue] == true)
  C.check("逾期不得自動變成 SKIPPED（狀態裡沒有這個詞）", st.inspect[0, 60],
          !st.to_s.include?("SKIPPED"))
  C.check("逾期時本期仍未 terminal closeout", st[:terminal_closeout].to_s,
          st[:terminal_closeout] == false)
  C.check("schedule status 不得寫入任何一列",
          "#{rows_before}→#{rt.read_rows(surface: cli_surface).size}",
          rt.read_rows(surface: cli_surface).size == rows_before)
  C.check("schedule 全程不得產生 closeout（排程不是 acceptance）",
          rt.store.db.get_first_value("SELECT COUNT(*) FROM closeouts").to_s,
          rt.store.db.get_first_value("SELECT COUNT(*) FROM closeouts").to_i == closeouts_before)

  # (7) 通知：失敗不影響 queue，但不得完全靜默（D5 裁決）
  err_io = StringIO.new
  failing = ->(_msg) { raise Errno::ENOENT, "osascript" }
  res = OMOS::Schedule.notify(3, io: err_io, runner: failing)
  C.check("通知失敗不得影響 queue（不拋出）", res[:notified].to_s, res[:notified] == false)
  C.check("通知失敗必須出聲（不得完全靜默）", err_io.string.strip[0, 40],
          err_io.string.include?("通知失敗") && err_io.string.include?("不影響 queue"))
  C.check("通知失敗只印一行（失敗出口必須唯一）", err_io.string.lines.size.to_s,
          err_io.string.lines.size == 1)
  C.check("通知失敗的原因要說得出是哪一種（例外 vs 回非零）", res[:reason].to_s[0, 30],
          res[:reason].to_s.start_with?("Errno::ENOENT"))

  nonzero_io = StringIO.new
  nonzero = OMOS::Schedule.notify(1, io: nonzero_io, runner: ->(_m) { false })
  C.check("osascript 回非零也必須出聲，且原因不同於例外", nonzero[:reason].to_s,
          nonzero[:notified] == false && nonzero[:reason] == "osascript 回非零" &&
          nonzero_io.string.lines.size == 1)

  quiet = StringIO.new
  none = OMOS::Schedule.notify(0, io: quiet, runner: ->(_m) { raise "不該被呼叫" })
  C.check("0 due items 不送通知，也不製造假完成", none[:reason].to_s,
          none[:notified] == false && none[:reason] == "NO_DUE_ITEMS" && quiet.string.empty?)

  ok_io = StringIO.new
  sent = []
  ok = OMOS::Schedule.notify(2, io: ok_io, runner: ->(m) { sent << m; true })
  C.check("有待 review 時送出「本週有 N 筆待 review」", sent.first.to_s,
          ok[:notified] == true && sent.first == "Personal Memory：本週有 2 筆待 review")

  # (8) 不新增任何 ledger／table 給 notification
  tables = rt.store.db.execute("SELECT name FROM sqlite_master WHERE type='table'").flatten
  C.check("不得為 notification 另開 table／ledger", tables.sort.inspect[0, 70],
          tables.none? { |t| t.to_s.match?(/notif|schedule|queue/i) })

  # (8b) repair-02：install／remove 是交易。
  #
  # 兩個 failure state 都是「現場看起來檔案都在，但東西已經壞了」：
  #   升級 bootstrap 失敗卻不還原 → 舊排程被打壞，使用者下週五收不到提醒
  #   remove 的 bootout 失敗卻照刪 → 留下沒有管理檔案的孤兒 launchd job
  #
  # 失敗一律用注入的 launchctl 製造，不碰真實 session。
  Dir.mktmpdir("omos-3c-a-schedule-txn") do |tdir|
    thome = File.join(tdir, "home")
    Support::FakeHome.seed(thome)
    Open3.capture3({ "HOME" => thome }, exe, "install", "--home", thome,
                   "--owner", Support::Fixtures::EMP, "--tenant", "t-acme")
    tpath = OMOS::Schedule.plist_path(thome)

    tloaded = { on: false }
    # bootstrap_fails_once 模擬「新設定被 launchd 拒絕，但舊設定仍載得回來」
    # ——這才是升級失敗的常見形狀。全域性的 bootstrap 壞掉是另一種現場，
    # 由 (a2) 單獨涵蓋。
    fail_modes = { bootstrap_fails_once: false, bootout: false }
    tcalls = []
    lctl = lambda do |*args|
      tcalls << args
      case args.first
      when "bootstrap"
        if fail_modes[:bootstrap_fails_once]
          fail_modes[:bootstrap_fails_once] = false
          { ok: false, status: 5, out: "", err: "Bootstrap failed: 5: Input/output error" }
        else
          tloaded[:on] = true
          { ok: true, status: 0, out: "", err: "" }
        end
      when "bootout"
        if fail_modes[:bootout]
          { ok: false, status: 5, out: "", err: "Boot-out failed" }
        else
          was = tloaded[:on]
          tloaded[:on] = false
          { ok: was, status: was ? 0 : 3, out: "", err: "" }
        end
      when "print" then { ok: tloaded[:on], status: tloaded[:on] ? 0 : 113, out: "", err: "" }
      else { ok: false, status: 1, out: "", err: "" }
      end
    end

    # 先裝一個正常運作的 16:00 排程
    OMOS::Schedule.install(home: thome, anchor_hour: 16, launchctl: lctl)
    good_bytes = File.binread(tpath)
    C.check("交易前提：舊排程正常運作", tloaded[:on].to_s, tloaded[:on] == true)

    # (a) 升級到 15:00 但 bootstrap 失敗 → 必須完整還原
    fail_modes[:bootstrap_fails_once] = true
    code = begin
      OMOS::Schedule.install(home: thome, anchor_hour: 15, launchctl: lctl)
      nil
    rescue OMOS::Schedule::Failed => e
      e.code
    end
    C.check("P1-1 升級 bootstrap 失敗 → 明確失敗", code.to_s,
            code == "SCHEDULE_LAUNCHCTL_BOOTSTRAP_FAILED")
    C.check("P1-1 升級失敗後舊 plist 位元組完全還原（anchor 仍是 16:00）",
            OMOS::Schedule.installed_anchor_hour(tpath).to_s,
            File.binread(tpath) == good_bytes &&
            OMOS::Schedule.installed_anchor_hour(tpath) == 16)
    C.check("P1-1 升級失敗後原本的 loaded 狀態也還原", tloaded[:on].to_s,
            tloaded[:on] == true && OMOS::Schedule.loaded?(launchctl: lctl) == true)

    # (a2) 還原**也**失敗時，必須自己講出來——不得讓使用者以為舊排程還在。
    #      這與 (a) 是兩種不同的現場，錯誤碼必須分得開。
    Dir.mktmpdir("omos-3c-a-schedule-norestore") do |ndir|
      nhome = File.join(ndir, "home")
      Support::FakeHome.seed(nhome)
      Open3.capture3({ "HOME" => nhome }, exe, "install", "--home", nhome,
                     "--owner", Support::Fixtures::EMP, "--tenant", "t-acme")
      nloaded = { on: false }
      dead = { all: false }
      nlctl = lambda do |*args|
        case args.first
        when "bootstrap"
          next { ok: false, status: 5, out: "", err: "Bootstrap failed: 5" } if dead[:all]

          nloaded[:on] = true
          { ok: true, status: 0, out: "", err: "" }
        when "bootout" then was = nloaded[:on]; nloaded[:on] = false
                            { ok: was, status: was ? 0 : 3, out: "", err: "" }
        when "print" then { ok: nloaded[:on], status: nloaded[:on] ? 0 : 113, out: "", err: "" }
        else { ok: false, status: 1, out: "", err: "" }
        end
      end
      OMOS::Schedule.install(home: nhome, anchor_hour: 16, launchctl: nlctl)
      dead[:all] = true
      ncode = begin
        OMOS::Schedule.install(home: nhome, anchor_hour: 15, launchctl: nlctl)
        nil
      rescue OMOS::Schedule::Failed => e
        e.code
      end
      C.check("P1-1 還原也失敗時必須用不同的錯誤碼講出來", ncode.to_s,
              ncode == "SCHEDULE_INSTALL_FAILED_AND_NOT_RESTORED")
      C.check("P1-1 還原失敗時 plist 位元組仍已寫回舊版",
              OMOS::Schedule.installed_anchor_hour(OMOS::Schedule.plist_path(nhome)).to_s,
              OMOS::Schedule.installed_anchor_hour(OMOS::Schedule.plist_path(nhome)) == 16)
    end

    # (b) 首次安裝 bootstrap 失敗 → 不得留下假安裝的 plist
    Dir.mktmpdir("omos-3c-a-schedule-first") do |fdir|
      fhome = File.join(fdir, "home")
      Support::FakeHome.seed(fhome)
      Open3.capture3({ "HOME" => fhome }, exe, "install", "--home", fhome,
                     "--owner", Support::Fixtures::EMP, "--tenant", "t-acme")
      fpath = OMOS::Schedule.plist_path(fhome)
      floaded = { on: false }
      flctl = lambda do |*args|
        case args.first
        when "bootstrap" then { ok: false, status: 5, out: "", err: "Bootstrap failed: 5" }
        when "print" then { ok: floaded[:on], status: 113, out: "", err: "" }
        else { ok: false, status: 3, out: "", err: "" }
        end
      end
      fcode = begin
        OMOS::Schedule.install(home: fhome, launchctl: flctl)
        nil
      rescue OMOS::Schedule::Failed => e
        e.code
      end
      C.check("P1-1 首次安裝 bootstrap 失敗 → 不得留下假安裝的 plist",
              "#{fcode}／plist=#{File.exist?(fpath)}",
              fcode == "SCHEDULE_LAUNCHCTL_BOOTSTRAP_FAILED" && !File.exist?(fpath))
    end

    # (c) remove 時 bootout 失敗 → 保留 plist 並 fail loud，不得留下孤兒 job
    fail_modes[:bootout] = true
    rcode = begin
      OMOS::Schedule.remove(home: thome, launchctl: lctl)
      nil
    rescue OMOS::Schedule::Failed => e
      e.code
    end
    fail_modes[:bootout] = false
    C.check("P1-1 remove 的 bootout 失敗 → fail loud", rcode.to_s,
            rcode == "SCHEDULE_BOOTOUT_FAILED")
    C.check("P1-1 remove 失敗時必須保留 plist（不得留下孤兒 job）",
            "plist=#{File.exist?(tpath)}／loaded=#{tloaded[:on]}",
            File.exist?(tpath) && tloaded[:on] == true)

    # (d) bootout 恢復正常後，remove 應該正常完成
    ok_remove = OMOS::Schedule.remove(home: thome, launchctl: lctl)
    C.check("P1-1 bootout 恢復後 remove 正常完成，且 job 真的停了",
            "#{ok_remove[:removed]}／loaded=#{tloaded[:on]}",
            ok_remove[:removed] == true && !File.exist?(tpath) && tloaded[:on] == false)
  end

  # (8c) repair-03：bootstrap 回 0 **不代表 job 真的載入**。
  #
  # 只信 exit status 會產生兩種假成功：install 留下一份 plist 卻沒有 job；
  # rollback 以為舊排程回來了卻沒有，而且錯誤碼不會升級，使用者不知道要手動
  # 處理。兩條路共用同一個判準：exit 0 **而且** loaded? 為真。
  Dir.mktmpdir("omos-3c-a-schedule-lying") do |ldir|
    lhome = File.join(ldir, "home")
    Support::FakeHome.seed(lhome)
    Open3.capture3({ "HOME" => lhome }, exe, "install", "--home", lhome,
                   "--owner", Support::Fixtures::EMP, "--tenant", "t-acme")
    lpath = OMOS::Schedule.plist_path(lhome)

    # 說謊的 launchctl：bootstrap 一律回 0，但 job 從來沒有真的載入。
    lying_loaded = { on: false }
    lie = { bootstrap: false }
    lying = lambda do |*args|
      case args.first
      when "bootstrap"
        lying_loaded[:on] = true unless lie[:bootstrap]
        { ok: true, status: 0, out: "", err: "" }
      when "bootout" then was = lying_loaded[:on]; lying_loaded[:on] = false
                          { ok: was, status: was ? 0 : 3, out: "", err: "" }
      when "print" then { ok: lying_loaded[:on], status: lying_loaded[:on] ? 0 : 113, out: "", err: "" }
      else { ok: false, status: 1, out: "", err: "" }
      end
    end

    # (a) 首次 install：bootstrap 回 0 但沒載入 → 不得回報成功、不得留 plist
    lie[:bootstrap] = true
    acode = begin
      OMOS::Schedule.install(home: lhome, launchctl: lying)
      nil
    rescue OMOS::Schedule::Failed => e
      e
    end
    C.check("P1 首次 install：bootstrap 說謊 → 明確失敗，不得假安裝",
            "#{acode&.code}／plist=#{File.exist?(lpath)}",
            acode.is_a?(OMOS::Schedule::Failed) &&
            acode.code == "SCHEDULE_LAUNCHCTL_BOOTSTRAP_FAILED" && !File.exist?(lpath))
    C.check("P1 錯誤訊息要說得出是「回報成功但實際未載入」",
            acode.to_s[-40, 40].to_s,
            acode.to_s.include?("實際未載入"))

    # (b) rollback 的 bootstrap 也說謊 → 必須升級成 NOT_RESTORED
    lie[:bootstrap] = false
    OMOS::Schedule.install(home: lhome, anchor_hour: 16, launchctl: lying)
    good = File.binread(lpath)
    lie[:bootstrap] = true      # 之後所有 bootstrap 都只是嘴上成功
    bcode = begin
      OMOS::Schedule.install(home: lhome, anchor_hour: 15, launchctl: lying)
      nil
    rescue OMOS::Schedule::Failed => e
      e.code
    end
    C.check("P1 rollback 的 bootstrap 說謊 → 升級成 NOT_RESTORED", bcode.to_s,
            bcode == "SCHEDULE_INSTALL_FAILED_AND_NOT_RESTORED")
    C.check("P1 即使還原失敗，plist 位元組仍已寫回舊版",
            OMOS::Schedule.installed_anchor_hour(lpath).to_s,
            File.binread(lpath) == good)
  end

  # (8d) repair-04：bootout 回 0 **不代表 job 真的停了**。
  #
  # reviewer 重播的 split-brain：舊 16:00 的 job 還活著，bootout 回 ok、
  # bootstrap 也回 ok 但沒換掉它，而 bootstrap 那側只問「這個 Label 是否
  # loaded」——看到的是**舊 job 還在**，於是判成功。結果 install 正常 return、
  # 磁碟 plist 是 15:00、真正 live 的 job 卻是 16:00。
  Dir.mktmpdir("omos-3c-a-schedule-stuck") do |sdir|
    shome = File.join(sdir, "home")
    Support::FakeHome.seed(shome)
    Open3.capture3({ "HOME" => shome }, exe, "install", "--home", shome,
                   "--owner", Support::Fixtures::EMP, "--tenant", "t-acme")
    spath = OMOS::Schedule.plist_path(shome)

    # 說謊的 bootout：回 0，但 job 繼續活著（而且仍是舊設定）。
    sloaded = { on: false }
    stuck = { bootout: false }
    slctl = lambda do |*args|
      case args.first
      when "bootstrap" then sloaded[:on] = true; { ok: true, status: 0, out: "", err: "" }
      when "bootout"
        sloaded[:on] = false unless stuck[:bootout]
        { ok: true, status: 0, out: "", err: "" }
      when "print" then { ok: sloaded[:on], status: sloaded[:on] ? 0 : 113, out: "", err: "" }
      else { ok: false, status: 1, out: "", err: "" }
      end
    end

    OMOS::Schedule.install(home: shome, anchor_hour: 16, launchctl: slctl)
    good16 = File.binread(spath)
    stuck[:bootout] = true

    code = begin
      OMOS::Schedule.install(home: shome, anchor_hour: 15, launchctl: slctl)
      nil
    rescue OMOS::Schedule::Failed => e
      e
    end
    C.check("P1 bootout 說謊（回 0 但仍 loaded）→ install 必須失敗，不得 split-brain",
            code.is_a?(OMOS::Schedule::Failed) ? code.code : "（成功 return）",
            code.is_a?(OMOS::Schedule::Failed) &&
            code.code == "SCHEDULE_LAUNCHCTL_BOOTOUT_FAILED")
    C.check("P1 錯誤訊息要說得出是「回報成功但仍在載入中」",
            code.to_s[-30, 30].to_s, code.to_s.include?("仍在載入中"))
    C.check("P1 失敗後磁碟 plist 還原成舊版 16:00（不得留下 15:00）",
            OMOS::Schedule.installed_anchor_hour(spath).to_s,
            File.binread(spath) == good16 &&
            OMOS::Schedule.installed_anchor_hour(spath) == 16)
    C.check("P1 舊 job 從未被停掉，因此仍 loaded——磁碟與 live 一致",
            sloaded[:on].to_s, sloaded[:on] == true)

    # remove 也走同一個判準
    rcode = begin
      OMOS::Schedule.remove(home: shome, launchctl: slctl)
      nil
    rescue OMOS::Schedule::Failed => e
      e.code
    end
    C.check("P1 remove 也用同一判準：bootout 說謊 → 保留 plist 並 fail loud",
            "#{rcode}／plist=#{File.exist?(spath)}",
            rcode == "SCHEDULE_BOOTOUT_FAILED" && File.exist?(spath))
  end

  # (9) 測試本身不得把 job 載進真實 session
  C.check("本組測試全程未呼叫真實 launchctl（只用注入替身）",
          "#{calls.size} 次注入呼叫",
          calls.size.positive?)

  rt.store.close
  C.group = nil
end

# --- Launchd lifecycle：依已簽署契約重做（CARD-LAUNCHD-LIFECYCLE-IMPLEMENTATION-20260922）---
#
# 契約凍結了 bootstrap／bootout 的四象限、階段序列、兩個方向的發布順序，
# 以及 lifecycle mutation 的序列化。這一組逐條驗。
#
# launchctl 一律注入替身；替身同時追蹤「現在 live 的是哪一份設定」，
# 因為 split-brain 的定義是**中間曾經存在過** disk 與 live 不一致，
# 只看最終結果驗不出來。
Dir.mktmpdir("omos-3c-a-lifecycle") do |dir|
  C.group = "A"
  home = File.join(dir, "home")
  Support::FakeHome.seed(home)
  exe = File.join(OMOS::Contract::ARTIFACT_ROOT, "exe/omos-personal-memory")
  Open3.capture3({ "HOME" => home }, exe, "install", "--home", home,
                 "--owner", Support::Fixtures::EMP, "--tenant", "t-acme")
  path = OMOS::Schedule.plist_path(home)

  # 追蹤 live 設定的替身：bootstrap 會把「當下磁碟上的 anchor」變成 live。
  disk_hour = -> { File.file?(path) ? OMOS::Schedule.installed_anchor_hour(path) : nil }
  make = lambda do |behaviour: {}|
    live = { hour: nil }
    trace = []
    lc = lambda do |*args|
      case args.first
      when "bootstrap"
        want = behaviour[:bootstrap]
        activates = want.nil? || want != :fail_clean
        live[:hour] = disk_hour.call if activates
        ok = want.nil?
        trace << [:bootstrap, disk_hour.call, live[:hour]]
        { ok: ok, status: ok ? 0 : 5, out: "", err: ok ? "" : "Bootstrap failed: 5" }
      when "bootout"
        want = behaviour[:bootout]
        stops = want != :stuck
        live[:hour] = nil if stops
        ok = want != :exit_nonzero
        trace << [:bootout, disk_hour.call, live[:hour]]
        { ok: ok, status: ok ? 0 : 5, out: "", err: ok ? "" : "Boot-out failed" }
      when "print" then { ok: !live[:hour].nil?, status: live[:hour] ? 0 : 113, out: "", err: "" }
      else { ok: false, status: 1, out: "", err: "" }
      end
    end
    [lc, live, trace]
  end

  # ── §1.3.3 正向 upgrade：全路徑不得出現 disk=new / live=old ────────────
  lc, live, trace = make.call
  OMOS::Schedule.install(home: home, anchor_hour: 16, launchctl: lc)
  base_trace_len = trace.size
  OMOS::Schedule.install(home: home, anchor_hour: 15, launchctl: lc)
  upgrade_trace = trace[base_trace_len..]
  split = upgrade_trace.select { |_, disk, livehour| disk == 15 && livehour == 16 }
  C.check("§1.3.3 upgrade 全路徑不得出現 disk=new／live=old",
          upgrade_trace.map { |a, d, l| "#{a}:#{d}/#{l}" }.inspect,
          split.empty?)
  C.check("§1.3.3 upgrade 必須先停舊 job 才發布新 plist",
          upgrade_trace.first.inspect,
          upgrade_trace.first[0] == :bootout && upgrade_trace.first[1] == 16)
  C.check("§1.3.3 upgrade 最終 disk 與 live 一致", "#{disk_hour.call}/#{live[:hour]}",
          disk_hour.call == 15 && live[:hour] == 15)

  # 舊 job 停不掉 → 不得發布新 plist，磁碟維持舊版
  lc2, live2, = make.call(behaviour: { bootout: :stuck })
  OMOS::Schedule.install(home: home, anchor_hour: 16, launchctl: lc2)
  code = begin
    OMOS::Schedule.install(home: home, anchor_hour: 15, launchctl: lc2)
    nil
  rescue OMOS::Schedule::Failed => e
    e.code
  end
  C.check("§1.3.3 舊 job 停不掉 → 不得發布新 plist，磁碟維持舊版",
          "#{code}／disk=#{disk_hour.call}／live=#{live2[:hour]}",
          code == "SCHEDULE_LAUNCHCTL_BOOTOUT_FAILED" &&
          disk_hour.call == 16 && live2[:hour] == 16)

  # ── §1.1 第四象限：partial activation ────────────────────────────────
  Dir.mktmpdir("omos-3c-a-lifecycle-partial") do |pdir|
    phome = File.join(pdir, "home")
    Support::FakeHome.seed(phome)
    Open3.capture3({ "HOME" => phome }, exe, "install", "--home", phome,
                   "--owner", Support::Fixtures::EMP, "--tenant", "t-acme")
    ppath = OMOS::Schedule.plist_path(phome)
    pdisk = -> { File.file?(ppath) ? OMOS::Schedule.installed_anchor_hour(ppath) : nil }

    plive = { hour: nil }
    # cleanup_stuck 只能卡住**清理新 job 的那一次 bootout**，不能連
    # OLD_STOP_VERIFIED 的那次也卡住——否則測到的是「舊 job 停不掉」，
    # 根本走不到 CLEANUP_NEW_IF_NEEDED。這是 fixture 必須精確表達情境的地方。
    pmode = { cleanup_stuck: false, partial: false, boots: 0 }
    plc = lambda do |*args|
      case args.first
      when "bootstrap"
        plive[:hour] = pdisk.call                      # job 活起來了
        pmode[:partial] ? { ok: false, status: 5, out: "", err: "Bootstrap failed: 5" }
                        : { ok: true, status: 0, out: "", err: "" }
      when "bootout"
        pmode[:boots] += 1
        stuck = pmode[:cleanup_stuck] && pmode[:boots] > 1   # 第 1 次是 OLD_STOP
        plive[:hour] = nil unless stuck
        { ok: true, status: 0, out: "", err: "" }
      when "print" then { ok: !plive[:hour].nil?, status: plive[:hour] ? 0 : 113, out: "", err: "" }
      else { ok: false, status: 1, out: "", err: "" }
      end
    end

    # (a) 首次安裝 partial activation：清得掉 → 乾淨失敗、不留 plist、不留 job
    pmode[:partial] = true
    acode = begin
      OMOS::Schedule.install(home: phome, launchctl: plc)
      nil
    rescue OMOS::Schedule::Failed => e
      e.code
    end
    C.check("§1.1 首次安裝 partial activation → 清掉新 job、不留假安裝",
            "#{acode}／plist=#{File.exist?(ppath)}／live=#{plive[:hour].inspect}",
            acode == "SCHEDULE_LAUNCHCTL_BOOTSTRAP_FAILED" &&
            !File.exist?(ppath) && plive[:hour].nil?)

    # (b) 升級 partial activation：清得掉 → 還原舊版並恢復 live
    pmode[:partial] = false
    OMOS::Schedule.install(home: phome, anchor_hour: 16, launchctl: plc)
    pmode[:partial] = true
    bcode = begin
      OMOS::Schedule.install(home: phome, anchor_hour: 15, launchctl: plc)
      nil
    rescue OMOS::Schedule::Failed => e
      e.code
    end
    C.check("§1.1 升級 partial activation → 清掉新 job 後還原舊版",
            "#{bcode}／disk=#{pdisk.call}／live=#{plive[:hour]}",
            bcode == "SCHEDULE_LAUNCHCTL_BOOTSTRAP_FAILED" &&
            pdisk.call == 16 && plive[:hour] == 16)

    # (c) partial activation 清不掉 → dirty failure，磁碟保留**新版**與 live 一致
    pmode[:cleanup_stuck] = true
    pmode[:boots] = 0
    ccode = begin
      OMOS::Schedule.install(home: phome, anchor_hour: 15, launchctl: plc)
      nil
    rescue OMOS::Schedule::Failed => e
      e.code
    end
    C.check("§1.3.2 partial activation 清不掉 → dirty failure，磁碟保留新版",
            "#{ccode}／disk=#{pdisk.call}／live=#{plive[:hour]}",
            ccode == "SCHEDULE_PARTIAL_ACTIVATION_NOT_CLEANED" &&
            pdisk.call == 15 && plive[:hour] == 15)
    C.check("§1.3.2 dirty failure 下磁碟與 live 仍一致（不得 disk=old／live=new）",
            "#{pdisk.call}/#{plive[:hour]}", pdisk.call == plive[:hour])
  end

  # ── §1.2 第四象限：bootout exit 非 0 但其實已停 → 視為成功 ─────────────
  Dir.mktmpdir("omos-3c-a-lifecycle-bootout4") do |bdir|
    bhome = File.join(bdir, "home")
    Support::FakeHome.seed(bhome)
    Open3.capture3({ "HOME" => bhome }, exe, "install", "--home", bhome,
                   "--owner", Support::Fixtures::EMP, "--tenant", "t-acme")
    blive = { on: false }
    blc = lambda do |*args|
      case args.first
      when "bootstrap" then blive[:on] = true; { ok: true, status: 0, out: "", err: "" }
      # bootout 一律回非零，但確實把 job 停掉了——例如它本來就沒載入
      when "bootout" then blive[:on] = false; { ok: false, status: 3, out: "", err: "not loaded" }
      when "print" then { ok: blive[:on], status: blive[:on] ? 0 : 113, out: "", err: "" }
      else { ok: false, status: 1, out: "", err: "" }
      end
    end
    OMOS::Schedule.install(home: bhome, anchor_hour: 16, launchctl: blc)
    up = begin
      OMOS::Schedule.install(home: bhome, anchor_hour: 15, launchctl: blc)
    rescue OMOS::Schedule::Failed => e
      e.code
    end
    C.check("§1.2 bootout exit 非 0 但其實已停 → 視為成功，升級照樣完成",
            up.is_a?(Hash) ? "anchor=#{up[:anchor_hour]}" : up.to_s,
            up.is_a?(Hash) && up[:anchor_hour] == 15 && up[:loaded] == true)
  end

  # ── §1.4 序列化 ───────────────────────────────────────────────────────
  Dir.mktmpdir("omos-3c-a-lifecycle-lock") do |kdir|
    khome = File.join(kdir, "home")
    Support::FakeHome.seed(khome)
    Open3.capture3({ "HOME" => khome }, exe, "install", "--home", khome,
                   "--owner", Support::Fixtures::EMP, "--tenant", "t-acme")
    klive = { on: false }
    inner = { code: :not_run }
    klc = lambda do |*args|
      case args.first
      when "bootstrap"
        # 在交易**進行中**再叫一次 install，模擬第二個 process
        if inner[:code] == :not_run
          inner[:code] = begin
            OMOS::Schedule.install(home: khome, anchor_hour: 17, launchctl: ->(*_) { { ok: true, status: 0, out: "", err: "" } })
            :succeeded
          rescue OMOS::Schedule::Failed => e
            e.code
          end
        end
        klive[:on] = true
        { ok: true, status: 0, out: "", err: "" }
      when "bootout" then klive[:on] = false; { ok: true, status: 0, out: "", err: "" }
      when "print" then { ok: klive[:on], status: klive[:on] ? 0 : 113, out: "", err: "" }
      else { ok: false, status: 1, out: "", err: "" }
      end
    end
    OMOS::Schedule.install(home: khome, anchor_hour: 16, launchctl: klc)
    C.check("§1.4 交易進行中的第二個 install 必須明確失敗（不得兩個都成功）",
            inner[:code].to_s, inner[:code] == "SCHEDULE_LIFECYCLE_BUSY")
    C.check("§1.4 被拒的第二個 install 不得改動磁碟",
            OMOS::Schedule.installed_anchor_hour(OMOS::Schedule.plist_path(khome)).to_s,
            OMOS::Schedule.installed_anchor_hour(OMOS::Schedule.plist_path(khome)) == 16)
    C.check("§1.4 lock 檔不得放進 ~/Library/LaunchAgents",
            OMOS::Schedule.lock_path(khome).sub(khome, "~"),
            !OMOS::Schedule.lock_path(khome).include?("Library/LaunchAgents"))
  end

  # ── §1.4 真併發：lock 之前不得讀任何 authoritative state ──────────────
  #
  # 上一輪 reviewer 的重播：install 在 lock **之前**讀到 existing=true 就停住，
  # remove 取得 lock 正常移除 plist，install 再繼續時仍用那份過期快照 →
  # Errno::ENOENT。有 flock 卻用 lock 前的快照，等於序列化只保護了寫入、
  # 沒保護判斷依據。
  Dir.mktmpdir("omos-3c-a-lifecycle-race") do |rdir|
    rhome = File.join(rdir, "home")
    Support::FakeHome.seed(rhome)
    Open3.capture3({ "HOME" => rhome }, exe, "install", "--home", rhome,
                   "--owner", Support::Fixtures::EMP, "--tenant", "t-acme")
    rpath = OMOS::Schedule.plist_path(rhome)

    rlive = { on: false }
    mutex = Mutex.new
    rlc = lambda do |*args|
      mutex.synchronize do
        case args.first
        when "bootstrap" then rlive[:on] = true; { ok: true, status: 0, out: "", err: "" }
        when "bootout" then rlive[:on] = false; { ok: true, status: 0, out: "", err: "" }
        when "print" then { ok: rlive[:on], status: rlive[:on] ? 0 : 113, out: "", err: "" }
        else { ok: false, status: 1, out: "", err: "" }
        end
      end
    end

    OMOS::Schedule.install(home: rhome, anchor_hour: 16, launchctl: rlc)

    # (a) install ↔ remove 真併發：不得出現 ENOENT 之類的過期快照錯誤
    8.times do
      gate = Queue.new
      results = Queue.new
      ts = [
        Thread.new do
          gate.pop
          results << begin
            [:install, OMOS::Schedule.install(home: rhome, anchor_hour: 15, launchctl: rlc)]
          rescue StandardError => e
            [:install, "#{e.class}: #{e.message[0, 40]}"]
          end
        end,
        Thread.new do
          gate.pop
          results << begin
            [:remove, OMOS::Schedule.remove(home: rhome, launchctl: rlc)]
          rescue StandardError => e
            [:remove, "#{e.class}: #{e.message[0, 40]}"]
          end
        end
      ]
      2.times { gate << :go }
      ts.each(&:join)
      outcomes = 2.times.map { results.pop }
      stale = outcomes.select { |_, r| r.is_a?(String) && !r.include?("SCHEDULE_LIFECYCLE_BUSY") }
      C.check("§1.4 install↔remove 真併發不得因過期快照炸出例外",
              stale.inspect, stale.empty?)

      # 收斂：把狀態重設成「有一份 16:00 且 live」再跑下一輪
      begin
        OMOS::Schedule.remove(home: rhome, launchctl: rlc)
      rescue StandardError
        nil
      end
      OMOS::Schedule.install(home: rhome, anchor_hour: 16, launchctl: rlc)
    end

    # (b) 併發後磁碟與 live 必須一致
    final_disk = File.file?(rpath) ? OMOS::Schedule.installed_anchor_hour(rpath) : nil
    C.check("§1.4 併發結束後磁碟與 live 一致",
            "disk=#{final_disk.inspect} live=#{rlive[:on]}",
            (final_disk.nil? && !rlive[:on]) || (!final_disk.nil? && rlive[:on]))

    # (c) 結構性斷言：lock 之前不得讀任何 authoritative state。
    #     這條用靜態檢查，因為修好之後那個競態**從外部已經構造不出來**了
    #     ——構造不出來正是修法生效的證明，但也代表行為測試蓋不到它。
    src_rb = File.read(File.join(OMOS::Contract::ARTIFACT_ROOT, "lib/omos/schedule.rb"))
    %w[install remove].each do |m|
      body = src_rb[/def #{m}\(home:.*?\n    end/m].to_s
      code = body.lines.reject { |l| l.strip.start_with?("#") }.join
      before_lock = code.split("with_lifecycle_lock").first.to_s
      leaked = before_lock.scan(/File\.file\?|File\.binread|File\.exist\?|own\?|loaded\?|plist_label/)
      C.check("§1.4 #{m} 在取得 lock 之前不得讀 authoritative state",
              leaked.inspect, leaked.empty?)
    end
  end

  # ── §1.3 rollback 不得用 loaded? 猜「現在活著的是誰」 ──────────────────
  src = File.read(File.join(OMOS::Contract::ARTIFACT_ROOT, "lib/omos/schedule.rb"))
  restore_body = src[/def restore_old.*?\n    end/m].to_s
  # 斷言的對象是**程式碼**，不是註解——註解裡提到 loaded? 正是在說明為什麼
  # 不用它。濾掉整行註解再檢查。
  restore_code = restore_body.lines.reject { |l| l.strip.start_with?("#") }.join
  C.check("§1.3 restore 路徑不得呼叫 loaded?（不得猜活著的是舊還是新）",
          restore_code.lines.grep(/loaded\?/).inspect,
          !restore_code.include?("loaded?"))
  C.check("§1.3 restore_previous 已不存在（改為只依 SNAPSHOT_OLD 動作）", "",
          !src.include?("def restore_previous"))

  C.group = nil
end

C.report!
