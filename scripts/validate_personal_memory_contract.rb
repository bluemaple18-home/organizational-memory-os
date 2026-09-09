#!/usr/bin/env ruby
#
# Backward-compatible aggregator。
#
# refactor 前這支是單一 monolith,一次驗 personal-memory 契約的全部面向。
# S02 把實作拆成五個 slice validator 後,這支保留原檔名與原行為:依序、
# fail-closed 執行五個 slice,全數 PASS 才印出與 refactor 前逐字相同的
# 「PASS personal memory contract validation」;任一 slice RED 就轉發其
# stdout/stderr 並以 exit 1 結束。
#
# 任何仍只呼叫 `ruby scripts/validate_personal_memory_contract.rb` 的 CI、
# 開發者或下游流程,covered 面向與 refactor 前完全相同,不會因為某個 slice
# 壞掉而得到假綠。

require "open3"
require "rbconfig"

SLICE_VALIDATORS = %w[
  validate_personal_memory_scope_contract
  validate_personal_memory_resource_contract
  validate_personal_capability_contract
  validate_recall_context_pack_contract
  validate_correction_flow_contract
].freeze

any_failure = false

SLICE_VALIDATORS.each do |slice|
  script = File.join(__dir__, "#{slice}.rb")
  stdout_str, stderr_str, status = Open3.capture3(RbConfig.ruby, script)
  next if status.success?

  any_failure = true
  $stdout.write(stdout_str)
  $stderr.write(stderr_str)
  warn "FAIL personal memory contract validation :: slice #{slice} exited #{status.exitstatus.inspect}"
end

if any_failure
  exit 1
else
  puts "PASS personal memory contract validation"
end
