#!/usr/bin/env ruby
# frozen_string_literal: true
#
# EMEM-11 切片 1｜Local Personal Store Runtime
#
# 驗證單位是一段「對同一個本機 personal store 的 runtime 操作序列」：
# store 表頭（engine／journal_mode／schema_version）＋依序發生的 operations。
# 序列而非單筆，是因為這片真正要守的東西全都是跨操作才成立的：
# schema version 必須是 migration 鏈的尾巴、idempotent replay 必須落回同一
# 列、revision 必須指向這個 store 裡真的存在的前身、同一個 review_period_id
# 只能有一次 terminal closeout。單看一筆操作，以上沒有一條驗得出來。
#
# Design Freeze 的落地位置：
#   A／invariant 3 → access_surfaces 是封閉列舉，forbidden 的四種遠端面
#                    各自以明確錯誤碼失敗（有負例實際打過）。
#   B            → supported_hosts_v1 ⊂ runtime_policy.optional_executors，
#                  在契約層斷言，不在 evaluator 裡重述一份 host 名單。
#   C            → HostSessionBinding 的身分欄位讀
#                  runtime_policy.portable_record_contract.
#                  executor_provenance_fields，而且外殼封閉——host／
#                  host_session_id 這類第二套身分以自己的錯誤碼被擋。
#   D            → closeout 唯一性的三套詞彙全部讀 weekly_review_cycle，
#                  SQLite constraint 是 enforcement 不是權威。
#   F／invariant 2 → 兩個合法 surface 走同一條 write_path；CLI 不因為沒有
#                  Host 就能跳過 policy／transaction 層。
#
# 累積下來的紀律在這裡先套用，不等 review 抓：
#   1. 封閉 allowlist，不是禁用清單。
#   2. 欄位名合法不等於資料形狀合法——每個讀到的值都做形狀鎖。
#   3. 每個檢查都要能回答：權威對照物是誰、它長什麼樣、我讀的是不是
#      同一個東西。本片的對照表寫在 handoff packet 裡。

require "json"
require "set"
require "yaml"
require_relative "lib/omos_contract_helpers"
require_relative "lib/loop_return_contract"
require_relative "lib/minimal_evidence_package_shape"
require_relative "lib/weekly_closeout_history"
require_relative "lib/personal_memory_resource_evaluator"
require_relative "lib/host_session_binding_shape"

ROOT = File.expand_path("..", __dir__)
SPEC_PATH = File.join(ROOT, "規格/v0.1/personal-harness-integration.yaml")
POSITIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-runtime-positive-fixtures.json")
NEGATIVE_FIXTURE_PATH = File.join(ROOT, "規格/v0.1/fixtures/personal-memory-runtime-negative-fixtures.json")

MEPShape = MinimalEvidencePackageShape
# closeout 歷程直接交給切片 4 已在用的同一支 evaluator，不留第二份。
WCH = WeeklyCloseoutHistory
HISTORY_PATH = File.join(__dir__, "lib/weekly_closeout_history.rb")
# row 的本體直接交給既有 Personal Memory resource evaluator，不在本片重寫。
PMRE = PersonalMemoryResourceEvaluator
RESOURCE_PATH = File.join(__dir__, "lib/personal_memory_resource_evaluator.rb")
# HostSessionBinding 的形狀檢查與切片 2 共用同一份實作。
HBShape = HostSessionBindingShape
BINDING_PATH = File.join(__dir__, "lib/host_session_binding_shape.rb")

RUN_ALLOWED_FIELDS = %w[store operations].freeze
STORE_ALLOWED_FIELDS = %w[engine journal_mode schema_version].freeze
OPERATION_ALLOWED_FIELDS = %w[
  op_seq surface kind path host_session_binding transaction
  migration row closeout
].freeze
MIGRATION_ALLOWED_FIELDS = %w[migration_id from_version to_version applied_at].freeze
ROW_ALLOWED_FIELDS = %w[kind row_id idempotency_key supersedes_ref deleted resource].freeze

OPERATION_KINDS = %w[SCHEMA_MIGRATION STORE_READ STORE_WRITE CLOSEOUT_COMMIT].freeze
WRITE_KINDS = %w[SCHEMA_MIGRATION STORE_WRITE CLOSEOUT_COMMIT].freeze
PATH_STEPS = %w[RUNTIME_POLICY_CHECK RUNTIME_TRANSACTION STORE_WRITE STORE_READ].freeze

EXPECTED_NEGATIVE_LABELS = [
  "a CLI operation claiming a host session binding",
  "a closeout attempt kind outside the upstream vocabulary",
  "a closeout history whose scheduled period start drifted between attempts",
  "a closeout payload that is not a map of known fields",
  "a closeout review period id that is not a non-blank string",
  "a closeout status outside the upstream vocabulary",
  "a host session binding additional field that is present but not a non-blank string",
  "a host session binding carrying a field outside the closed shape",
  "a host session binding carrying a shadow identity field",
  "a host session binding missing an upstream executor identity field",
  "a host session binding naming an executor that is not a supported host",
  "a host session binding whose effective_scope is an ownership mode, not a visibility scope",
  "a host session binding that is not a map",
  "a migration id re-emitted with different content",
  "a migration payload that is not a map of known fields",
  "a migration receipt missing a required field",
  "a migration whose from_version does not continue the chain",
  "a promotion_ref carried without a promotion idempotency key",
  "a retry whose promotion identity drifted for the same item",
  "a revision superseding a row of a different kind",
  "a revision superseding a row that was already superseded",
  "a revision superseding a row this store never wrote",
  "a row carrying no Personal Memory resource body",
  "a row deletion erasing history",
  "a row id that does not match its resource body identity",
  "a row id that does not match its upstream id template",
  "a row kind outside the upstream id templates",
  "a row payload that is not a map of known fields",
  "a row resource missing a required field its kind declares upstream",
  "a row resource that was never personally accepted",
  "a row resource that was never verified",
  "a row resource whose candidate snapshot never reached ACCEPTED_FOR_RECORD",
  "a row resource whose memory kind is not long-lived by default",
  "a row resource with no support link at all",
  "a row whose support_link_ref does not resolve inside this store",
  "a run carrying a field outside the allowlist",
  "a run that is not a map",
  "a same-id same-key write that alters supersedes_ref",
  "a second terminal closeout for the same review period",
  "a store engine that is not SQLite",
  "a store header that is not a map",
  "a store journal mode that is not WAL",
  "a store schema version that is not a non-blank string",
  "a store schema version that no migration in the chain produced",
  "a store write outside a runtime transaction",
  "a support link row whose anchor resolution is not usable as support",
  "a support link that does not point back at the row it supports",
  "a write to an existing row id that is not an idempotent replay",
  "an MCP operation with no host session binding",
  "an idempotency key that is not a non-blank string",
  "an idempotent replay that produced a second row id",
  "an operation carrying a field outside the allowlist",
  "an operation kind outside the closed enumeration",
  "an operation on a forbidden remote surface",
  "an operation on a surface outside the closed enumeration",
  "an operation path that does not match the declared path for its kind",
  "an operation path that is not an array of known steps",
  "an operation path whose store access precedes its permission check",
  "an operation sequence with a gap or reordering",
  "an operation that is not a map",
  "an operation whose payload does not match its kind",
  "an operations list that is not a non-empty array",
  "an uncommitted transaction that still produced a durable row"
].freeze

