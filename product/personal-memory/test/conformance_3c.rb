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

C.report!
