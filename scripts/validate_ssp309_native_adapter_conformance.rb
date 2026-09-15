#!/usr/bin/env ruby
#
# SSP-309 / AIWR-11：Codex／Claude Code Native Adapter conformance validator。
#
# 兩份 Native Adapter 契約（codex-native-adapter.yaml／claude-code-native-adapter.yaml）
# 各自已經是通過大 review 的獨立契約，本 validator 不重驗它們各自的內部斷言
# （那是 validate_codex_native_adapter_contract.rb／
# validate_claude_code_native_adapter_contract.rb 的責任），只驗證兩者之間
# 「已經宣告要遵守」但沒人真的比對過的一致性：
#
#   C-01：mapping_run 的核心欄位集合與 outcomes 列舉兩邊須相等，平台專屬欄位
#         （在該契約自己的 mapping_run 底下有一個只在單邊出現的 <field>_rule
#         說明）例外。
#   C-02：error_contract 的語意碼（去掉 CODEX_／CLAUDE_CODE_ 前綴後）兩邊須
#         互相對應；有差集的碼必須能在該契約自己的文件文字裡找到 error_contract
#         之外的至少一次引用（證明是有記錄的平台差異，不是漏做）。
#
# 研究結論（見 .work/evidence/SSP309-NATIVE-ADAPTER-CONFORMANCE-20260915.md）：
# 原計畫的第三條「lifecycle_event_map 綁定 ai-task-card-record.yaml」已經由
# 兩支既有 validator 各自 fail-closed 做過（讀取 TASK_CARD_SPEC_PATH 並綁定
# 每個 target），本檔不重做，避免「兩份手寫清單互相比對」的重複模式。

require "set"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
CODEX_SPEC_PATH = File.join(ROOT, "規格/v0.1/codex-native-adapter.yaml")
CLAUDE_SPEC_PATH = File.join(ROOT, "規格/v0.1/claude-code-native-adapter.yaml")

# --- C-01：mapping_run 核心欄位／outcomes 一致 -----------------------------

def platform_specific_field?(field, own_rule_keys, other_rule_keys)
  key = "#{field}_rule"
  own_rule_keys.include?(key) && !other_rule_keys.include?(key)
end

def mapping_run_conformance_failures(codex_mr, claude_mr)
  failures = []
  codex_fields = codex_mr.fetch("fields", [])
  claude_fields = claude_mr.fetch("fields", [])
  codex_rule_keys = codex_mr.keys.select { |k| k.end_with?("_rule") }
  claude_rule_keys = claude_mr.keys.select { |k| k.end_with?("_rule") }

  codex_core = codex_fields.reject { |f| platform_specific_field?(f, codex_rule_keys, claude_rule_keys) }
  claude_core = claude_fields.reject { |f| platform_specific_field?(f, claude_rule_keys, codex_rule_keys) }

  assert(sorted_set(codex_core) == sorted_set(claude_core),
         "mapping_run 核心欄位集合須相等（扣除各自已有平台專屬 *_rule 理由的欄位）：" \
         "codex=#{codex_core.sort} claude=#{claude_core.sort}", failures)
  assert(sorted_set(codex_mr.fetch("outcomes", [])) == sorted_set(claude_mr.fetch("outcomes", [])),
         "mapping_run.outcomes 兩邊須逐字相等：codex=#{codex_mr["outcomes"]} claude=#{claude_mr["outcomes"]}",
         failures)
  failures
end

# --- C-02：error_contract 語意碼對應 ---------------------------------------

