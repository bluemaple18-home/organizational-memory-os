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

module OMOS
  class CLI
    DEFAULT_STORE = File.expand_path("~/.omos/personal-memory/personal.db")

    USAGE = <<~TXT
      用法: omos-personal-memory <command> [options]

        init                    建立／升級本機 store（執行 migration）
        status                  顯示 store 路徑、SQLite 版本、schema 版本、列數
        write --kind K --resource FILE --key KEY [--supersedes REF]
                                寫入一列（寫入前由既有治理 evaluator 判定）
        read                    讀出所有列（權限檢查先於讀取）
        closeout --file FILE    提交一次 weekly closeout
        install [--home DIR]    初始化 store 並註冊到 Codex / Claude Code
        uninstall [--home DIR] [--remove-store]
                                移除本產品註冊（預設保留 Personal Store）
        doctor [--home DIR]     對實物做健康檢查
        journal                 輸出 operation journal（證據，非保護）

      共用選項:
        --store PATH            store 檔案路徑（預設 #{DEFAULT_STORE}）
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
      when "read"     then cmd_read(store_path, out)
      when "closeout" then cmd_closeout(store_path, opts, out)
      when "journal"  then cmd_journal(store_path, out)
      when "install"   then cmd_install(opts, out, err)
      when "uninstall" then cmd_uninstall(opts, out, err)
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
      end.parse!(argv)
      opts
    end

    def usage(io)
      io.puts USAGE
      0
    end

    def surface = Runtime::SURFACES[:cli]

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
      resource = JSON.parse(File.read(opts[:resource]))
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

      closeout = JSON.parse(File.read(opts[:file]))
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

    def cmd_doctor(opts, out)
      home = opts[:home] || Dir.home
      results = Doctor.new(home: home, store_path: opts[:store]).run
      width = results.map { |r| r.id.length }.max
      results.each { |r| out.puts format("%-4s %-#{width}s  %s", r.status, r.id, r.detail) }
      failed = results.reject(&:ok?)
      out.puts
      out.puts "doctor: #{results.size - failed.size}/#{results.size} OK"
      failed.empty? ? 0 : 1
    end

    def cmd_journal(path, out)
      with_runtime(path) { |rt| out.puts JSON.pretty_generate(rt.operation_log) }
      0
    end
  end
end
