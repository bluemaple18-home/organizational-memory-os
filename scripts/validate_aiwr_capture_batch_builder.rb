#!/usr/bin/env ruby
# frozen_string_literal: true
#
# AIWR 最後一哩 builder 的常設 regression gate。
#
# 存在理由（big review repair-01 的 F-03／P2）：`build_aiwr_capture_batch.rb`
# 的兩個 identity／idempotency 缺口（task_ref 只驗泛型 OMOS URN、event_key
# 字串串接會碰撞）被 24 支既有 validator 全數放行——既有 gate 驗的是契約與
# fixture，沒有人驗這個 builder。本檔補上，並把上面兩個真實缺口固定成負例。
#
# 設計原則：**不重寫一份 capture 規則**。驗證用的
# `hook_capture_failure` 直接綁定 validate_ai_work_record_hook_contract.rb
# 的原始碼（機械抽取函式本體後 eval，非手抄），所以上游改了行為而這裡沒跟上
# 時，抽取會失敗、gate 會紅，而不是兩份實作各說各話。

require "json"
require "yaml"
require "fileutils"
require "tmpdir"
require_relative "build_aiwr_capture_batch"

# ROOT 由 build_aiwr_capture_batch.rb 定義（上面已 require_relative）。
HOOK_VALIDATOR_PATH = File.join(ROOT, "scripts/validate_ai_work_record_hook_contract.rb")
CARD_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-task-card-record.yaml")
HOOK_SPEC_PATH = File.join(ROOT, "規格/v0.1/ai-work-record-hook.yaml")

REQUIRED_CONSTANTS = %w[
  EXPECTED_ENVELOPE_FIELDS EXPECTED_FORBIDDEN_BATCH_FIELDS
  OMOS_URN EXPECTED_HOST_TASK_IMPACT_ALLOWED
].freeze
REQUIRED_FUNCTIONS = ["hook_capture_failure", "replay_transition_failure", "urn\\?"].freeze