# --- 結構驗證（fail-closed）------------------------------------------------

def runtime_log_failure(run, b)
  return "PMR_RUN_NOT_MAP" unless run.is_a?(Hash)
  return "PMR_RUN_UNKNOWN_FIELD" unless (run.keys - RUN_ALLOWED_FIELDS).empty?

  store = run["store"]
  return "PMR_STORE_NOT_MAP" unless store.is_a?(Hash) && (store.keys - STORE_ALLOWED_FIELDS).empty?
  return "PMR_STORE_ENGINE_NOT_SQLITE" unless store["engine"] == b[:engine]
  return "PMR_STORE_JOURNAL_MODE_NOT_WAL" unless store["journal_mode"] == b[:journal_mode]
  return "PMR_STORE_SCHEMA_VERSION_MISSING" if MEPShape.blank?(store["schema_version"])

  operations = run["operations"]
  return "PMR_OPERATIONS_NOT_ARRAY" unless operations.is_a?(Array) && operations.any?

  # 跨操作狀態：這片的保證幾乎全都住在這裡。
  schema_version = nil                  # migration 鏈目前的尾巴
  migration_receipts = {}               # migration_id => 受凍結的 receipt 內容
  rows = {}                             # row_id => { kind, idempotency_key }
  key_to_row = {}                       # idempotency_key => row_id
  superseded = Set.new                  # 已被取代的 row_id
  closeout_history = {}                 # review_period_id => 依序的 closeout entries

  operations.each_with_index do |op, index|
    return "PMR_OPERATION_NOT_MAP" unless op.is_a?(Hash)
    return "PMR_OPERATION_UNKNOWN_FIELD" unless (op.keys - OPERATION_ALLOWED_FIELDS).empty?
    return "PMR_OPERATION_SEQUENCE_BROKEN" unless op["op_seq"] == index + 1

    kind = op["kind"]
    return "PMR_OPERATION_KIND_UNKNOWN" unless OPERATION_KINDS.include?(kind)

    # 禁列先於封閉列舉：那四種遠端面要以自己的錯誤碼失敗，而不是被歸進
    # 泛用的 unknown surface。
    surface = op["surface"]
    return "PMR_SURFACE_FORBIDDEN" if b[:forbidden_surfaces].include?(surface)
    return "PMR_SURFACE_NOT_IN_CLOSED_ENUM" unless b[:surfaces].include?(surface)

    binding = op["host_session_binding"]
    if surface == "LOCAL_STDIO_MCP"
      return "PMR_MCP_OPERATION_MISSING_HOST_BINDING" if binding.nil?
    elsif !binding.nil?
      # CLI 沒有 Host session 可綁；宣稱有就是偽造 provenance。
      return "PMR_CLI_OPERATION_CLAIMS_HOST_BINDING"
    end

    unless binding.nil?
      # repair-01（切片 2 P1-1／P1-2）：形狀判定搬到共用 evaluator，切片 2 的
      # Host 適配器與本片 runtime 因此不可能對同一個 binding 有不同結論。
      # 這裡逐碼轉發而不是 `return problem`，是因為 LoopReturnContract 要求
      # 出口只能是字面碼；六個碼的診斷粒度依 Owner §1.5 裁決保留。
      problem = HBShape.binding_problem(binding, b[:binding_shape])
      return "PMR_HOST_BINDING_NOT_MAP" if problem == "PMR_HOST_BINDING_NOT_MAP"
      return "PMR_HOST_BINDING_SHADOW_IDENTITY_FIELD" if problem == "PMR_HOST_BINDING_SHADOW_IDENTITY_FIELD"
      return "PMR_HOST_BINDING_UNKNOWN_FIELD" if problem == "PMR_HOST_BINDING_UNKNOWN_FIELD"
      return "PMR_HOST_BINDING_IDENTITY_FIELD_MISSING" if problem == "PMR_HOST_BINDING_IDENTITY_FIELD_MISSING"
      return "PMR_HOST_BINDING_ADDITIONAL_FIELD_NOT_STRING" if problem == "PMR_HOST_BINDING_ADDITIONAL_FIELD_NOT_STRING"
      return "PMR_HOST_BINDING_EFFECTIVE_SCOPE_NOT_VISIBILITY_SCOPE" if problem == "PMR_HOST_BINDING_EFFECTIVE_SCOPE_NOT_VISIBILITY_SCOPE"
      return "PMR_HOST_BINDING_EXECUTOR_NOT_SUPPORTED_HOST" if problem == "PMR_HOST_BINDING_EXECUTOR_NOT_SUPPORTED_HOST"
    end

    path = op["path"]
    return "PMR_PATH_NOT_ARRAY" unless path.is_a?(Array) && path.any? && path.all? { |s| PATH_STEPS.include?(s) }
    # permission-before-retrieval 的確定性 seam：store 存取之前必須先有
    # policy check，而且是第一步。check 之後才回 allow 不算數。
    return "PMR_PERMISSION_CHECK_NOT_FIRST" unless path.first == "RUNTIME_POLICY_CHECK"
    expected_path = kind == "STORE_READ" ? b[:read_path] : b[:write_path]
    return "PMR_PATH_NOT_DECLARED_PATH" unless path == expected_path

    # kind 與 payload 必須互相說得通；讀取操作不得夾帶落地列。
    expected_payload = { "SCHEMA_MIGRATION" => "migration", "STORE_WRITE" => "row",
                         "CLOSEOUT_COMMIT" => "closeout", "STORE_READ" => nil }[kind]
    payload_keys = %w[migration row closeout].select { |f| !op[f].nil? }
    return "PMR_OPERATION_PAYLOAD_MISMATCH" unless payload_keys == [expected_payload].compact

    if WRITE_KINDS.include?(kind)
      transaction = op["transaction"]
      return "PMR_WRITE_OUTSIDE_TRANSACTION" unless transaction.is_a?(Hash)
      return "PMR_UNCOMMITTED_WRITE_DURABLE" unless transaction["committed"] == true
    end

    if kind == "SCHEMA_MIGRATION"
      migration = op["migration"]
      return "PMR_MIGRATION_NOT_MAP" unless migration.is_a?(Hash) &&
                                           (migration.keys - MIGRATION_ALLOWED_FIELDS).empty?
      return "PMR_MIGRATION_RECEIPT_INCOMPLETE" unless MIGRATION_ALLOWED_FIELDS.all? { |f| !MEPShape.blank?(migration[f]) }
      # 鏈必須接得上：第一筆從 nil 起算，之後每筆的 from_version 就是目前尾巴。
      return "PMR_MIGRATION_CHAIN_BROKEN" unless migration["from_version"] == (schema_version || b[:genesis_version])

      migration_id = migration["migration_id"]
      prior = migration_receipts[migration_id]
      # receipt 不可變（correction_flow 的 receipt_mutation）：同一個
      # migration_id 用不同內容再發一次就是竄改。
      return "PMR_MIGRATION_RECEIPT_MUTATED" if !prior.nil? && prior != migration
      migration_receipts[migration_id] = migration
      schema_version = migration["to_version"]
    end

    if kind == "STORE_WRITE"
      row = op["row"]
      return "PMR_ROW_NOT_MAP" unless row.is_a?(Hash) && (row.keys - ROW_ALLOWED_FIELDS).empty?
      # 刪除在這個 store 裡不存在：history_erasure 是 correction_flow 明文禁項。
      return "PMR_HISTORY_ERASURE" if row["deleted"] == true

      row_kind = row["kind"]
      return "PMR_ROW_KIND_UNKNOWN" unless b[:id_patterns].key?(row_kind)
      row_id = row["row_id"]
      # id 形狀鎖到上游 id_template，含 UUIDv7 的 version／variant nibble。
      return "PMR_ROW_ID_NOT_MATCHING_ID_TEMPLATE" unless row_id.is_a?(String) &&
                                                          b[:id_patterns][row_kind].match?(row_id)
      return "PMR_IDEMPOTENCY_KEY_INVALID" if MEPShape.blank?(row["idempotency_key"])

      # repair-01 P1-3：落地的是一筆 Personal Memory 資源，不是一個空殼 id。
      # required_fields／forbidden 在評估當下讀 personal_memory_resource_
      # contracts.resources.<kind>，本片不維護第二份欄位清單。
      resource = row["resource"]
      return "PMR_ROW_RESOURCE_NOT_MAP" unless resource.is_a?(Hash)
      # 合法 id 配上別人的本體，等於 id 沒有真的指向任何東西。
      return "PMR_ROW_ID_NOT_BOUND_TO_RESOURCE_IDENTITY" unless resource[b[:row_identity_fields][row_kind]] == row_id

      # repair-02 P1-3：不是「required_fields 路徑存在」而已——整份本體交給
      # 既有 Personal Memory resource evaluator：support、memory kind、
      # verification／acceptance、lifecycle、Record creation gate 全部由那一份
      # 實作判定。indexes 用的是**這個 store 目前已寫入的列**，所以
      # support_link_refs 必須解析到同一個 store 裡真的存在、且 target_ref
      # 指回本列的 MemorySupportLink——這是組合，不是形式呼叫。
      store_cases = rows.map { |rid, rec| { "resource_type" => rec[:kind], "resource" => rec[:resource], "case_id" => rid } }
      store_cases << { "resource_type" => row_kind, "resource" => resource, "case_id" => row_id }
      resource_problems = PMRE.resource_failures(
        b[:spec], b[:common_vocab], PMRE.build_indexes(store_cases),
        { "resource_type" => row_kind, "resource" => resource }
      )
      return "PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT" unless resource_problems.empty?

      key = row["idempotency_key"]
      seen_row_for_key = key_to_row[key]
      # 重放必須落回同一列；換一個 row_id 就不是 retry，是第二筆。
      return "PMR_IDEMPOTENT_REPLAY_CREATED_SECOND_ROW" if !seen_row_for_key.nil? && seen_row_for_key != row_id

      # repair-01 P1-1：凍結的是「整筆 row」，不是 row_id + key。先前只記
      # {kind, key}，於是同一個 row_id + 同一把 key 只要把 supersedes_ref
      # 改掉就能就地改寫；而原封不動重放一筆 revision 反而會被誤判成第二次
      # supersession。兩者同一個根因：部分凍結。
      canonical_row = canonical_json(row)
      existing = rows[row_id]
      unless existing.nil?
        return "PMR_IN_PLACE_ROW_OVERWRITE" unless existing[:canonical] == canonical_row

        # 逐欄相同的重放是 no-op：不得再動 supersession 帳。
        next
      end

      supersedes_ref = row["supersedes_ref"]
      unless supersedes_ref.nil?
        target = rows[supersedes_ref]
        return "PMR_SUPERSEDES_TARGET_UNKNOWN" if target.nil?
        return "PMR_SUPERSEDES_TARGET_KIND_MISMATCH" unless target[:kind] == row_kind
        return "PMR_SUPERSEDES_TARGET_ALREADY_SUPERSEDED" if superseded.include?(supersedes_ref)
        superseded << supersedes_ref
      end

      rows[row_id] = { kind: row_kind, canonical: canonical_row, resource: resource }
      key_to_row[key] = row_id
    end

    if kind == "CLOSEOUT_COMMIT"
      closeout = op["closeout"]
      # 只做「能安全分組」所需的最低檢查，其餘全部交給共用 evaluator。
      return "PMR_CLOSEOUT_NOT_MAP" unless closeout.is_a?(Hash)
      period_id = closeout["review_period_id"]
      return "PMR_CLOSEOUT_REVIEW_PERIOD_ID_INVALID" if MEPShape.blank?(period_id)

      (closeout_history[period_id] ||= []) << closeout
    end
  end

  # repair-01 P1-2：同一個 review_period_id 的 CLOSEOUT_COMMIT 依發生順序
  # 排起來，就是 weekly_review_cycle 眼中的一段 closeout 歷程——直接丟給
  # 切片 4 已在用的同一支 evaluator。terminal 唯一性、status／attempt 詞彙、
  # SKIPPED 的 catch-up 規則、disposition 分類，以及本片原本完全沒有落地的
  # promotion idempotency（retry 不得換掉同一 item 的 promotion 身分），
  # 全部來自那一份實作，本片不再自己列任何一份詞彙。
  closeout_history.each_value do |entries|
    problem = WCH.weekly_review_cycle_failure(
      { "review_period_id" => entries.first["review_period_id"], "closeouts" => entries },
      b[:disposition_categories], b[:candidate_ref_prefix], b[:record_ref_prefix]
    )
    return "PMR_CLOSEOUT_FAILS_WEEKLY_CYCLE_CONTRACT" unless problem.nil?
  end

  # schema_version 不是獨立主張，是 migration 鏈的尾巴。
  return "PMR_STORE_SCHEMA_VERSION_NOT_MIGRATION_CHAIN_TAIL" unless store["schema_version"] == schema_version

  nil
