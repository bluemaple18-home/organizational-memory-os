#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SSP-310 / AIWR-12：最小真實 runtime hook（PM pilot 前置，見
# .work/CARD-SSP310-PILOT-RUNTIME-HOOK-20260915.md）。
#
# 只在本 worktree 生效（project-level .claude/settings.json 註冊，見同
# 目錄下的 settings.json）。只接 UserPromptSubmit／Stop 兩個事件，依
# 規格/v0.1/claude-code-native-adapter.yaml 的 lifecycle_event_map 分類，
# append 一行 JSON 到本地 evidence log。
#
# 硬性約束（Owner 核准的最小 footprint，見卡片，不可自行擴大）：
#   - 絕不印任何東西到 stdout（UserPromptSubmit 的 stdout 會被當成 context
#     插入對話，印東西就是污染使用者的真實對話——絕對禁止）。
#   - 絕不用非 0 exit code（避免意外阻擋使用者的正常操作）。
#   - 絕不記錄 prompt／回覆的實際內容，只記分類 metadata。
#   - 任何內部錯誤 fail-open（不影響 session）、寫進本地 debug log
#     fail-loud（自己看得到）。
#   - 只 append 到本檔案定義的路徑，不做任何網路呼叫。

require "json"
require "time"
require "yaml"
require "fileutils"

PROJECT_DIR = ENV.fetch("CLAUDE_PROJECT_DIR", File.expand_path("../..", __dir__))
SPEC_PATH = File.join(PROJECT_DIR, "規格/v0.1/claude-code-native-adapter.yaml")
LOG_PATH = File.join(PROJECT_DIR, ".work/evidence/ssp310-pilot-runtime-log.jsonl")
DEBUG_LOG_PATH = File.join(PROJECT_DIR, ".work/evidence/ssp310-pilot-runtime-debug.log")

def debug_log(message)
  FileUtils.mkdir_p(File.dirname(DEBUG_LOG_PATH))
  File.open(DEBUG_LOG_PATH, "a") { |f| f.puts("[#{Time.now.utc.iso8601}] #{message}") }
rescue StandardError
  nil # debug log 本身失敗也不能讓 hook 有任何可見副作用
end

def append_log(record)
  FileUtils.mkdir_p(File.dirname(LOG_PATH))
  File.open(LOG_PATH, "a") { |f| f.puts(record.to_json) }
rescue StandardError => e
  debug_log("append_log failed: #{e.class}: #{e.message}")
end

def classify(input, lifecycle_map)
  native_event = input["hook_event_name"]
  prompt_id = input["prompt_id"]
  stop_hook_active = input["stop_hook_active"]

  unless lifecycle_map.key?(native_event)
    return { native_event_type: native_event, mapped_to: nil, outcome: "NOT_LIFECYCLE",
             native_correlation_ref: prompt_id, note: "not in lifecycle_event_map" }
  end

  declared_target = lifecycle_map.fetch(native_event)

  # FP-2-A：Stop 在同一 turn 內因為 Stop hook block 而重複觸發時，
  # stop_hook_active 為 true，這次不是真的終態，不可標記 MAPPED/submit_review。
  if native_event == "Stop" && stop_hook_active == true
    return { native_event_type: native_event, mapped_to: nil, outcome: "NOT_LIFECYCLE",
             native_correlation_ref: prompt_id, stop_hook_active: true,
             note: "stop_hook_active continuation, not terminal (SPEC_FREEZE FP-2-A)" }
  end

  record = { native_event_type: native_event, mapped_to: declared_target, outcome: "MAPPED",
             native_correlation_ref: prompt_id }
  record[:stop_hook_active] = stop_hook_active if native_event == "Stop"
  record
end

begin
  raw_stdin = $stdin.read
  input = JSON.parse(raw_stdin)
  spec = YAML.safe_load(File.read(SPEC_PATH), permitted_classes: [], aliases: false)
  lifecycle_map = spec.dig("lifecycle_event_map", "map") || {}

  record = classify(input, lifecycle_map)
  record[:adapter_output_ref] = "urn:omos:ssp310-pilot-evidence:#{input['session_id']}:#{Time.now.utc.iso8601(6)}"
  record[:occurred_at] = Time.now.utc.iso8601
  record[:session_id] = input["session_id"]

  append_log(record)
rescue StandardError => e
  # fail-open：任何錯誤都不能讓使用者的操作被卡住或看到任何輸出。
  debug_log("hook failed: #{e.class}: #{e.message}")
end

# 刻意不印任何東西到 stdout；exit code 永遠 0（script 正常結束即是 0，
# 不呼叫 exit 1／exit 2）。