# 從既有 validator 的原始碼抽出需要的常數與函式本體。抽不到就 fail loud
# ——代表上游結構變了，這個 gate 必須被重新對齊，不能默默失效。
def load_hook_evaluator!
  source = File.read(HOOK_VALIDATOR_PATH)
  pieces = []

  REQUIRED_CONSTANTS.each do |name|
    match = source[/\n#{name} = .*?\.freeze\n/m]
    raise "抽不到常數 #{name}（#{HOOK_VALIDATOR_PATH} 結構已改變？）" unless match

    pieces << match
  end

  REQUIRED_FUNCTIONS.each do |name|
    match = source[/\ndef #{name}\(.*?\n^end\n/m]
    raise "抽不到函式 #{name}（#{HOOK_VALIDATOR_PATH} 結構已改變？）" unless match

    pieces << match
  end

  # present? 在 lib/omos_contract_helpers.rb，直接 require 沒有副作用。
  require_relative "lib/omos_contract_helpers"
  Object.class_eval(pieces.join("\n"))
end

def mapping_record(session_id:, correlation_ref:, event:, task_ref:, at:)
  record = {
    "native_event_type" => event == "start" ? "UserPromptSubmit" : "Stop",
    "mapped_to" => event,
    "outcome" => "MAPPED",
    "native_correlation_ref" => correlation_ref,
    "adapter_output_ref" => "urn:omos:ssp310-pilot-evidence:#{session_id}:#{at}",
    "occurred_at" => at,
    "session_id" => session_id
  }
  record["declared_task_ref"] = task_ref if task_ref
  record
end

def build_batches(records)
  Dir.mktmpdir do |dir|
    log = File.join(dir, "log.jsonl")
    File.write(log, records.map(&:to_json).join("\n") + "\n")
    out = File.join(dir, "out")
    main(log, out)
    Dir[File.join(out, "*.json")].sort.map { |f| JSON.parse(File.read(f)) }
  end
end

# builder 以非 0 結束碼拒絕時，main 會呼叫 exit —— 用 SystemExit 攔下來。
def build_batches_expecting_refusal(records)
  build_batches(records)
  nil
rescue SystemExit => e
  e.status
end

TASK_A = "urn:omos:task-card:aaaaaaaa-1111-2222-3333-444444444444"
TASK_B = "urn:omos:task-card:bbbbbbbb-1111-2222-3333-444444444444"

failures = []

def assert(condition, message, failures)
  failures << message unless condition
end

load_hook_evaluator!
card_spec = YAML.safe_load(File.read(CARD_SPEC_PATH), permitted_classes: [], aliases: false)
hook_spec = YAML.safe_load(File.read(HOOK_SPEC_PATH), permitted_classes: [], aliases: false)
allowed_events = hook_spec.dig("capture_contract", "allowed_events")

# --- 正例：兩個 turn ＋ 重放 ＋ 一筆未宣告 -------------------------------

positive = [
  mapping_record(session_id: "s1", correlation_ref: "t1", event: "start", task_ref: TASK_A, at: "2026-09-16T01:00:00Z"),
  mapping_record(session_id: "s1", correlation_ref: "t1", event: "submit_review", task_ref: TASK_A, at: "2026-09-16T01:01:00Z"),
  mapping_record(session_id: "s1", correlation_ref: "t2", event: "start", task_ref: TASK_A, at: "2026-09-16T01:02:00Z"),
  mapping_record(session_id: "s1", correlation_ref: "t2", event: "submit_review", task_ref: TASK_A, at: "2026-09-16T01:03:00Z"),
  # 重放 t1（同一 turn 同一事件被重複擷取）→ 必須被 event_key 去重
  mapping_record(session_id: "s1", correlation_ref: "t1", event: "start", task_ref: TASK_A, at: "2026-09-16T01:04:00Z"),
  # 另一張卡
  mapping_record(session_id: "s2", correlation_ref: "t9", event: "start", task_ref: TASK_B, at: "2026-09-16T01:05:00Z"),
  mapping_record(session_id: "s2", correlation_ref: "t9", event: "submit_review", task_ref: TASK_B, at: "2026-09-16T01:06:00Z"),
  # 未宣告 → 不進 batch（FP-1-A）
  mapping_record(session_id: "s3", correlation_ref: "tx", event: "start", task_ref: nil, at: "2026-09-16T01:07:00Z")
]

batches = build_batches(positive)
assert(batches.size == 2, "應依 task_ref 分成 2 個 batch，實際 #{batches.size}", failures)

batches.each do |batch|
  refs = batch["raw_events"].map { |e| e["task_ref"] }.uniq
  assert(refs.size == 1, "一個 batch 只能含一個 task_ref，實際 #{refs.inspect}", failures)
  assert(refs.first != nil && refs.first.start_with?("urn:omos:task-card:"),
         "batch 的 task_ref 必須是 task-card URN，實際 #{refs.first.inspect}", failures)
  code = hook_capture_failure(batch, card_spec, allowed_events)
  assert(code.nil?, "正例 batch 應通過 hook_capture_failure，實際 #{code.inspect}", failures)
end

task_a_batch = batches.find { |b| b["raw_events"].first["task_ref"] == TASK_A }
assert(!task_a_batch.nil?, "找不到 TASK_A 的 batch", failures)
if task_a_batch
  assert(task_a_batch["raw_events"].size == 5,
         "TASK_A 的 raw 應為 5 筆，實際 #{task_a_batch['raw_events'].size}", failures)
  assert(task_a_batch["emitted"]["lifecycle_events"] == %w[start submit_review start submit_review],
         "重放應被去重成 start/submit_review/start/submit_review，實際 " \
         "#{task_a_batch['emitted']['lifecycle_events'].inspect}", failures)
end

# --- 負例 1（F-01）：宣告的不是 task-card URN → 必須整批拒絕 -------------

# 兩種都必須被拒：
#   (a) 根本不是 task-card entity
#   (b) 是 task-card 前綴，但 identity 形狀不是 canonical 的 UUID
#       （repair-02：只擋前綴不夠，會放行不存在的身分）
[
  ["urn:omos:evidence:not-a-task-card", "不是 task-card entity"],
  ["urn:omos:task-card:not-a-uuid", "task-card 前綴但非 canonical UUID 形狀"]
].each do |bad_ref, label|
  mis_declared = [
    mapping_record(session_id: "s1", correlation_ref: "t1", event: "start",
                   task_ref: bad_ref, at: "2026-09-16T01:00:00Z"),
    mapping_record(session_id: "s1", correlation_ref: "t1", event: "submit_review",
                   task_ref: bad_ref, at: "2026-09-16T01:01:00Z")
  ]
  status = build_batches_expecting_refusal(mis_declared)
  assert(!status.nil? && status != 0,
         "F-01 負例（#{label}）：#{bad_ref} 必須被 fail-closed 拒絕（非 0 結束碼），實際 #{status.inspect}",
         failures)
end

# 對照組：canonical UUID 形狀必須放行（確認收窄沒有過頭）。
assert(TASK_CARD_URN.match?(TASK_A),
       "canonical UUID 形狀的 task_ref 不該被擋：#{TASK_A}", failures)

# --- 負例 2（F-02）：分隔符歧義的兩個不同 turn 不得被誤併 ----------------
#
# 舊版用 "session:correlation:event" 串接，("a:b","c") 與 ("a","b:c")
# 會撞成同一個 key，raw=2 卻 emitted=1。

ambiguous = [
  mapping_record(session_id: "a:b", correlation_ref: "c", event: "start",
                 task_ref: TASK_A, at: "2026-09-16T01:00:00Z"),
  mapping_record(session_id: "a", correlation_ref: "b:c", event: "start",
                 task_ref: TASK_A, at: "2026-09-16T01:01:00Z")
]
ambiguous_batches = build_batches(ambiguous)
assert(ambiguous_batches.size == 1, "歧義負例應只有一個 batch", failures)
if ambiguous_batches.size == 1
  batch = ambiguous_batches.first
  keys = batch["raw_events"].map { |e| e["event_key"] }
  assert(keys.uniq.size == 2,
         "F-02 負例：('a:b','c') 與 ('a','b:c') 必須產生不同的 event_key，實際 #{keys.inspect}", failures)
  assert(batch["emitted"]["lifecycle_events"].size == 2,
         "F-02 負例：兩個不同 turn 不得被去重成一筆，實際 " \
         "#{batch['emitted']['lifecycle_events'].inspect}", failures)
end

if failures.empty?
  puts "PASS aiwr capture batch builder validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