end

# --- 契約層斷言 -----------------------------------------------------------

failures = []

spec = read_yaml(SPEC_PATH)
pmr = spec.fetch("personal_memory_runtime")

assert(pmr["slice_of"].to_s.include?("EMEM-11"), "personal_memory_runtime 必須標明 slice_of EMEM-11", failures)

invariants = pmr.fetch("invariants", [])
%w[
  HOST_BINDING_IS_AN_ADAPTER_NOT_THE_RUNTIME
  LOCAL_CLI_AND_HOST_MCP_SHARE_THE_SAME_RUNTIME_AUTHORITY
  NO_REMOTE_PERSONAL_STORE_ACCESS_SURFACE
].each do |invariant|
  assert(invariants.include?(invariant), "invariants 必須含 Design Freeze 的 #{invariant}", failures)
end
assert(pmr["owner_authorization"].to_s.include?("Personal scope only"),
       "owner_authorization 必須維持 Owner 裁決 E 的限定範圍文字", failures)

# store 表頭
store_spec = pmr.fetch("store", {})
engine = store_spec["engine"]
journal_mode = store_spec["journal_mode"]
assert(engine == "SQLITE", "store.engine 必須是 SQLITE", failures)
assert(journal_mode == "WAL", "store.journal_mode 必須是 WAL", failures)
assert(store_spec["schema_version_required"] == true, "store.schema_version_required 必須為 true", failures)
assert(store_spec["migration_receipt_required"] == true, "store.migration_receipt_required 必須為 true", failures)
assert(store_spec["schema_version_source"] == "MIGRATION_CHAIN_TAIL",
       "store.schema_version_source 必須宣告 schema_version 來自 migration 鏈尾", failures)

