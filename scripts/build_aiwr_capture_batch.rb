#!/usr/bin/env ruby
# frozen_string_literal: true
#
# AIWR 最後一哩：把 Native Adapter pilot hook 記錄的 mapping_run，組成
# ai-work-record-hook.yaml 的 capture batch。
#
# 實作 Owner 於 2026-09-16 簽定的凍結點
# （.work/CARD-AIWR-LAST-MILE-SPEC-FREEZE-20260916.md）：
#
#   FP-1-A：task_ref 由呼叫端在啟動 session 時以 OMOS_TASK_REF 明示宣告，
#           由 hook 原樣記在 declared_task_ref。沒宣告的記錄不組 batch。
#           本檔不核發、不解析、不推論任何 task-card URN。
#   FP-2-A：終點是產出「通過既有 hook_capture_failure 的 capture batch
#           JSON」，不寫入任何 canonical store（系統裡也沒有那種 store）。
#   FP-3-A：event_key 由 (session_id, native_correlation_ref, event) 以
#           JSON tuple 編碼（見 event_key_for 的 repair-01 說明——原本的
#           ":" 串接會碰撞）。決定性、不含時間戳；同一 turn 的同一事件重放
#           會正確去重，跨 turn 不會誤併。刻意不用 adapter_output_ref
#           （含微秒時間戳，每次都不同，去重會形同虛設）。
#
# 用法：
#   ruby scripts/build_aiwr_capture_batch.rb <mapping-run-log.jsonl> <out-dir>
#
# 每個 task_ref 各輸出一個 batch 檔（capture_contract.batch_scoping_rule
# 要求一次呼叫只含一個 task_ref，這是呼叫端責任——本檔就是那個呼叫端）。

require "json"
require "set"

# repair-01 F-01（P1）：光是「合法 OMOS URN」不足以當 task_ref。
# hook_capture_failure 只驗泛型的 urn:omos:<kind>:<rest> 格式，所以
# urn:omos:evidence:... 之類的別種 entity 會被當成 task card 收下去。
# 本檔是把 declared_task_ref 轉成 Hook envelope `task_ref` 的那一層
# ——身分收窄的責任就在這裡，必須 fail-closed。
#
# repair-02 F-01（P1，第二輪）：收窄到 `urn:omos:task-card:` 前綴仍不夠，
# `urn:omos:task-card:not-a-uuid` 這種不存在的身分照樣會過。canonical 的
# task-card identity 形狀定義在
# scripts/validate_ai_task_card_record_contract.rb 的 CARD_ID_URN。
#
# 這裡**綁定**那個常數的原始碼，而不是手抄一份 UUID regex——手抄就會變成
# 兩份各自演化的清單，上游改了這裡不會知道。抽不到就 fail loud。
ROOT = File.expand_path("..", __dir__)
CARD_RECORD_VALIDATOR_PATH = File.join(ROOT, "scripts/validate_ai_task_card_record_contract.rb")

def canonical_task_card_urn_pattern
  source = File.read(CARD_RECORD_VALIDATOR_PATH)
  literal = source[/\nCARD_ID_URN = (\/.*?\/)\.freeze\n/m, 1]
  raise "抽不到 CARD_ID_URN（#{CARD_RECORD_VALIDATOR_PATH} 結構已改變？）" unless literal

  eval(literal) # rubocop:disable Security/Eval -- 來源是本 repo 自己的 validator 原始碼
end

TASK_CARD_URN = canonical_task_card_urn_pattern.freeze

def build_envelope(record)
  {
    "task_ref" => record.fetch("declared_task_ref"),
    "event" => record.fetch("mapped_to"),
    "occurred_at" => record.fetch("occurred_at"),
    "event_key" => event_key_for(record),
    "evidence_refs" => [record.fetch("adapter_output_ref")]
  }
end

# FP-3-A：決定性、不含時間戳。
#
# repair-01 F-02（P1）：原本用 ":" 串接三個值，會碰撞——
# ("a:b","c","start") 與 ("a","b:c","start") 都得到 "a:b:c:start"，
# 兩個不同 turn 被當成同一事件去重。改用 JSON array 編碼，分隔語意由
# JSON 的引號與跳脫負責，任何含 ":" 的值都不會造成歧義。
def event_key_for(record)
  JSON.generate([record.fetch("session_id"),
                 record.fetch("native_correlation_ref"),
                 record.fetch("mapped_to")])
