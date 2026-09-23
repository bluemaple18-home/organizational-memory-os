# frozen_string_literal: true
#
# omos-personal-memory CLI。
#
# 契約 invariant LOCAL_CLI_AND_HOST_MCP_SHARE_THE_SAME_RUNTIME_AUTHORITY：
# CLI 不因為沒有 Host 就取得捷徑——這裡沒有任何一行直接下 SQL，全部經由
# OMOS::Runtime，因此走的是同一套治理與交易層（no direct DB access path）。

require "json"
require "optparse"
require_relative "runtime"
require_relative "installer"
require_relative "host_config_writer"
require_relative "doctor"
require_relative "inbox"
require_relative "review_queue"
require_relative "review_ledger"
require_relative "schedule"

module OMOS
  class CLI
    DEFAULT_STORE = File.expand_path("~/.omos/personal-memory/personal.db")

    USAGE = <<~TXT
      用法: omos-personal-memory <command> [options]

        init                    建立／升級本機 store（執行 migration）
        status                  顯示 store 路徑、SQLite 版本、schema 版本、列數
        write --kind K --resource FILE --key KEY [--supersedes REF]
                                寫入一列（寫入前由既有治理 evaluator 判定）
        import FILE [--memory-kind KIND]
                                把一個 .md／.txt 匯入成 PersonalMemoryCandidate(PROPOSED)
        inbox list              列出已匯入的 evidence 與對應的 candidate
        review due [--notify] [--anchor-hour H] [--anchor-weekday D]
                                列出本週期待 review 的 candidate（純讀，不做任何處置）
        review history          週期帳：每個 ISO 週一列，MISSING 即「少了哪週」
        review done --period YYYY-Www --item <candidate>=<CATEGORY> [--item ...]
                                把該週期記成已完成（NO_PROMOTION）
        review skip --period YYYY-Www
                                catch-up 期限過後，把該週期明確記成 SKIPPED
        schedule install [--home DIR] [--anchor-hour H] [--anchor-weekday D]
                                安裝週五提醒（macOS launchd LaunchAgent）
        schedule status [--home DIR]
        schedule remove [--home DIR]
        read                    讀出所有列（權限檢查先於讀取）
        closeout --file FILE    提交一次 weekly closeout
        install [--home DIR] [--owner REF --tenant ID]
                                初始化 store 並註冊到已交付的 Host（v1：Claude Code）
                                身分只需設定一次，之後 import 自動沿用；升級不會洗掉
        uninstall [--home DIR] [--remove-store]
                                移除本產品註冊（預設保留 Personal Store）
        rollback [--home DIR]   切回上一個 artifact（只切 pointer，不動 Host 設定）
        doctor [--home DIR]     對實物做健康檢查
        journal                 輸出 operation journal（證據，非保護）

      共用選項:
        --store PATH            store 檔案路徑（預設 #{DEFAULT_STORE}）

      個人身分（install 設定一次；import 可明確覆寫）:
        --owner REF             urn:omos:employee:...
        --tenant ID             tenant_id
    TXT

    def self.run(argv, out: $stdout, err: $stderr)
      new.run(argv, out: out, err: err)
    end

    def run(argv, out: $stdout, err: $stderr)
      command = argv.shift
      opts = parse(argv)
      return usage(out) if command.nil? || %w[-h --help help].include?(command)

      store_path = opts[:store] || DEFAULT_STORE
      case command
      when "init"     then cmd_init(store_path, out)
      when "status"   then cmd_status(store_path, out)
      when "write"    then cmd_write(store_path, opts, out)
      when "import"   then cmd_import(store_path, argv, opts, out, err)
      when "inbox"    then cmd_inbox(store_path, argv, out, err)
      when "review"   then cmd_review(store_path, argv, opts, out, err)
      when "schedule" then cmd_schedule(store_path, argv, opts, out, err)
      when "read"     then cmd_read(store_path, out)
      when "closeout" then cmd_closeout(store_path, opts, out)
      when "journal"  then cmd_journal(store_path, out)
      when "install"   then cmd_install(opts, out, err)
      when "uninstall" then cmd_uninstall(opts, out, err)
      when "rollback"  then cmd_rollback(opts, out)
      when "doctor"    then cmd_doctor(opts, out)
      else
        err.puts "未知指令: #{command}"
        usage(err)
        2
      end
    rescue Installer::Failed => e
      err.puts "INSTALL FAILED #{e.code}"
      err.puts "  已從備份還原，未留下半套安裝。"
      1
    rescue HostConfigWriter::RefusedWrite => e
      err.puts "REFUSED #{e.code}"
      err.puts "  設定檔未被修改。"
      1
    rescue Runtime::Rejected => e
      # 治理層拒絕：明確失敗，不 silent fallback。
      err.puts "REJECTED #{e.code}"
      err.puts "  #{e.detail}" if e.detail
      1
    rescue Store::VersionUnsafe => e
      err.puts "UNSAFE #{e.message}"
      1
    end

    private

    def parse(argv)
      opts = {}
      OptionParser.new do |o|
        o.on("--store PATH") { |v| opts[:store] = v }
        o.on("--kind KIND") { |v| opts[:kind] = v }
        o.on("--resource FILE") { |v| opts[:resource] = v }
        o.on("--key KEY") { |v| opts[:key] = v }
        o.on("--supersedes REF") { |v| opts[:supersedes] = v }
        o.on("--file FILE") { |v| opts[:file] = v }
        o.on("--home DIR") { |v| opts[:home] = v }
        o.on("--remove-store") { opts[:remove_store] = true }
        o.on("--memory-kind KIND") { |v| opts[:memory_kind] = v }
        o.on("--owner REF") { |v| opts[:owner] = v }
        o.on("--tenant ID") { |v| opts[:tenant] = v }
        o.on("--notify") { opts[:notify] = true }
        o.on("--anchor-hour H", Integer) { |v| opts[:anchor_hour] = v }
        o.on("--anchor-weekday D", Integer) { |v| opts[:anchor_weekday] = v }
        o.on("--period W") { |v| opts[:period] = v }
        o.on("--item PAIR") { |v| (opts[:items] ||= []) << v }
        o.on("--dispositions FILE") { |v| opts[:dispositions] = v }
      end.parse!(argv)
      opts
    end

    def usage(io)
      io.puts USAGE
      0
    end

    def surface = Runtime::SURFACES[:cli]

    # 匯入身分的解析順序（Owner 裁決 2026-09-21）：
    #
    #   明確參數 > install receipt 保存的 > （測試／暫時相容）環境變數 > fail closed
    #
    # 不新增 identity 檔、不新增第二套 vocabulary：receipt 只是保存**使用者
    # 在 install 時明確設定過**的值，欄位名沿用既有的 employee_owner_ref／
    # tenant_id。它不是 identity authority。
    #
    # 為什麼不從 SessionStart 推：HostSessionBinding 只有 executor_ref／
    # executor_session_ref／cwd／project_ref／effective_scope，**沒有**
    # employee_owner_ref 與 tenant_id。從那裡硬推等於造一份假的 mapping。
    #
    # 環境變數排在 receipt 之後且只在沒有 receipt 身分時才採用，並且會出聲：
    # 它太容易隨 shell／session 漂移，適合測試或暫時相容，不適合當長期來源。
    # 三者都沒有就當場失敗——猜一個 owner 會讓整條 evidence 鏈掛在錯的人身上。
    # review P1-1：原本逐欄 fallback，於是 receipt=emp-A/t-A 時
    # `import --owner emp-B` 會拼出 **emp-B / t-A**——一個從來不存在的身分組合，
    # 而且 rc=0 靜默寫進 Candidate。
    #
    # 身分是一個 **tuple**，不是兩個獨立欄位：整組取自同一個來源，或整組不取。
    # 只給一半視為輸入錯誤，不往下一個來源補。
    def import_identity(opts, err)
      explicit_owner = presence(opts[:owner])
      explicit_tenant = presence(opts[:tenant])
      if explicit_owner || explicit_tenant
        if explicit_owner.nil? || explicit_tenant.nil?
          raise Inbox::IdentityIncomplete,
                "--owner 與 --tenant 必須一起給（身分是一組，不能只覆寫一半）"
        end
        return [explicit_owner, explicit_tenant]
      end

      stored = installed_identity
      s_owner = presence(stored["employee_owner_ref"])
      s_tenant = presence(stored["tenant_id"])
      return [s_owner, s_tenant] if s_owner && s_tenant

      env_owner = presence(ENV["OMOS_EMPLOYEE_REF"])
      env_tenant = presence(ENV["OMOS_TENANT_ID"])
      if env_owner && env_tenant
        err.puts "[omos-personal-memory] 身分取自環境變數（測試／暫時相容用）。" \
                 "長期請用 install --owner/--tenant 寫進 receipt。"
        return [env_owner, env_tenant]
      end

      raise Inbox::IdentityRequired, "employee_owner_ref、tenant_id"
    end

    def presence(v) = v.is_a?(String) && !v.strip.empty? ? v.strip : nil

    def installed_identity(path = File.expand_path(Installer::RECEIPT_PATH))
      installed_identity_at(path)
    end

    def installed_identity_at(path)
      return {} unless File.file?(path)

      (JSON.parse(File.read(path))["personal_identity"] || {})
    rescue JSON::ParserError
      {}
    end

    def cmd_import(path, argv, opts, out, err)
      source = argv.shift
      if source.nil?
        err.puts "import 需要一個檔案路徑"
        return 2
      end

      owner, tenant = import_identity(opts, err)
      with_runtime(path) do |rt|
        result = Inbox.import(rt, path, source, memory_kind: opts[:memory_kind],
                                                owner_ref: owner, tenant_id: tenant,
                                                surface: surface)
        out.puts result[:status]
        out.puts "  evidence:  #{result[:evidence_ref]}"
        out.puts "  sha256:    #{result[:content_sha256]}"
        if result[:status] == "CANDIDATE_PROPOSED"
          out.puts "  candidate: #{result[:candidate_id]}（PROPOSED）"
          out.puts "  link:      #{result[:link_id]}"
          out.puts "  （重放，未新增任何一列）" if result[:replayed]
        else
          out.puts "  #{result[:detail]}"
        end
      end
      0
    rescue Inbox::IdentityIncomplete => e
      err.puts "INBOX_OWNER_IDENTITY_INCOMPLETE: #{e.message}"
      2
    rescue Inbox::IdentityRequired => e
      err.puts "INBOX_OWNER_IDENTITY_REQUIRED: 缺 #{e.message}"
      err.puts "  設定一次即可： omos-personal-memory install --owner urn:omos:employee:… --tenant t-…"
      err.puts "  或這次明確指定： import FILE --owner … --tenant …"
      2
    rescue EvidenceSnapshot::Rejected => e
      err.puts e.code
      err.puts "  #{e.detail}" if e.detail
      2
    end

    def cmd_inbox(path, argv, out, err)
      sub = argv.shift
      unless sub == "list"
        err.puts "用法: omos-personal-memory inbox list"
        return 2
      end

      with_runtime(path) do |rt|
        entries = Inbox.entries(rt, path, surface: surface)
        if entries.empty?
          out.puts "inbox 是空的（尚未匯入任何檔案）"
        else
          entries.each do |e|
            out.puts "#{e["content_sha256"][0, 12]}  #{e["candidate_status"]}"
            out.puts "  檔案:     #{e["original_filename"]}（#{e["captured_at"]}）"
            out.puts "  memory_kind: #{e["memory_kind"] || "—"}"
            out.puts "  evidence 可驗證: #{e["evidence_verifiable"] ? "是" : "否"}"
          end
          out.puts "\n共 #{entries.size} 筆"
        end
      end
      0
    end

    def with_runtime(path)
      rt = Runtime.open(path)
      begin
        yield rt
      ensure
        rt.store.close
      end
    end

    def cmd_init(path, out)
      with_runtime(path) do |rt|
        out.puts "store: #{path}"
        out.puts "schema_version: #{rt.store.schema_version}"
        out.puts "migration receipts: #{rt.store.migration_receipts.size}"
      end
      0
    end

    def cmd_status(path, out)
      unless File.exist?(path)
        out.puts "store 不存在: #{path}（先執行 init）"
        return 1
      end
      with_runtime(path) do |rt|
        s = rt.store
        out.puts "store:           #{path}"
        out.puts "sqlite_version:  #{s.sqlite_version}（產品連線回報）"
        out.puts "journal_mode:    #{s.journal_mode}"
        out.puts "schema_version:  #{s.schema_version}"
        out.puts "rows:            #{s.rows.size}"
      end
      0
    end

    def cmd_write(path, opts, out)
      %i[kind resource key].each do |required|
        raise ArgumentError, "缺少 --#{required}" if opts[required].nil?
      end
      resource = JSON.parse(File.read(opts[:resource], encoding: "UTF-8"))
      with_runtime(path) do |rt|
        result = rt.write_row(kind: opts[:kind], resource: resource, idempotency_key: opts[:key],
                              supersedes_ref: opts[:supersedes], surface: surface)
        out.puts(result[:replayed] ? "REPLAYED #{result[:row_id]}" : "WROTE #{result[:row_id]}")
      end
      0
    end

    def cmd_read(path, out)
      with_runtime(path) do |rt|
        rt.read_rows(surface: surface).each do |row|
          out.puts "#{row[:kind]}\t#{row[:row_id]}#{row[:supersedes_ref] ? "\tsupersedes #{row[:supersedes_ref]}" : ""}"
        end
      end
      0
    end

    def cmd_closeout(path, opts, out)
      raise ArgumentError, "缺少 --file" if opts[:file].nil?

      closeout = JSON.parse(File.read(opts[:file], encoding: "UTF-8"))
      with_runtime(path) do |rt|
        result = rt.commit_closeout(closeout: closeout, surface: surface)
        out.puts "COMMITTED #{result[:review_period_id]} terminal=#{result[:terminal]}"
      end
      0
    end

    # review due 只準備 queue 與回報。契約把 acceptance authority 封死在每個
    # Candidate 自己的 gate 上，批次確認本身不能接受任何東西——所以這裡沒有
    # 週期帳與補做。CLI 只正規化與組 payload，合法性一律交既有
    # Runtime.commit_closeout 與 weekly_closeout_history evaluator。
    def anchor_opts(opts)
      { anchor_hour: opts[:anchor_hour] || ReviewQueue::DEFAULT_ANCHOR_HOUR,
        anchor_weekday: opts[:anchor_weekday] || ReviewQueue::FRIDAY }
    end

    def weekly_origin(path)
      receipt = File.expand_path(Installer::RECEIPT_PATH)
      receipt = File.join(File.dirname(path), "install-receipt.json") unless File.file?(receipt)
      return nil unless File.file?(receipt)

      JSON.parse(File.read(receipt))["weekly_review_origin_at"]
    rescue JSON::ParserError
      nil
    end

    def cmd_review_history(path, opts, out, err)
      origin = weekly_origin(path)
      if origin.nil?
        err.puts "REVIEW_HISTORY_NO_ORIGIN"
        err.puts "  找不到 weekly_review_origin_at——請先跑 install。"
        return 2
      end

      with_runtime(path) do |rt|
        rows = ReviewLedger.history(rt, origin, **anchor_opts(opts))
        out.puts "週期帳（自 #{origin} 起）"
        rows.each do |r|
          mark = r["status"] == "MISSING" ? "x" : "v"
          out.puts "  #{mark} #{r["period"]}  #{r["status"].ljust(13)} " \
                   "起 #{r["scheduled_review_period_start"]}  attempts=#{r["attempts"]}"
        end
        missing = rows.count { |r| r["status"] == "MISSING" }
        out.puts "\n共 #{rows.size} 週，其中 #{missing} 週未完成。"
        out.puts "補做： omos-personal-memory review done --period <YYYY-Www> …" if missing.positive?
      end
      0
    end

    def parse_dispositions(opts)
      from_file = opts[:dispositions] ? JSON.parse(File.read(opts[:dispositions])) : {}
      (opts[:items] || []).each_with_object(from_file) do |pair, acc|
        ref, category = pair.split("=", 2)
        raise ArgumentError, "--item 需要 <candidate-urn>=<CATEGORY>：#{pair}" if category.nil?

        acc[ref] = category
      end
    end

    def cmd_review_closeout(path, opts, out, err, mode)
      if opts[:period].nil?
        err.puts "REVIEW_PERIOD_REQUIRED"
        err.puts "  必須明確指定週期，例如 --period 2026-W38。"
        err.puts "  （不自動猜本週：下週補上週、同週做兩次時會分不清。）"
        return 2
      end

      period = ReviewLedger.period_from_iso_week(opts[:period], **anchor_opts(opts))
      with_runtime(path) do |rt|
        payload = if mode == :done
                    ReviewLedger.build_done(rt, period, parse_dispositions(opts), surface: surface)
                  else
                    ReviewLedger.build_skip(rt, period)
                  end
        result = rt.commit_closeout(closeout: payload, surface: surface)
        out.puts "COMMITTED #{result[:review_period_id]}"
        out.puts "  final_status: #{payload["final_status"]}"
        out.puts "  attempt_kind: #{payload["attempt_kind"]}"
        out.puts "  terminal:     #{result[:terminal]}"
      end
      0
    rescue ReviewLedger::Rejected => e
      err.puts e.code
      err.puts "  #{e.message}"
      2
    rescue ArgumentError => e
      err.puts "REVIEW_ARGUMENT_INVALID"
      err.puts "  #{e.message}"
      2
    end

    # 任何寫入路徑，連「標記已讀」都沒有。
    def cmd_review(path, argv, opts, out, err)
      sub = argv.shift
      case sub
      when "history" then return cmd_review_history(path, opts, out, err)
      when "done"    then return cmd_review_closeout(path, opts, out, err, :done)
      when "skip"    then return cmd_review_closeout(path, opts, out, err, :skip)
      when "due"     then nil
      else
        err.puts "用法: omos-personal-memory review due|history|done|skip"
        return 2
      end

      with_runtime(path) do |rt|
        q = ReviewQueue.due(rt, **anchor_opts(opts), surface: surface)
        notified = opts[:notify] ? Schedule.notify(q[:items].size, io: err) : nil
        out.puts "review period: #{q[:id]}"
        out.puts "  anchor:       #{q[:scheduled_anchor_at]}（起始 #{q[:scheduled_review_period_start]}）"
        out.puts "  catch-up 截止: #{q[:catch_up_deadline_at]}#{q[:catch_up_deadline_passed] ? "（已過）" : ""}"
        out.puts "  本期 terminal closeout: #{q[:terminal_closeout] ? "已提交" : "尚未提交"}"
        if q[:items].empty?
          out.puts "0 due items"
        else
          out.puts "本週有 #{q[:items].size} 筆待 review："
          q[:items].each do |i|
            out.puts "  #{i["candidate_id"].split(":").last[0, 8]}  #{i["memory_kind"]}  #{i["created_at"]}"
          end
        end
        out.puts "  通知: #{notified[:notified] ? "已送出" : "未送出（#{notified[:reason] || "失敗"}）"}" if notified
      end
      0
    end

    # schedule 只碰 launchd 與自己那一支 plist，不碰 store。
    def cmd_schedule(path, argv, opts, out, err)
      sub = argv.shift
      home = opts[:home] || Dir.home
      case sub
      when "install"
        r = Schedule.install(home: home,
                             anchor_hour: opts[:anchor_hour] || ReviewQueue::DEFAULT_ANCHOR_HOUR,
                             anchor_weekday: opts[:anchor_weekday] || ReviewQueue::FRIDAY)
        out.puts(r[:replaced] ? "SCHEDULE_REPLACED" : "SCHEDULE_INSTALLED")
        out.puts "  label:  #{r[:label]}"
        out.puts "  plist:  #{r[:plist]}"
        out.puts "  觸發:   每週#{%w[日 一 二 三 四 五 六][r[:anchor_weekday]]} " \
                 "#{r[:anchor_hour]}:00（本機時區）＋ RunAtLoad 補喚醒"
        out.puts "  已載入: #{r[:loaded] ? "是" : "否"}"
      when "status"
        with_runtime(path) do |rt|
          st = Schedule.status(home: home, runtime: rt, surface: surface)
          out.puts "schedule: #{st[:installed] ? "已安裝且已載入" : "未安裝"}（#{st[:label]}）"
          out.puts "  plist:         #{st[:plist_present] ? (st[:plist_is_ours] ? "存在（本產品）" : "存在但不是本產品的") : "不存在"}"
          out.puts "  launchd job:   #{st[:loaded] ? "已載入" : "未載入"}"
          out.puts "  anchor:        每週#{%w[日 一 二 三 四 五 六][st[:effective_anchor_weekday]]} " \
                   "#{st[:effective_anchor_hour]}:00#{st[:anchor_hour].nil? ? "（plist 未宣告或不一致，採預設）" : ""}"
          out.puts "  period:        #{st[:period]}"
          out.puts "  排定於:        #{st[:scheduled_anchor_at]}"
          out.puts "  catch-up 截止: #{st[:catch_up_deadline_at]}#{st[:overdue] ? "（逾期）" : ""}"
          out.puts "  待 review:     #{st[:due_count]} 筆"
          out.puts "  本期 terminal closeout: #{st[:terminal_closeout] ? "已提交" : "尚未提交"}"
          out.puts "  逾期不等於 SKIPPED——terminal disposition 仍須人工 closeout。" if st[:overdue]
        end
      when "remove"
        r = Schedule.remove(home: home)
        if r[:removed]
          out.puts "SCHEDULE_REMOVED"
        else
          out.puts "SCHEDULE_NOT_REMOVED（#{r[:reason]}）"
          out.puts "  該路徑的 plist 內部 Label 是 #{r[:found_label].inspect}，不是本產品的，未動。" if r[:reason] == "NOT_OURS"
        end
      else
        err.puts "用法: omos-personal-memory schedule install|status|remove"
        return 2
      end
      0
    rescue Schedule::Failed => e
      err.puts e.code
      err.puts "  #{e.message}"
      2
    end

    def installer_for(opts)
      home = opts[:home] || Dir.home
      # 只有兩個都給才算「這次明確設定身分」。給一半是輸入錯誤，不是部分更新
      # ——半組身分寫進 receipt 之後，import 會拿到一個永遠湊不齊的來源。
      identity = if presence(opts[:owner]) && presence(opts[:tenant])
                   { "employee_owner_ref" => opts[:owner].strip, "tenant_id" => opts[:tenant].strip }
                 end
      Installer.new(home: home, store_path: opts[:store], personal_identity: identity)
    end

    def cmd_install(opts, out, err)
      if presence(opts[:owner]).nil? ^ presence(opts[:tenant]).nil?
        err.puts "INSTALL_IDENTITY_INCOMPLETE: --owner 與 --tenant 必須一起給"
        return 2
      end

      inst = installer_for(opts)
      result = inst.install
      out.puts "INSTALLED"
      out.puts "  store:   #{result[:store_path]} (schema #{result[:schema_version]})"
      out.puts "  hosts:   #{result[:hosts].join(", ")}"
      out.puts "  receipt: #{inst.receipt_path}"
      ident = installed_identity_at(inst.receipt_path)
      if ident["employee_owner_ref"]
        out.puts "  身分:    #{ident["employee_owner_ref"]} / #{ident["tenant_id"]}"
      else
        out.puts "  身分:    尚未設定（import 時再補 --owner/--tenant，或重跑 install 帶上）"
      end
      out.puts "接著執行 `omos-personal-memory doctor` 確認。"
      0
    end

    def cmd_uninstall(opts, out, _err)
      inst = installer_for(opts)
      result = inst.uninstall(remove_store: opts[:remove_store] == true)
      out.puts "UNINSTALLED hosts=#{result[:hosts].join(", ")}"
      out.puts(result[:store_removed] ? "  Personal Store 已移除。" :
               "  Personal Store 保留於 #{inst.store_path}（--remove-store 才會刪除）。")
      0
    end

    def cmd_rollback(opts, out)
      inst = installer_for(opts)
      result = inst.rollback
      out.puts "ROLLED BACK"
      out.puts "  目前 artifact: #{result[:artifact_id]}"
      out.puts "  可再切回:      #{result[:previous_artifact_id]}"
      out.puts "  Host 設定未變動——Host 認的是固定 launcher，與版本無關。"
      0
    end

    def cmd_doctor(opts, out)
      home = opts[:home] || Dir.home
      results = Doctor.new(home: home, store_path: opts[:store]).run
      width = results.map { |r| r.id.length }.max
      results.each { |r| out.puts format("%-4s %-#{width}s  %s", r.status, r.id, r.detail) }
      failed = results.select { |r| r.status == "FAIL" }
      warned = results.select { |r| r.status == "WARN" }
      out.puts
      out.puts "doctor: #{results.count(&:ok?)} OK / #{warned.size} WARN / #{failed.size} FAIL"
      out.puts "  WARN = 這一項在這台機器上無法觀測，不等於健康也不等於失敗。" unless warned.empty?
      failed.empty? ? 0 : 1
    end

    def cmd_journal(path, out)
      with_runtime(path) { |rt| out.puts JSON.pretty_generate(rt.operation_log) }
      0
    end
  end
end