# Design Freeze A／invariant 3：access surface 是封閉列舉，且沒有遠端面。
surfaces = pmr.fetch("access_surfaces", [])
forbidden_surfaces = pmr.fetch("forbidden_access_surfaces", [])
assert(sorted_set(surfaces) == sorted_set(%w[LOCAL_STDIO_MCP LOCAL_CLI]),
       "access_surfaces 必須恰為兩個本機 surface（封閉列舉）", failures)
assert(forbidden_surfaces.any?, "forbidden_access_surfaces 不得為空", failures)
assert((sorted_set(surfaces) & sorted_set(forbidden_surfaces)).empty?,
       "合法與禁止 surface 不得重疊", failures)
assert(surfaces.all? { |s| s.start_with?("LOCAL_") },
       "access_surfaces 不得含非本機 surface（invariant NO_REMOTE_PERSONAL_STORE_ACCESS_SURFACE）", failures)

# Design Freeze B：supported_hosts_v1 ⊂ runtime_policy.optional_executors。
optional_executors = spec.dig("runtime_policy", "optional_executors") || []
supported_hosts = pmr.fetch("supported_hosts_v1", [])
assert(optional_executors.any?, "runtime_policy.optional_executors 必須存在（本片讀它，不重述）", failures)
assert(supported_hosts.any?, "supported_hosts_v1 不得為空", failures)
assert((sorted_set(supported_hosts) - sorted_set(optional_executors)).empty?,
       "supported_hosts_v1 必須是 runtime_policy.optional_executors 的子集：" \
       "#{(sorted_set(supported_hosts) - sorted_set(optional_executors)).to_a.inspect}", failures)

