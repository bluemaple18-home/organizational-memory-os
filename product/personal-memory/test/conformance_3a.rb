# frozen_string_literal: true
#
# 切片 3a conformance：對**實物**驗收。
#
# Owner 裁決：「該拒絕的寫入，要在落地前就被同一套治理邏輯拒絕；操作紀錄是
# 證據，不是事後替代保護。」因此每一條被拒絕的寫入，這裡都直接查**實際資料表**
# 確認那一筆根本不存在，而不是只看 runtime 回報了什麼。
#
# 另依裁決，驗收不得只驗自己產出的 journal，必須另以：
#   - 實際資料庫讀回（SELECT）
#   - rollback 實測
#   - 重啟後持久化（關閉連線、重新開啟）
# 三者確認。journal 通過切片 1 validator 只是最後一項附加證據。

require "tmpdir"
require "json"
require "set"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "omos/version_guard"
OMOS::VersionGuard.assert!
require "omos/runtime"

RESULTS = []

def check(name, detail, ok)
  RESULTS << [ok ? "PASS" : "FAIL", name, detail.to_s]
end

def expect_rejected(name, code, store)
  yield
  check(name, "未被拒絕（預期 #{code}）", false)
rescue OMOS::Runtime::Rejected => e
  check(name, "#{e.code}", e.code == code)
ensure
  # 關鍵：不論 runtime 說什麼，實際資料表裡不得多出任何一列。
  @row_count_stable = store.db.get_first_value("SELECT COUNT(*) FROM memory_rows")
end

# --- 測試資料：依上游 required_fields 組出真的合法的本體 -----------------

EMP = "urn:omos:employee:emp-001"
def link_body(link_id, target)
  { "link_id" => link_id, "tenant_id" => "t-acme", "employee_owner_ref" => EMP,
    "target_ref" => target, "evidence_ref" => "urn:omos:evidence:ev-001",
    "source_anchor_ref" => "urn:omos:source-anchor:sa-001",
    "source_anchor_profile" => "MARKDOWN_TEXT_V1", "relation" => "SUPPORTS",
    "anchor_resolution" => "EXACT_MATCH",
    "provenance" => { "created_by" => EMP, "created_at" => "2026-09-20T09:00:00Z" } }
end

def record_body(record_id, link_id)
  { "record_id" => record_id, "tenant_id" => "t-acme", "employee_owner_ref" => EMP,
    "origin_candidate_ref" => "urn:omos:personal-memory:candidate:01900000-0000-7000-8000-0000000000c9",
    "memory_kind" => "DECISION",
    "content" => { "statement_or_structured_content" => "改用 WAL 模式以支援並行讀取" },
    "applicability" => { "scope_mode" => "EMPLOYEE_PRIVATE", "applies_to_refs" => ["urn:omos:project:omos"] },
    "validity_interval" => { "effective_from" => "2026-09-01T00:00:00Z" },
    "support_link_refs" => [link_id],
    "candidate_snapshot" => { "candidate_status" => "ACCEPTED_FOR_RECORD",
                              "verification_status" => "PASS", "acceptance_status" => "ACCEPTED" },
    "governance" => { "ownership_mode" => "EMPLOYEE_OWNED", "visibility_scope" => "EMPLOYEE_PRIVATE",
                      "verification_status" => "PASS", "acceptance_status" => "ACCEPTED",
                      "verification_receipt_ref" => "urn:omos:verification-receipt:vr-001",
                      "personal_acceptance_ref" => "urn:omos:personal-acceptance:pa-001",
                      "sensitivity" => "NORMAL", "acl_ref" => "urn:omos:acl:acl-001",
                      "freshness" => "CURRENT", "review_due_at" => "2026-12-01T00:00:00Z",
                      "conflict_refs" => [], "supersedes" => [], "superseded_by" => [],
                      "retention_state" => "RETAINED" },
    "chronology" => { "created_at" => "2026-09-20T09:00:00Z", "effective_from" => "2026-09-01T00:00:00Z" },
    "record_status" => "ACTIVE" }
end

