# frozen_string_literal: true
#
# EMEM-11 切片 3a 前置預檢（隔離環境）。
#
# 這支只回答「鎖定的環境能不能撐起產品」，不做任何 Host 整合。
# 其中 SQLite 版本檢查是 Owner 指定的必要項：WAL-reset 在多連線同時
# 寫入／checkpoint 的罕見情況下可能造成資料庫損毀，修復於 3.51.3。
# 必須由「產品實際開啟的那條連線」回報版本，不能看系統 sqlite3 指令，
# 也不能只看 gem 版本號。這一項之後要放進 installer／doctor。

require "sqlite3"
require "mcp"
require "tmpdir"

WAL_RESET_FIX = "3.51.3"

def cmp(a, b)
  pa = a.split(".").map(&:to_i)
  pb = b.split(".").map(&:to_i)
  (0..2).each { |i| return (pa[i].to_i <=> pb[i].to_i) unless pa[i].to_i == pb[i].to_i }
  0
end

results = []
def check(results, name, detail, ok)
  results << [ok ? "PASS" : "FAIL", name, detail]
end

check(results, "Ruby 版本", RUBY_VERSION, RUBY_VERSION == "3.4.10")
check(results, "sqlite3 gem", SQLite3::VERSION, cmp(SQLite3::VERSION, "2.0.0") >= 0)
check(results, "mcp gem 可載入", MCP::VERSION, defined?(MCP::VERSION) ? true : false)

Dir.mktmpdir("omos-preflight") do |dir|
  path = File.join(dir, "store.db")
  db = SQLite3::Database.new(path)

  # Owner 指定項：由產品實際連線回報的 SQLite 版本
  lib_version = db.get_first_value("SELECT sqlite_version()")
  check(results, "SQLite（產品連線回報）", lib_version,
        cmp(lib_version, WAL_RESET_FIX) >= 0)

  mode = db.get_first_value("PRAGMA journal_mode=WAL")
  check(results, "journal_mode=WAL 實際生效", mode.to_s, mode.to_s.downcase == "wal")

  db.execute("PRAGMA busy_timeout=5000")
  bt = db.get_first_value("PRAGMA busy_timeout")
  check(results, "busy_timeout 可設定", bt.to_s, bt.to_i == 5000)

  db.execute("CREATE TABLE probe (id TEXT PRIMARY KEY, body TEXT NOT NULL)")

  # BEGIN IMMEDIATE：commit 要落地
  db.execute("BEGIN IMMEDIATE")
  db.execute("INSERT INTO probe VALUES (?, ?)", ["kept", "committed"])
  db.execute("COMMIT")

  # rollback 要真的丟棄
  db.execute("BEGIN IMMEDIATE")
  db.execute("INSERT INTO probe VALUES (?, ?)", ["dropped", "rolled-back"])
  db.execute("ROLLBACK")

  check(results, "BEGIN IMMEDIATE + COMMIT 落地",
        db.get_first_value("SELECT body FROM probe WHERE id='kept'").to_s,
        db.get_first_value("SELECT COUNT(*) FROM probe WHERE id='kept'") == 1)
  check(results, "ROLLBACK 真的丟棄", "count=#{db.get_first_value("SELECT COUNT(*) FROM probe WHERE id='dropped'")}",
        db.get_first_value("SELECT COUNT(*) FROM probe WHERE id='dropped'") == 0)

  # UNIQUE 違反要拋，不能靜默
  raised = begin
    db.execute("INSERT INTO probe VALUES (?, ?)", ["kept", "dup"])
    false
  rescue SQLite3::ConstraintException
    true
  end
  check(results, "UNIQUE 違反會拋出（不靜默）", raised ? "ConstraintException" : "無例外", raised)

  db.close

  # 重啟持久化：關掉再開，讀得回來
  db2 = SQLite3::Database.new(path)
  persisted = db2.get_first_value("SELECT body FROM probe WHERE id='kept'")
  wal_after_reopen = db2.get_first_value("PRAGMA journal_mode")
  db2.close
  check(results, "關閉後重開仍讀得回", persisted.to_s, persisted == "committed")
  check(results, "WAL 模式隨檔案持久", wal_after_reopen.to_s, wal_after_reopen.to_s.downcase == "wal")
end

# MCP stdio 依賴可用（只確認相依，不展開 Host 整合）
stdio = defined?(MCP::Server::Transports::StdioTransport) ? "StdioTransport" : nil
check(results, "MCP stdio transport 類別存在", stdio.to_s, !stdio.nil?)

width = results.map { |_, name, _| name.length }.max
results.each { |st, name, detail| puts format("%-4s %-#{width}s  %s", st, name, detail) }
failed = results.count { |st, _, _| st == "FAIL" }
puts "\n預檢結果：#{results.size - failed}/#{results.size} PASS"
exit(failed.zero? ? 0 : 1)