# Design Freeze C：身分欄位是引用上游，不是本片自己列一份。
binding_spec = pmr.fetch("host_session_binding", {})
identity_ref = binding_spec["executor_identity_fields_ref"].to_s
assert(identity_ref == "runtime_policy.portable_record_contract.executor_provenance_fields",
       "host_session_binding 必須以 ref 指向上游 executor_provenance_fields，不得內嵌第二份清單", failures)
identity_fields = spec.dig("runtime_policy", "portable_record_contract", "executor_provenance_fields") || []
assert(identity_fields == %w[executor_ref executor_session_ref],
       "上游 executor_provenance_fields 形狀改變，本片的綁定需重新檢視：#{identity_fields.inspect}", failures)
assert(binding_spec["executor_identity_fields"].nil?,
       "host_session_binding 不得內嵌 executor_identity_fields（那就是第二套身分詞彙）", failures)
binding_additional = binding_spec.fetch("additional_fields", [])
binding_forbidden = binding_spec.fetch("forbidden_fields", [])
assert(binding_forbidden.any?, "host_session_binding.forbidden_fields 不得為空", failures)
assert((sorted_set(binding_forbidden) & sorted_set(identity_fields + binding_additional)).empty?,
       "禁用身分欄位不得同時出現在合法欄位裡", failures)
%w[host host_session_id].each do |field|
  assert(binding_forbidden.include?(field),
         "forbidden_fields 必須含 #{field}（Owner 裁決 C：不得另造第二套 host 身分）", failures)
end

# Design Freeze F／invariant 2：兩個 surface 共用同一條 write path。
write_path = pmr.fetch("write_path", [])
read_path = pmr.fetch("read_path", [])
assert(write_path == %w[RUNTIME_POLICY_CHECK RUNTIME_TRANSACTION STORE_WRITE],
       "write_path 必須是 policy check → transaction → store write", failures)
assert(read_path == %w[RUNTIME_POLICY_CHECK STORE_READ],
       "read_path 必須以 policy check 起頭", failures)
assert((write_path + read_path).all? { |s| PATH_STEPS.include?(s) },
       "宣告的 path step 必須都在 evaluator 認得的步驟詞彙裡", failures)
floor = spec.dig("capability_safety_floor", "invariants") || []
assert(floor.include?("permission_before_retrieval"),
       "capability_safety_floor.invariants 必須含 permission_before_retrieval（本片的讀路徑 seam 依賴它）", failures)

# Design Freeze D：closeout 唯一性的詞彙全部讀 weekly_review_cycle。
uniqueness = pmr.fetch("closeout_uniqueness", {})
assert(uniqueness["derived_from"] == "weekly_review_cycle",
       "closeout_uniqueness 必須宣告 derived_from weekly_review_cycle（SQLite constraint 不是權威）", failures)
assert(uniqueness["identity_field"] == "review_period_id",
       "closeout 唯一性的 identity 必須是 review_period_id", failures)
assert(uniqueness["evaluator_ref"] == "scripts/lib/weekly_closeout_history.rb",
       "closeout_uniqueness 必須宣告它委派給哪一支共用 evaluator", failures)
assert(File.exist?(HISTORY_PATH), "宣告的共用 evaluator 必須存在：#{HISTORY_PATH}", failures)
assert(uniqueness["promotion_idempotency_rule_ref"] == "weekly_review_cycle.promotion_idempotency_rule",
       "closeout_uniqueness 必須指回 weekly cycle 的 promotion idempotency 規則", failures)
assert(!MEPShape.blank?(spec.dig("weekly_review_cycle", "promotion_idempotency_rule")),
       "weekly_review_cycle.promotion_idempotency_rule 必須存在（本片委派它，不重述）", failures)
%w[status_vocabulary_ref terminal_vocabulary_ref attempt_vocabulary_ref].each do |key|
  assert(uniqueness[key].nil?,
         "closeout_uniqueness 不得再自行指派 #{key}——詞彙由共用 evaluator 一併帶入", failures)
end
%w[closeout_statuses terminal_statuses attempt_kinds].each do |key|
  assert(uniqueness[key].nil?,
         "closeout_uniqueness 不得內嵌 #{key} 的副本（那就是取代 cycle 契約而非執行它）", failures)
end
wrc = spec.fetch("weekly_review_cycle")

# 委派之後仍要確認「被委派的那一份」和上游沒有漂移——讀的是共用 evaluator
# 的常數本身，不是在這裡再抄一份詞彙。少了這幾條，上游改詞彙時 runtime
# 會靜靜地繼續用舊的（改版時的漂移探針就是這樣抓到的）。
{
  "closeout_statuses" => WCH::CLOSEOUT_STATUSES,
  "terminal_statuses" => WCH::TERMINAL_STATUSES,
  "attempt_kinds" => WCH::ATTEMPT_KINDS
}.each do |key, shared|
  assert(sorted_set(wrc.fetch(key, [])) == sorted_set(shared),
         "weekly_review_cycle.#{key} 與共用 evaluator 的詞彙不一致：#{wrc[key].inspect} vs #{shared.inspect}", failures)
end
assert(sorted_set(spec.dig("weekly_review_cycle", "closeout_receipt", "required_fields") || []) ==
       sorted_set(WCH::REQUIRED_FIELDS),
       "weekly_review_cycle.closeout_receipt.required_fields 與共用 evaluator 不一致", failures)
closeout_statuses = wrc.fetch("closeout_statuses")
terminal_statuses = wrc.fetch("terminal_statuses")
attempt_kinds = wrc.fetch("attempt_kinds")
assert((sorted_set(terminal_statuses) - sorted_set(closeout_statuses)).empty?,
       "weekly_review_cycle.terminal_statuses 必須是 closeout_statuses 的子集", failures)
assert(closeout_statuses.include?("FAILED") && !terminal_statuses.include?("FAILED"),
       "FAILED 必須是合法但非 terminal 的狀態（retry 才有意義）", failures)

