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
        read                    讀出所有列（權限檢查先於讀取）
        closeout --file FILE    提交一次 weekly closeout
        install [--home DIR]    初始化 store 並註冊到已交付的 Host（v1：Claude Code）
        uninstall [--home DIR] [--remove-store]
                                移除本產品註冊（預設保留 Personal Store）
        rollback [--home DIR]   切回上一個 artifact（只切 pointer，不動 Host 設定）
        doctor [--home DIR]     對實物做健康檢查
        journal                 輸出 operation journal（證據，非保護）

      共用選項:
        --store PATH            store 檔案路徑（預設 #{DEFAULT_STORE}）

      匯入身分（import 需要，flag 優先於環境變數）:
        --owner REF             urn:omos:employee:...（或 OMOS_EMPLOYEE_REF）
        --tenant ID             tenant_id（或 OMOS_TENANT_ID）
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
      end.parse!(argv)
      opts
    end

    def usage(io)
      io.puts USAGE
      0
    end

    def surface = Runtime::SURFACES[:cli]

    # 匯入身分：flag 優先，其次環境變數。
    #
    # 刻意**不**新增第二套身分資料：契約明寫綁定 Host 時要沿用既有的 executor
    # identity，不得另立 identity vocabulary。產品目前沒有任何地方存過員工
    # 身分（write 的 tenant_id／employee_owner_ref 一直都由呼叫端的 resource
    # JSON 自己帶），所以這裡也不偷偷開一份 identity 檔——缺就當場失敗，
    # 並說清楚要補什麼。猜一個 owner 會讓整條 evidence 鏈掛在錯的人身上。
    def import_identity(opts)
      owner = opts[:owner] || ENV["OMOS_EMPLOYEE_REF"]
      tenant = opts[:tenant] || ENV["OMOS_TENANT_ID"]
      missing = []
      missing << "--owner（或 OMOS_EMPLOYEE_REF）" if owner.nil? || owner.strip.empty?
      missing << "--tenant（或 OMOS_TENANT_ID）" if tenant.nil? || tenant.strip.empty?
      return [owner, tenant] if missing.empty?

      raise Inbox::IdentityRequired, missing.join("、")
    end

    def cmd_import(path, argv, opts, out, err)
      source = argv.shift
      if source.nil?
        err.puts "import 需要一個檔案路徑"
        return 2
      end

      owner, tenant = import_identity(opts)
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
    rescue Inbox::IdentityRequired => e
      err.puts "INBOX_OWNER_IDENTITY_REQUIRED: 缺 #{e.message}"
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

    def installer_for(opts)
      home = opts[:home] || Dir.home
      Installer.new(home: home, store_path: opts[:store])
    end

    def cmd_install(opts, out, err)
      inst = installer_for(opts)
      result = inst.install
      out.puts "INSTALLED"
      out.puts "  store:   #{result[:store_path]} (schema #{result[:schema_version]})"
      out.puts "  hosts:   #{result[:hosts].join(", ")}"
      out.puts "  receipt: #{inst.receipt_path}"
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
