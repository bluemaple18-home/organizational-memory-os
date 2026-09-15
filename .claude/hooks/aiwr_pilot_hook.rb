#!/usr/bin/env ruby
# frozen_string_literal: true
#
# SSP-310 / AIWR-12：最小真實 runtime hook（PM pilot 前置，見
# .work/CARD-SSP310-PILOT-RUNTIME-HOOK-20260915.md）。
#
# 只在本 worktree 生效（透過 `claude --settings` 明示載入，見
# .work/evidence/SSP310-PILOT-RUNTIME-HOOK-20260915.md repair-01，
# **不**放在會被自動載入、跟著 repo 一起分享的 committed .claude/
# settings.json——那是大 review F-01 找到的洞）。只接 UserPromptSubmit／
# Stop 兩個事件，依 規格/v0.1/claude-code-native-adapter.yaml 的
# lifecycle_event_map 分類，append 一行 JSON 到本地 evidence log。
#
# 硬性約束（Owner 核准的最小 footprint，見卡片，不可自行擴大）：
#   - 絕不印任何東西到 stdout（UserPromptSubmit 的 stdout 會被當成 context
#     插入對話，印東西就是污染使用者的真實對話——絕對禁止）。
#   - 絕不用非 0 exit code（避免意外阻擋使用者的正常操作）。
#   - 絕不記錄 prompt／回覆的實際內容，只記分類 metadata——**包含任何
#     debug／錯誤訊息路徑**（repair-01：`e.message` 會把 JSON parser
#     吃到一半的原始輸入片段帶出來，等於間接記錄了內容；只能記
#     `e.class.name` 這種穩定、跟輸入內容無關的值）。
#   - 只寫出真的符合既有 validate_claude_code_native_adapter_contract.rb
#     的 claude_code_mapping_failure 語意的 record；不符合的一律不寫
#     （repair-01：先前 NOT_LIFECYCLE／缺 native_correlation_ref 的案例
#     會被那支既有 evaluator 判定不合法，寫出來是偽造合法證據）。
#   - 任何內部錯誤 fail-open（不影響 session）、寫進本地 debug log
#     fail-loud（自己看得到，但不含任何輸入內容）。
#   - 只 append 到本檔案定義的路徑，不做任何網路呼叫。

require "json"
require "time"
require "yaml"
require "fileutils"

# 一律用這支腳本自己的位置定位 repo（.claude/hooks/ 往上兩層），不依賴
# CLAUDE_PROJECT_DIR——否則從別的目錄啟動 session 時，log 會被寫到那個
# 目錄去。這支 hook 服務的永遠是它自己所在的這個 repo。
PROJECT_DIR = File.expand_path("../..", __dir__)
SPEC_PATH = File.join(PROJECT_DIR, "規格/v0.1/claude-code-native-adapter.yaml")
LOG_PATH = File.join(PROJECT_DIR, ".work/evidence/ssp310-pilot-runtime-log.jsonl")
DEBUG_LOG_PATH = File.join(PROJECT_DIR, ".work/evidence/ssp310-pilot-runtime-debug.log")

# 穩定、跟輸入內容無關的 skip 原因碼——絕不含任何 stdin-derived 文字。
def debug_log(reason_code)
  FileUtils.mkdir_p(File.dirname(DEBUG_LOG_PATH))
  File.open(DEBUG_LOG_PATH, "a") { |f| f.puts("[#{Time.now.utc.iso8601}] #{reason_code}") }
rescue StandardError
  nil # debug log 本身失敗也不能讓 hook 有任何可見副作用
end

def append_log(record)
  FileUtils.mkdir_p(File.dirname(LOG_PATH))
  File.open(LOG_PATH, "a") { |f| f.puts(record.to_json) }
rescue StandardError
  debug_log("APPEND_LOG_WRITE_FAILED")
end

# 只在「一定會通過既有 claude_code_mapping_failure 語意」時才回傳一個
# record；其餘情況一律回傳 nil（連 NOT_LIFECYCLE 這種看似無害的分類都
# 不寫——這支 hook 只註冊在 UserPromptSubmit／Stop 兩個事件上，兩者在
# 契約裡都屬於 lifecycle_event_map，真的收到未分類事件是不該發生的異常
# 狀況，不是可以安全落地成證據的正常路徑）。
def classify(input, lifecycle_map)
  native_event = input["hook_event_name"]
  prompt_id = input["prompt_id"]
  stop_hook_active = input["stop_hook_active"]

  return [nil, "UNCLASSIFIED_NATIVE_EVENT"] unless lifecycle_map.key?(native_event)
  return [nil, "MISSING_NATIVE_CORRELATION_REF"] unless prompt_id.is_a?(String) && !prompt_id.strip.empty?

  # SPEC_FREEZE FP-2-A：Stop 在同一 turn 內因為 Stop hook block 而重複
  # 觸發時，stop_hook_active 為 true，這次不是真的終態。既有 evaluator
  # 對這個情況「MAPPED 或 NOT_LIFECYCLE 都不合法」——唯一正確的處理是完全
  # 不寫 mapping_run record，不是換一個 outcome 硬寫。
  return [nil, "STOP_HOOK_ACTIVE_NOT_TERMINAL"] if native_event == "Stop" && stop_hook_active == true

  declared_target = lifecycle_map.fetch(native_event)
  record = { native_event_type: native_event, mapped_to: declared_target, outcome: "MAPPED",
             native_correlation_ref: prompt_id }
  record[:stop_hook_active] = stop_hook_active if native_event == "Stop"
  [record, nil]
end

begin
  raw_stdin = $stdin.read
  input = JSON.parse(raw_stdin)
  spec = YAML.safe_load(File.read(SPEC_PATH), permitted_classes: [], aliases: false)
  lifecycle_map = spec.dig("lifecycle_event_map", "map") || {}

  record, skip_reason = classify(input, lifecycle_map)

  if record
    record[:adapter_output_ref] = "urn:omos:ssp310-pilot-evidence:#{input['session_id']}:#{Time.now.utc.iso8601(6)}"
    record[:occurred_at] = Time.now.utc.iso8601
    record[:session_id] = input["session_id"]
    append_log(record)
  else
    debug_log("SKIPPED_#{skip_reason}")
  end
rescue StandardError => e
  # fail-open：任何錯誤都不能讓使用者的操作被卡住或看到任何輸出。
  # 只記 exception class（穩定、跟輸入內容無關），絕不記 e.message
  # ——message 可能帶著 parser 吃到一半的原始輸入片段（repair-01 finding）。
  debug_log("HOOK_ERROR_#{e.class.name.gsub('::', '_')}")
end

# 刻意不印任何東西到 stdout；exit code 永遠 0（script 正常結束即是 0，
# 不呼叫 exit 1／exit 2）。