# revision／receipt 的不可變性直接落在 correction_flow 的既有禁項上。
correction_forbidden = spec.dig("correction_flow", "contract", "forbidden") || []
%w[in_place_record_overwrite history_erasure receipt_mutation].each do |item|
  assert(correction_forbidden.include?(item),
         "correction_flow.contract.forbidden 必須含 #{item}（本片是它在 runtime 層的 enforcement）", failures)
end
assert(spec.dig("correction_flow", "contract", "immutable_receipt") == true,
       "correction_flow.contract.immutable_receipt 必須維持 true", failures)

# row id 形狀讀上游 id_templates，UUID 版本位元沿用切片 A 的推導結果。
vocab = read_yaml(File.join(ROOT, "規格/v0.1/common-vocabulary.yaml"))
std01 = read_json(File.join(ROOT, "規格/v0.1/raw-evidence-envelope.schema.json"))
mep_bindings, binding_problems = MEPShape.build_bindings(spec, vocab, std01)
binding_problems.each { |problem| assert(false, problem, failures) }
version_digit = mep_bindings[:uuid_version_digit]
id_templates = spec.dig("personal_memory_resource_contracts", "shared_constraints", "id_templates") || {}
assert(id_templates.any?, "shared_constraints.id_templates 必須存在（本片讀它，不自創 row id 形狀）", failures)
id_patterns = {}
id_templates.each do |kind, template|
  id_patterns[kind] = Regexp.new("\\A#{MEPShape.build_id_template_pattern(template, version_digit)}\\z")
end
assert(id_patterns.key?("PersonalMemoryRecord") && id_patterns.key?("PersonalMemoryCandidate"),
       "id_templates 必須至少涵蓋 Candidate／Record", failures)

# repair-01 P1-3：落地列必須是一筆真的 Personal Memory 資源。
resources = spec.dig("personal_memory_resource_contracts", "resources") || {}
row_contract = pmr.fetch("row_contract", {})
assert(row_contract["resource_contract_ref"] == "personal_memory_resource_contracts.resources",
       "row_contract 必須宣告它綁的是既有 resource 契約", failures)
row_identity_fields = row_contract.fetch("identity_fields", {})
assert(sorted_set(row_identity_fields.keys) == sorted_set(id_templates.keys),
       "row_contract.identity_fields 必須恰好涵蓋 id_templates 的每一個 kind", failures)
row_identity_fields.each do |kind, field|
  kind_def = resources[kind]
  assert(kind_def.is_a?(Hash), "row_contract.identity_fields 指名的 #{kind} 必須有 resource 契約", failures)
  required = kind_def.is_a?(Hash) ? (kind_def["required_fields"] || []) : []
  assert(required.include?(field),
         "#{kind} 的 identity 欄位 #{field} 必須本來就在它的 required_fields 裡（本片不另立欄位）", failures)
  assert(required.size > 1,
         "#{kind} 的 required_fields 必須不只 identity 一欄，否則「有本體」等於沒要求", failures)
end
assert(row_contract["required_fields"].nil? && row_contract["forbidden"].nil?,
       "row_contract 不得內嵌第二份欄位清單（必須在評估當下讀上游）", failures)

# 共用 evaluator 的三個引數取法與切片 4 完全相同——讀同一批上游，
# 不在本片重新定義分類詞彙或 ref 前綴。
hc_categories = spec.dig("historical_comparison", "categories") || []
assert(hc_categories.any?, "historical_comparison.categories 必須存在（共用 evaluator 綁定它）", failures)
disposition_categories = (hc_categories + ["NEEDS_ORG_FOLLOWUP"]).to_set
candidate_ref_prefix = id_templates["PersonalMemoryCandidate"].to_s.split("{").first
record_ref_prefix = id_templates["PersonalMemoryRecord"].to_s.split("{").first

# repair-01 P1-2：effective_scope 的詞彙來源。切片 2 的契約也指向同一處，
# 兩片因此不可能對這個欄位各自解讀。
visibility_scopes = spec.dig("ownership_visibility_contract", "visibility_scopes") || {}
assert(visibility_scopes.any?,
       "ownership_visibility_contract.visibility_scopes 必須存在（effective_scope 綁定它）", failures)
visibility_scope_names = visibility_scopes.keys
mode_names = (spec.dig("ownership_visibility_contract", "mode_definitions") || {}).keys
assert((visibility_scope_names & mode_names).empty?,
       "visibility scope 與 ownership mode 的詞彙不得相交，否則 effective_scope 又會兩義", failures)

genesis_version = store_spec["genesis_version"]
assert(!MEPShape.blank?(genesis_version),
       "store.genesis_version 必須宣告（migration 鏈的起點，第一筆 from_version 比對它）", failures)

BINDINGS = {
  engine: engine,
  journal_mode: journal_mode,
  surfaces: surfaces,
  forbidden_surfaces: forbidden_surfaces,
  supported_hosts: supported_hosts,
  identity_fields: identity_fields,
  binding_shape: {
    identity_fields: identity_fields,
    additional_fields: binding_additional,
    allowed_fields: identity_fields + binding_additional,
    forbidden_fields: binding_forbidden,
    supported_hosts: supported_hosts,
    visibility_scopes: visibility_scope_names
  },
  write_path: write_path,
  read_path: read_path,
  id_patterns: id_patterns,
  spec: spec,
  common_vocab: vocab,
  row_identity_fields: row_identity_fields,
  disposition_categories: disposition_categories,
  candidate_ref_prefix: candidate_ref_prefix,
  record_ref_prefix: record_ref_prefix,
  genesis_version: genesis_version
}.freeze

# --- fixtures -------------------------------------------------------------

positive_fixtures = read_json(POSITIVE_FIXTURE_PATH)
negative_fixtures = read_json(NEGATIVE_FIXTURE_PATH)