end

def build_capture(envelopes)
  # 去重規則與 hook_capture_failure 一致：以 event_key 去重，emitted 的
  # lifecycle_events 必須等於去重後的事件序列。
  deduped = envelopes.uniq { |e| e["event_key"] }
  {
    "raw_events" => envelopes,
    "emitted" => {
      "lifecycle_events" => deduped.map { |e| e["event"] },
      "batch" => deduped
    },
    # failure_isolation：擷取失敗不得影響宿主任務。本流程是離線組批，
    # 本來就不可能影響任何進行中的任務。
    "host_task_impact" => "UNAFFECTED",
    "disabled" => false
  }
end

def main(log_path, out_dir)
  records = File.readlines(log_path).reject { |l| l.strip.empty? }.map { |l| JSON.parse(l) }

  # 只收 MAPPED 且有呼叫端宣告的記錄。沒有 declared_task_ref 的一律略過
  # ——FP-1-A 明定沒宣告就不產出 batch，不猜、不套用預設值。
  declared = records.select do |r|
    r["outcome"] == "MAPPED" && r["declared_task_ref"].is_a?(String) &&
      !r["declared_task_ref"].strip.empty?
  end

  # F-01 fail-closed：有宣告但不是 task-card URN，代表該 session 的
  # OMOS_TASK_REF 設錯了。不靜默略過（會讓人以為只是沒宣告），也不放行
  # （會把別種 entity 當成 task card 寫進 Hook envelope）——整批停住、
  # 指出錯誤的值，什麼都不產出。
  mis_declared = declared.reject { |r| TASK_CARD_URN.match?(r["declared_task_ref"]) }
  unless mis_declared.empty?
    warn "declared_task_ref 不是 task-card URN，拒絕組批（fail-closed）："
    mis_declared.map { |r| r["declared_task_ref"] }.uniq.each { |v| warn "  #{v}" }
    warn "task_ref 必須符合 canonical task-card identity 形狀 #{TASK_CARD_URN.source}"
    warn "（綁定自 validate_ai_task_card_record_contract.rb 的 CARD_ID_URN）；請修正 OMOS_TASK_REF 後重跑。"
    exit 3
  end

  attributed = declared
  skipped = records.size - attributed.size
  if attributed.empty?
    warn "沒有任何帶 declared_task_ref 的 MAPPED 記錄（共讀入 #{records.size} 筆）。"
    warn "請在啟動 session 前設定 OMOS_TASK_REF=urn:omos:task-card:<uuid>。"
    exit 2
  end

  # 依 task_ref 分組：一個 task_ref 一個 batch（batch_scoping_rule）。
  grouped = attributed.group_by { |r| r["declared_task_ref"] }

  Dir.mkdir(out_dir) unless Dir.exist?(out_dir)
  written = []
  grouped.each do |task_ref, group|
    sorted = group.sort_by { |r| r.fetch("occurred_at") }
    capture = build_capture(sorted.map { |r| build_envelope(r) })
    slug = task_ref.split(":").last.gsub(/[^A-Za-z0-9_-]/, "_")
    path = File.join(out_dir, "capture-batch-#{slug}.json")
    File.write(path, JSON.pretty_generate(capture) + "\n")
    written << [path, task_ref, capture["emitted"]["lifecycle_events"]]
  end

  puts "讀入 #{records.size} 筆；組出 #{written.size} 個 batch（略過 #{skipped} 筆未宣告／非 MAPPED）"
  written.each do |path, task_ref, events|
    puts "  #{File.basename(path)}  task_ref=#{task_ref}  events=#{events.inspect}"
  end
end

# 只有被當成指令執行時才跑 main；被 require 進來（例如常設 regression
# gate）時只提供上面那些純函式，不產生任何副作用。
if __FILE__ == $PROGRAM_NAME
  if ARGV.size != 2
    warn "用法：ruby scripts/build_aiwr_capture_batch.rb <mapping-run-log.jsonl> <out-dir>"
    exit 1
  end

  main(ARGV[0], ARGV[1])
end