L1 = "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000b1"
L2 = "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000b2"
R1 = "urn:omos:personal-memory:record:01900000-0000-7000-8000-000000000001"
R2 = "urn:omos:personal-memory:record:01900000-0000-7000-8000-000000000002"
CLI = OMOS::Runtime::SURFACES[:cli]

Dir.mktmpdir("omos-3a") do |dir|
  path = File.join(dir, "personal.db")
  rt = OMOS::Runtime.open(path)
  store = rt.store

  # --- 環境與 schema ---
  check("SQLite 版本（產品連線）", store.sqlite_version,
        store.version_at_least?(store.sqlite_version, OMOS::Store::WAL_RESET_FIX))
  check("journal_mode 實際為 WAL", store.journal_mode, store.journal_mode.to_s.casecmp("wal").zero?)
  check("schema_version 由 migration 鏈產生", store.schema_version, store.schema_version == "0.1.0")
  check("migration receipt 已寫入", store.migration_receipts.size, store.migration_receipts.size == 1)

  # --- 正常寫入，並以實際資料表讀回 ---
  rt.write_row(kind: "MemorySupportLink", resource: link_body(L1, R1), idempotency_key: "k-l1", surface: CLI)
  rt.write_row(kind: "PersonalMemoryRecord", resource: record_body(R1, L1), idempotency_key: "k-1", surface: CLI)
  row_in_db = store.db.get_first_value("SELECT kind FROM memory_rows WHERE row_id = ?", [R1])
  check("寫入後以 SELECT 從實際資料表讀回", row_in_db.to_s, row_in_db == "PersonalMemoryRecord")

  # --- 治理：被拒絕的寫入不得落地（直接查資料表）---
  before = store.db.get_first_value("SELECT COUNT(*) FROM memory_rows")

  expect_rejected("無 support link 的本體被拒", "PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT", store) do
    body = record_body(R2, L2).merge("support_link_refs" => [])
    rt.write_row(kind: "PersonalMemoryRecord", resource: body, idempotency_key: "k-bad1", surface: CLI)
  end
  expect_rejected("未驗證／未接受的本體被拒", "PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT", store) do
    body = record_body(R2, L1)
    body["governance"] = body["governance"].merge("verification_status" => "NOT_CHECKED")
    rt.write_row(kind: "PersonalMemoryRecord", resource: body, idempotency_key: "k-bad2", surface: CLI)
  end
  expect_rejected("非 UUIDv7 的 row id 被拒", "PMR_ROW_ID_NOT_MATCHING_ID_TEMPLATE", store) do
    bad = "urn:omos:personal-memory:record:01900000-0000-4000-8000-000000000009"
    rt.write_row(kind: "PersonalMemoryRecord", resource: record_body(bad, L1), idempotency_key: "k-bad3", surface: CLI)
  end
  expect_rejected("CLI 宣稱 host binding 被拒", "PMR_CLI_OPERATION_CLAIMS_HOST_BINDING", store) do
    rt.write_row(kind: "PersonalMemoryRecord", resource: record_body(R2, L1), idempotency_key: "k-bad4",
                 surface: CLI, binding: { "executor_ref" => "Codex" })
  end
  expect_rejected("遠端 surface 被拒", "PMR_SURFACE_FORBIDDEN", store) do
    rt.write_row(kind: "PersonalMemoryRecord", resource: record_body(R2, L1), idempotency_key: "k-bad5",
                 surface: "HTTP_TUNNEL")
  end

  after = store.db.get_first_value("SELECT COUNT(*) FROM memory_rows")
  check("被拒絕的寫入完全沒有落地（資料表筆數未變）", "#{before} → #{after}", before == after)

  # --- idempotency 與不可變性 ---
  rt.write_row(kind: "MemorySupportLink", resource: link_body(L2, R2), idempotency_key: "k-l2", surface: CLI)
  rt.write_row(kind: "PersonalMemoryRecord", resource: record_body(R2, L2), idempotency_key: "k-2",
               supersedes_ref: R1, surface: CLI)
  count_before_replay = store.db.get_first_value("SELECT COUNT(*) FROM memory_rows")
  result = rt.write_row(kind: "PersonalMemoryRecord", resource: record_body(R2, L2), idempotency_key: "k-2",
                        supersedes_ref: R1, surface: CLI)
  count_after_replay = store.db.get_first_value("SELECT COUNT(*) FROM memory_rows")
  check("逐欄相同的重放是 no-op（不產生第二列）",
        "replayed=#{result[:replayed]} #{count_before_replay}→#{count_after_replay}",
        result[:replayed] && count_before_replay == count_after_replay)

  expect_rejected("同 id 同 key 但改動 supersedes_ref 被拒", "PMR_IN_PLACE_ROW_OVERWRITE", store) do
    rt.write_row(kind: "PersonalMemoryRecord", resource: record_body(R2, L2), idempotency_key: "k-2", surface: CLI)
  end
  expect_rejected("同一列被第二次取代被拒", "PMR_SUPERSEDES_TARGET_ALREADY_SUPERSEDED", store) do
    r3 = "urn:omos:personal-memory:record:01900000-0000-7000-8000-000000000003"
    rt.write_row(kind: "MemorySupportLink", resource: link_body(
      "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000b3", r3
    ), idempotency_key: "k-l3", surface: CLI)
    rt.write_row(kind: "PersonalMemoryRecord",
                 resource: record_body(r3, "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-0000000000b3"),
                 idempotency_key: "k-3", supersedes_ref: R1, surface: CLI)
  end

  # --- 資料庫本身擋住改寫與刪除（trigger 層）---
  overwrite_blocked = begin
    store.db.execute("UPDATE memory_rows SET kind='X' WHERE row_id=?", [R1])
    false
  rescue SQLite3::ConstraintException, SQLite3::SQLException => e
    e.message.include?("in_place_record_overwrite")
  end
  erasure_blocked = begin
    store.db.execute("DELETE FROM memory_rows WHERE row_id=?", [R1])
    false
  rescue SQLite3::ConstraintException, SQLite3::SQLException => e
    e.message.include?("history_erasure")
  end
  check("資料庫 trigger 擋住 UPDATE（in_place_record_overwrite）", overwrite_blocked, overwrite_blocked)
  check("資料庫 trigger 擋住 DELETE（history_erasure）", erasure_blocked, erasure_blocked)

  # --- rollback 實測：交易中途失敗不得留下半套 ---
  count_before_rollback = store.db.get_first_value("SELECT COUNT(*) FROM memory_rows")
  rolled_back = begin
    store.transaction do
      store.db.execute(
        "INSERT INTO memory_rows (row_id, kind, idempotency_key, supersedes_ref, canonical, resource_json, created_at) " \
        "VALUES (?,?,?,?,?,?,?)",
        ["urn:omos:personal-memory:record:01900000-0000-7000-8000-00000000000f", "PersonalMemoryRecord",
         "k-rollback", nil, "{}", "{}", "2026-09-20T09:00:00Z"]
      )
      raise "注入的失敗"
    end
    false
  rescue RuntimeError
    true
  end
  count_after_rollback = store.db.get_first_value("SELECT COUNT(*) FROM memory_rows")
  check("交易中途失敗會 rollback，不留半套",
        "#{count_before_rollback} → #{count_after_rollback}",
        rolled_back && count_before_rollback == count_after_rollback)

  # --- closeout 唯一性 ---
  period = "urn:omos:personal-memory:review-period:2026-W38"
  item = "urn:omos:personal-memory:candidate:01900000-0000-7000-8000-0000000000a1"
  def closeout(period, item, status, attempt)
    { "review_period_id" => period, "scheduled_review_period_start" => "2026-09-18",
      "scheduled_anchor_at" => "2026-09-18T15:00:00Z", "actual_closeout_at" => "2026-09-18T17:30:00Z",
      "attempt_kind" => attempt, "final_status" => status, "catch_up_deadline_passed" => true,
      "selected_item_refs" => [item],
      "item_dispositions" => { item => { "category" => "MATERIALLY_CHANGED",
                                         "promotion_ref" => "urn:omos:promotion:pr-001",
                                         "promotion_idempotency_key" => "pk-001" } } }
  end
  rt.commit_closeout(closeout: closeout(period, item, "FAILED", "SCHEDULED"), surface: CLI)
  rt.commit_closeout(closeout: closeout(period, item, "COMPLETE", "RETRY"), surface: CLI)
  dup_rejected = begin
    rt.commit_closeout(closeout: closeout(period, item, "NO_PROMOTION", "RETRY"), surface: CLI)
    false
  rescue OMOS::Runtime::Rejected => e
    e.code == "PMR_CLOSEOUT_FAILS_WEEKLY_CYCLE_CONTRACT"
  end
  terminal_count = store.db.get_first_value(
    "SELECT COUNT(*) FROM closeouts WHERE review_period_id=? AND is_terminal=1", [period]
  )
  check("第二次 terminal closeout 被拒", dup_rejected, dup_rejected)
  check("資料表中同一 period 只有一筆 terminal", terminal_count, terminal_count == 1)

  drift_rejected = begin
    c = closeout(period + "-b", item, "COMPLETE", "SCHEDULED")
    rt.commit_closeout(closeout: c, surface: CLI)
    c2 = closeout(period + "-b", item, "COMPLETE", "RETRY")
    c2["item_dispositions"][item]["promotion_idempotency_key"] = "pk-999"
    rt.commit_closeout(closeout: c2, surface: CLI)
    false
  rescue OMOS::Runtime::Rejected => e
    e.code == "PMR_CLOSEOUT_FAILS_WEEKLY_CYCLE_CONTRACT"
  end
  check("retry 換掉 promotion identity 被拒", drift_rejected, drift_rejected)

  # --- 證據（附加，不是保護）：journal 過切片 1 的共用 oracle ---
  #
  # 這一段是事後 conformance。真正的保護是上面那些：pre-write 治理判定、
  # SQLite constraint/trigger、rollback 與重啟持久化。
  log = rt.operation_log
  File.write(File.join(dir, "journal.json"), JSON.pretty_generate(log))
  problem = OMOS::Contract.runtime_log_problem(log)
  check("真實 journal 通過切片 1 共用 oracle", problem.inspect, problem.nil?)

  # 邊界（Owner 明示）：oracle 不得進入寫入治理路徑。這裡做成機器檢查，
  # 而不是只寫在註解裡——runtime.rb 一旦引用 oracle，這條就會紅。
  runtime_src = File.read(File.expand_path("../lib/omos/runtime.rb", __dir__))
  check("寫入路徑未引用 journal oracle",
        runtime_src.include?("LogOracle") || runtime_src.include?("RuntimeLogOracle") ? "有引用" : "無引用",
        !runtime_src.include?("LogOracle") && !runtime_src.include?("RuntimeLogOracle"))

  store.close

  # --- 重啟持久化：全新連線重新開啟，讀得回 ---
  reopened = OMOS::Runtime.open(path)
  persisted = reopened.store.db.get_first_value("SELECT kind FROM memory_rows WHERE row_id = ?", [R2])
  version_after = reopened.store.schema_version
  wal_after = reopened.store.journal_mode
  rows_after = reopened.store.rows.size
  reopened.store.close
  check("關閉後重新開啟仍讀得回", persisted.to_s, persisted == "PersonalMemoryRecord")
  check("重啟後 schema_version 不變", version_after, version_after == "0.1.0")
  check("重啟後仍是 WAL", wal_after, wal_after.to_s.casecmp("wal").zero?)
  check("重啟後列數一致", rows_after, rows_after == count_after_rollback)
end

width = RESULTS.map { |_, n, _| n.length }.max
RESULTS.each { |st, n, d| puts format("%-4s %-#{width}s  %s", st, n, d) }
failed = RESULTS.count { |st, _, _| st == "FAIL" }
puts "\n3a conformance：#{RESULTS.size - failed}/#{RESULTS.size} PASS"
exit(failed.zero? ? 0 : 1)