positive_fixtures.fetch("cases").each do |test_case|
  case_id = test_case.fetch("case_id")
  run = test_case.fetch("run")
  assert(test_case.fetch("expected") == "allow", "#{case_id} 正例必須預期 allow", failures)

  actual = runtime_log_failure(run, BINDINGS)
  assert(actual.nil?, "#{case_id} 預期 allow，實際被拒：#{actual}", failures)
end

# 負例採 base + 明寫 mutation：每一筆只宣告它對那段合法序列動了什麼，
# reviewer 不必 diff 兩份兩百行的 JSON 才看得出攻擊點。路徑機制直接沿用
# omos_contract_helpers 既有的 set_path／delete_path／read_path，不另造一套。
negative_base = negative_fixtures.fetch("base")
# 這條斷言是整個表示法的支點：base 自己必須是合法序列，因此每個負例都
# 精確地等於「一段會通過的序列，再加上下面這一個 mutation」。
assert(runtime_log_failure(negative_base, BINDINGS).nil?,
       "負例 base 必須本身通過，否則每個負例都可能是因為別的原因被拒", failures)

def apply_fixture_mutation(base, mutation)
  return mutation["replace_run"] if mutation.key?("replace_run")

  run = deep_dup(base)
  (mutation["set"] || {}).each { |path, value| set_path(run, path, value) }
  (mutation["delete"] || []).each { |path| delete_path(run, path) }
  (mutation["append"] || {}).each { |path, value| read_path(run, path) << value }
  run
end

negative_cases = negative_fixtures.fetch("cases")
negative_runs = []
negative_cases.each do |test_case|
  case_id = test_case.fetch("case_id")
  mutation = test_case.fetch("mutate")
  assert(mutation.is_a?(Hash) && mutation.any?,
         "#{case_id} 必須宣告至少一個 mutation（空 mutation 等於重貼 base）", failures)
  run = apply_fixture_mutation(negative_base, mutation)
  negative_runs << run
  assert(canonical_json(run) != canonical_json(negative_base),
         "#{case_id} 的 mutation 沒有真的改變 base", failures)
  assert(test_case.fetch("expected") == "deny", "#{case_id} 負例必須預期 deny", failures)
  expected_code = test_case.fetch("expected_failure_code")

  actual = runtime_log_failure(run, BINDINGS)
  assert(!actual.nil?, "#{case_id} 預期 deny，實際通過", failures)
  assert(actual == expected_code, "#{case_id} 預期 #{expected_code}，實際 #{actual.inspect}", failures)
end

covered = sorted_set(negative_cases.map { |c| c.fetch("covers_negative_fixture") })
missing_labels = sorted_set(EXPECTED_NEGATIVE_LABELS) - covered
assert(missing_labels.empty?, "negative fixtures 未覆蓋：#{missing_labels.to_a.join(', ')}", failures)

# 每一個宣告為禁止的遠端 surface 都必須有負例實際打過，不能只宣告在 YAML 裡。
covered_forbidden = sorted_set(
  negative_runs.map do |r|
    ops = r.is_a?(Hash) ? r["operations"] : nil
    ops.is_a?(Array) ? ops.map { |o| o.is_a?(Hash) ? o["surface"] : nil } : nil
  end.compact.flatten.compact & forbidden_surfaces
)
missing_surfaces = sorted_set(forbidden_surfaces) - covered_forbidden
assert(missing_surfaces.empty?,
       "以下禁止 surface 沒有負例實際打過：#{missing_surfaces.to_a.join(', ')}", failures)

# --- error contract -------------------------------------------------------

