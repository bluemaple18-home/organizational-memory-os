# frozen_string_literal: true
#
# 本機 Personal Store：真的開啟 SQLite、真的提交交易、重啟後真的讀得回。
#
# 這一層只負責「儲存」，不做治理判定——治理在 OMOS::Runtime，且發生在寫入
# 之前。schema 裡的 constraint 與 trigger 是 enforcement，不是權威：權威是
# personal_memory_runtime 契約與 correction_flow 的既有禁項。
#
# 交易政策依 Owner 裁決採既有機制，不新造交易管理器：
#   - 寫入一律 BEGIN IMMEDIATE（避免 upgrade deadlock）
#   - PRAGMA journal_mode=WAL、PRAGMA busy_timeout
#   - SQLITE_BUSY 有上限重試，且重試沿用同一把 idempotency key，
#     因此重放必然落回同一列（切片 1 契約已保證）

require "sqlite3"
require "json"
require "time"
require_relative "contract"

module OMOS
  class Store
    class ImmutabilityViolation < StandardError; end
    class VersionUnsafe < StandardError; end

    BUSY_TIMEOUT_MS = 5_000
    BUSY_MAX_RETRIES = 5
    # WAL-reset 可能在多連線同時寫入／checkpoint 時造成資料庫損毀，修復於此版。
    WAL_RESET_FIX = "3.51.3"

    # migration 鏈：每一段都必須從上一段的 to_version 接上，並留下不可變 receipt。
    MIGRATIONS = [
      {
        id: "0001-initial-store",
        from: "0.0.0",
        to: "0.1.0",
        sql: <<~SQL
          CREATE TABLE schema_migrations (
            migration_id  TEXT PRIMARY KEY,
            from_version  TEXT NOT NULL,
            to_version    TEXT NOT NULL,
            applied_at    TEXT NOT NULL
          );
          -- receipt_mutation：receipt 一旦寫下不得改寫或刪除
          CREATE TRIGGER schema_migrations_no_update BEFORE UPDATE ON schema_migrations
          BEGIN SELECT RAISE(ABORT, 'receipt_mutation'); END;
          CREATE TRIGGER schema_migrations_no_delete BEFORE DELETE ON schema_migrations
          BEGIN SELECT RAISE(ABORT, 'receipt_mutation'); END;

          CREATE TABLE memory_rows (
            row_id           TEXT PRIMARY KEY,
            kind             TEXT NOT NULL,
            idempotency_key  TEXT NOT NULL UNIQUE,
            supersedes_ref   TEXT REFERENCES memory_rows(row_id),
            canonical        TEXT NOT NULL,
            resource_json    TEXT NOT NULL,
            created_at       TEXT NOT NULL
          );
          -- 一列只能被取代一次（對應 PMR_SUPERSEDES_TARGET_ALREADY_SUPERSEDED）
          CREATE UNIQUE INDEX memory_rows_supersedes_once
            ON memory_rows(supersedes_ref) WHERE supersedes_ref IS NOT NULL;
          -- in_place_record_overwrite / history_erasure：由資料庫本身擋
          CREATE TRIGGER memory_rows_no_update BEFORE UPDATE ON memory_rows
          BEGIN SELECT RAISE(ABORT, 'in_place_record_overwrite'); END;
          CREATE TRIGGER memory_rows_no_delete BEFORE DELETE ON memory_rows
          BEGIN SELECT RAISE(ABORT, 'history_erasure'); END;

          CREATE TABLE closeouts (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            review_period_id  TEXT NOT NULL,
            attempt_seq       INTEGER NOT NULL,
            final_status      TEXT NOT NULL,
            is_terminal       INTEGER NOT NULL,
            payload_json      TEXT NOT NULL,
            committed_at      TEXT NOT NULL
          );
          -- 同一 review_period_id 至多一次 terminal closeout
          CREATE UNIQUE INDEX closeouts_one_terminal
            ON closeouts(review_period_id) WHERE is_terminal = 1;

          CREATE TABLE operation_journal (
            op_seq        INTEGER PRIMARY KEY AUTOINCREMENT,
            surface       TEXT NOT NULL,
            kind          TEXT NOT NULL,
            path_json     TEXT NOT NULL,
            binding_json  TEXT,
            payload_json  TEXT,
            occurred_at   TEXT NOT NULL
          );
        SQL
      }
    ].freeze

    attr_reader :path, :db

    def self.open(path)
      store = new(path)
      store.connect!
      store
    end

    def initialize(path)
      @path = path
    end

    def connect!
      FileUtils_mkdir_p(File.dirname(@path))
      @db = SQLite3::Database.new(@path)
      @db.busy_timeout = BUSY_TIMEOUT_MS
      @db.execute("PRAGMA journal_mode=#{Contract.journal_mode}")
      @db.execute("PRAGMA foreign_keys=ON")
      assert_sqlite_version!
      self
    end

    # Owner 指定項：版本必須由**產品實際開啟的這條連線**回報，不能看系統
    # sqlite3 指令，也不能只看 gem 版本號。本機實測三者確實不同。
    def sqlite_version = @db.get_first_value("SELECT sqlite_version()")

    def assert_sqlite_version!
      actual = sqlite_version
      return if version_at_least?(actual, WAL_RESET_FIX)

      raise VersionUnsafe,
            "SQLite #{actual} 低於 WAL-reset 修復版本 #{WAL_RESET_FIX}；" \
            "多連線同時寫入／checkpoint 時可能損毀資料庫"
    end

    def version_at_least?(actual, minimum)
      a = actual.to_s.split(".").map(&:to_i)
      m = minimum.split(".").map(&:to_i)
      (0..2).each do |i|
        return true if a[i].to_i > m[i].to_i
        return false if a[i].to_i < m[i].to_i
      end
      true
    end

    def journal_mode = @db.get_first_value("PRAGMA journal_mode")
    def schema_version = @db.get_first_value("SELECT to_version FROM schema_migrations ORDER BY rowid DESC LIMIT 1")

    def migrate!(now: Time.now.utc.iso8601)
      ensure_bootstrap!
      current = schema_version || Contract.genesis_version
      MIGRATIONS.each do |migration|
        next if migration_applied?(migration[:id])
        next unless migration[:from] == current

        transaction do
          @db.execute_batch(migration[:sql]) unless migration[:id] == "0001-initial-store" && bootstrapped?
          @db.execute(
            "INSERT INTO schema_migrations (migration_id, from_version, to_version, applied_at) VALUES (?,?,?,?)",
            [migration[:id], migration[:from], migration[:to], now]
          )
        end
        current = migration[:to]
      end
      current
    end

    def migration_receipts
      return [] unless table?("schema_migrations")

      @db.execute("SELECT migration_id, from_version, to_version, applied_at FROM schema_migrations ORDER BY rowid")
         .map { |r| { "migration_id" => r[0], "from_version" => r[1], "to_version" => r[2], "applied_at" => r[3] } }
    end

    # BEGIN IMMEDIATE + 有上限的 SQLITE_BUSY 重試。不自建交易管理器。
    def transaction
      attempts = 0
      begin
        @db.execute("BEGIN IMMEDIATE")
        result = yield
        @db.execute("COMMIT")
        result
      rescue SQLite3::BusyException
        rollback_quietly
        attempts += 1
        retry if attempts <= BUSY_MAX_RETRIES
        raise
      rescue StandardError
        rollback_quietly
        raise
      end
    end

    def rows
      @db.execute("SELECT row_id, kind, idempotency_key, supersedes_ref, canonical, resource_json FROM memory_rows ORDER BY rowid")
         .map do |r|
        { row_id: r[0], kind: r[1], idempotency_key: r[2], supersedes_ref: r[3],
          canonical: r[4], resource: JSON.parse(r[5]) }
      end
    end

    def row(row_id)
      rows.find { |r| r[:row_id] == row_id }
    end

    def row_for_key(key)
      rows.find { |r| r[:idempotency_key] == key }
    end

    def closeouts_for(review_period_id)
      @db.execute("SELECT payload_json FROM closeouts WHERE review_period_id = ? ORDER BY attempt_seq", [review_period_id])
         .map { |r| JSON.parse(r[0]) }
    end

    def next_attempt_seq(review_period_id)
      (@db.get_first_value("SELECT MAX(attempt_seq) FROM closeouts WHERE review_period_id = ?", [review_period_id]) || 0) + 1
    end

    def journal
      @db.execute("SELECT op_seq, surface, kind, path_json, binding_json, payload_json FROM operation_journal ORDER BY op_seq")
    end

    def close = @db&.close

    private

    def rollback_quietly
      @db.execute("ROLLBACK")
    rescue SQLite3::SQLException
      nil
    end

    def table?(name)
      !@db.get_first_value("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [name]).nil?
    end

    def bootstrapped? = table?("memory_rows")

    def ensure_bootstrap!
      return if table?("schema_migrations")

      @db.execute_batch(MIGRATIONS.first[:sql])
    end

    def migration_applied?(id)
      !@db.get_first_value("SELECT 1 FROM schema_migrations WHERE migration_id = ?", [id]).nil?
    end

    def FileUtils_mkdir_p(dir)
      require "fileutils"
      FileUtils.mkdir_p(dir)
    end
  end
end