def strip_prefix(code, prefix)
  code.start_with?(prefix) ? code.sub(/\A#{Regexp.escape(prefix)}/, "") : code
end

def error_contract_conformance_failures(codex_ec, claude_ec, codex_raw, claude_raw)
  failures = []
  codex_base_to_full = codex_ec.keys.each_with_object({}) { |k, h| h[strip_prefix(k, "CODEX_")] = k }
  claude_base_to_full = claude_ec.keys.each_with_object({}) { |k, h| h[strip_prefix(k, "CLAUDE_CODE_")] = k }

  codex_only = codex_base_to_full.keys - claude_base_to_full.keys
  claude_only = claude_base_to_full.keys - codex_base_to_full.keys

  codex_only.each do |base|
    full = codex_base_to_full.fetch(base)
    count = codex_raw.scan(full).size
    assert(count >= 2,
           "codex-native-adapter.yaml 的平台專屬錯誤碼 #{full} 在 error_contract 之外沒有被文件化理由引用" \
           "（只出現 #{count} 次）", failures)
  end
  claude_only.each do |base|
    full = claude_base_to_full.fetch(base)
    count = claude_raw.scan(full).size
    assert(count >= 2,
           "claude-code-native-adapter.yaml 的平台專屬錯誤碼 #{full} 在 error_contract 之外沒有被文件化理由引用" \
           "（只出現 #{count} 次）", failures)
  end
  failures
end

# --- 對真實契約跑 -----------------------------------------------------------

failures = []

codex_spec = read_yaml(CODEX_SPEC_PATH)
claude_spec = read_yaml(CLAUDE_SPEC_PATH)
codex_raw = File.read(CODEX_SPEC_PATH)
claude_raw = File.read(CLAUDE_SPEC_PATH)

failures.concat(mapping_run_conformance_failures(codex_spec.fetch("mapping_run"), claude_spec.fetch("mapping_run")))
failures.concat(error_contract_conformance_failures(codex_spec.fetch("error_contract"), claude_spec.fetch("error_contract"),
                                                     codex_raw, claude_raw))

# --- self-test：證明兩條斷言不是恆真 ----------------------------------------
#
# 在記憶體裡建構違規版本的輸入，呼叫同一個 pure function，確認它真的會回報
# failure——不對兩份契約檔案做任何寫入，不需要 cp 備份／還原。

self_test_failures = []

broken_extra_field = mapping_run_conformance_failures(
  codex_spec.fetch("mapping_run").merge("fields" => codex_spec.fetch("mapping_run").fetch("fields") + ["surprise_field"]),
  claude_spec.fetch("mapping_run")
)
assert(!broken_extra_field.empty?,
       "self-test 失敗：mapping_run 核心欄位集合不相等時必須回報，實際通過", self_test_failures)

broken_outcomes = mapping_run_conformance_failures(
  codex_spec.fetch("mapping_run").merge("outcomes" => %w[MAPPED NOT_LIFECYCLE]),
  claude_spec.fetch("mapping_run")
)
assert(!broken_outcomes.empty?,
       "self-test 失敗：outcomes 集合不相等時必須回報，實際通過", self_test_failures)

undocumented_code_failures = error_contract_conformance_failures(
  codex_spec.fetch("error_contract").merge("CODEX_SURPRISE_UNDOCUMENTED" => "codex_native.error.surprise_undocumented"),
  claude_spec.fetch("error_contract"),
  codex_raw, # 真實檔案文字裡完全沒有這個字串，count 必為 0
  claude_raw
)
assert(!undocumented_code_failures.empty?,
       "self-test 失敗：平台專屬錯誤碼完全沒被文件引用時必須回報，實際通過", self_test_failures)

documented_code_name = "CODEX_SELF_TEST_DOCUMENTED_CODE"
documented_raw = "#{codex_raw}\n# #{documented_code_name} 第一次引用\n# #{documented_code_name} 第二次引用\n"
documented_code_failures = error_contract_conformance_failures(
  codex_spec.fetch("error_contract").merge(documented_code_name => "codex_native.error.self_test_documented_code"),
  claude_spec.fetch("error_contract"),
  documented_raw,
  claude_raw
)
assert(documented_code_failures.empty?,
       "self-test 失敗：平台專屬錯誤碼在文件裡被引用兩次以上時不應該被擋下，實際被擋", self_test_failures)

assert(self_test_failures.empty?, "self-test 未全部通過：#{self_test_failures.join('; ')}", failures)

if failures.empty?
  puts "PASS ssp309 native adapter conformance validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