ERROR_CONTRACT = {
  "PMR_RUN_NOT_MAP" => "personal_memory_runtime.error.run_not_map",
  "PMR_RUN_UNKNOWN_FIELD" => "personal_memory_runtime.error.run_unknown_field",
  "PMR_STORE_NOT_MAP" => "personal_memory_runtime.error.store_not_map",
  "PMR_STORE_ENGINE_NOT_SQLITE" => "personal_memory_runtime.error.store_engine_not_sqlite",
  "PMR_STORE_JOURNAL_MODE_NOT_WAL" => "personal_memory_runtime.error.store_journal_mode_not_wal",
  "PMR_STORE_SCHEMA_VERSION_MISSING" => "personal_memory_runtime.error.store_schema_version_missing",
  "PMR_OPERATIONS_NOT_ARRAY" => "personal_memory_runtime.error.operations_not_array",
  "PMR_OPERATION_NOT_MAP" => "personal_memory_runtime.error.operation_not_map",
  "PMR_OPERATION_UNKNOWN_FIELD" => "personal_memory_runtime.error.operation_unknown_field",
  "PMR_OPERATION_SEQUENCE_BROKEN" => "personal_memory_runtime.error.operation_sequence_broken",
  "PMR_OPERATION_KIND_UNKNOWN" => "personal_memory_runtime.error.operation_kind_unknown",
  "PMR_SURFACE_FORBIDDEN" => "personal_memory_runtime.error.surface_forbidden",
  "PMR_SURFACE_NOT_IN_CLOSED_ENUM" => "personal_memory_runtime.error.surface_not_in_closed_enum",
  "PMR_MCP_OPERATION_MISSING_HOST_BINDING" => "personal_memory_runtime.error.mcp_operation_missing_host_binding",
  "PMR_CLI_OPERATION_CLAIMS_HOST_BINDING" => "personal_memory_runtime.error.cli_operation_claims_host_binding",
  "PMR_HOST_BINDING_NOT_MAP" => "personal_memory_runtime.error.host_binding_not_map",
  "PMR_HOST_BINDING_SHADOW_IDENTITY_FIELD" => "personal_memory_runtime.error.host_binding_shadow_identity_field",
  "PMR_HOST_BINDING_UNKNOWN_FIELD" => "personal_memory_runtime.error.host_binding_unknown_field",
  "PMR_HOST_BINDING_IDENTITY_FIELD_MISSING" => "personal_memory_runtime.error.host_binding_identity_field_missing",
  "PMR_HOST_BINDING_ADDITIONAL_FIELD_NOT_STRING" => "personal_memory_runtime.error.host_binding_additional_field_not_string",
  "PMR_HOST_BINDING_EFFECTIVE_SCOPE_NOT_VISIBILITY_SCOPE" => "personal_memory_runtime.error.host_binding_effective_scope_not_visibility_scope",
  "PMR_HOST_BINDING_EXECUTOR_NOT_SUPPORTED_HOST" => "personal_memory_runtime.error.host_binding_executor_not_supported_host",
  "PMR_PATH_NOT_ARRAY" => "personal_memory_runtime.error.path_not_array",
  "PMR_PERMISSION_CHECK_NOT_FIRST" => "personal_memory_runtime.error.permission_check_not_first",
  "PMR_PATH_NOT_DECLARED_PATH" => "personal_memory_runtime.error.path_not_declared_path",
  "PMR_OPERATION_PAYLOAD_MISMATCH" => "personal_memory_runtime.error.operation_payload_mismatch",
  "PMR_WRITE_OUTSIDE_TRANSACTION" => "personal_memory_runtime.error.write_outside_transaction",
  "PMR_UNCOMMITTED_WRITE_DURABLE" => "personal_memory_runtime.error.uncommitted_write_durable",
  "PMR_MIGRATION_NOT_MAP" => "personal_memory_runtime.error.migration_not_map",
  "PMR_MIGRATION_RECEIPT_INCOMPLETE" => "personal_memory_runtime.error.migration_receipt_incomplete",
  "PMR_MIGRATION_CHAIN_BROKEN" => "personal_memory_runtime.error.migration_chain_broken",
  "PMR_MIGRATION_RECEIPT_MUTATED" => "personal_memory_runtime.error.migration_receipt_mutated",
  "PMR_ROW_NOT_MAP" => "personal_memory_runtime.error.row_not_map",
  "PMR_ROW_RESOURCE_NOT_MAP" => "personal_memory_runtime.error.row_resource_not_map",
  "PMR_ROW_RESOURCE_FAILS_RESOURCE_CONTRACT" => "personal_memory_runtime.error.row_resource_fails_resource_contract",
  "PMR_ROW_ID_NOT_BOUND_TO_RESOURCE_IDENTITY" => "personal_memory_runtime.error.row_id_not_bound_to_resource_identity",
  "PMR_HISTORY_ERASURE" => "personal_memory_runtime.error.history_erasure",
  "PMR_ROW_KIND_UNKNOWN" => "personal_memory_runtime.error.row_kind_unknown",
  "PMR_ROW_ID_NOT_MATCHING_ID_TEMPLATE" => "personal_memory_runtime.error.row_id_not_matching_id_template",
  "PMR_IDEMPOTENCY_KEY_INVALID" => "personal_memory_runtime.error.idempotency_key_invalid",
  "PMR_IDEMPOTENT_REPLAY_CREATED_SECOND_ROW" => "personal_memory_runtime.error.idempotent_replay_created_second_row",
  "PMR_IN_PLACE_ROW_OVERWRITE" => "personal_memory_runtime.error.in_place_row_overwrite",
  "PMR_SUPERSEDES_TARGET_UNKNOWN" => "personal_memory_runtime.error.supersedes_target_unknown",
  "PMR_SUPERSEDES_TARGET_KIND_MISMATCH" => "personal_memory_runtime.error.supersedes_target_kind_mismatch",
  "PMR_SUPERSEDES_TARGET_ALREADY_SUPERSEDED" => "personal_memory_runtime.error.supersedes_target_already_superseded",
  "PMR_CLOSEOUT_NOT_MAP" => "personal_memory_runtime.error.closeout_not_map",
  "PMR_CLOSEOUT_REVIEW_PERIOD_ID_INVALID" => "personal_memory_runtime.error.closeout_review_period_id_invalid",
  "PMR_CLOSEOUT_FAILS_WEEKLY_CYCLE_CONTRACT" => "personal_memory_runtime.error.closeout_fails_weekly_cycle_contract",
  "PMR_STORE_SCHEMA_VERSION_NOT_MIGRATION_CHAIN_TAIL" => "personal_memory_runtime.error.store_schema_version_not_migration_chain_tail"
}.freeze

declared_codes = ERROR_CONTRACT.keys
history_violations = LoopReturnContract.exit_shape_violations(HISTORY_PATH, "weekly_review_cycle_failure")
assert(history_violations.empty?,
       "共用的 weekly closeout evaluator 有不合契約的 return 形式：#{history_violations.inspect}", failures)
binding_violations = LoopReturnContract.exit_shape_violations(BINDING_PATH, "binding_problem")
assert(binding_violations.empty?,
       "共用的 HostSessionBinding evaluator 有不合契約的 return 形式：#{binding_violations.inspect}", failures)
binding_codes = LoopReturnContract.reachable_codes(BINDING_PATH, "binding_problem")
assert((binding_codes - ERROR_CONTRACT.keys).empty?,
       "共用 binding evaluator 會回傳但本片 error_contract 未宣告：#{(binding_codes - ERROR_CONTRACT.keys).sort.inspect}", failures)
violations = LoopReturnContract.exit_shape_violations(__FILE__, "runtime_log_failure")
assert(violations.empty?, "runtime_log_failure 有不合契約的 return 形式：#{violations.inspect}", failures)
reachable = LoopReturnContract.reachable_codes(__FILE__, "runtime_log_failure")
assert((reachable - declared_codes).empty?,
       "evaluator 會回傳但 error_contract 未宣告：#{(reachable - declared_codes).sort.inspect}", failures)
assert((declared_codes - reachable).empty?,
       "error_contract 宣告但 evaluator 不可能回傳：#{(declared_codes - reachable).sort.inspect}", failures)

if failures.empty?
  puts "PASS personal memory runtime contract validation " \
       "(surfaces=#{surfaces.size} hosts=#{supported_hosts.size} codes=#{declared_codes.size})"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
