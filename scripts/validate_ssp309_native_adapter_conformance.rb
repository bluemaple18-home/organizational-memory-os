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
#         （在該契約自己的 mapping_run 底下有一個只在單邊出現、且值是非空
#         String 的 <field>_rule 說明——不是只放一個空殼 key）例外。
#   C-02：error_contract 的語意碼（去掉 CODEX_／CLAUDE_CODE_ 前綴後）兩邊須
#         互相對應；有差集的碼必須能在該契約自己 parsed 後的 design_note／
#         *_rule 敘述性欄位裡找到至少一次引用（證明是有記錄的平台差異，不是
#         漏做——只掃 raw YAML 文字會被任意 comment 騙過，故意不那麼做）。
#
# 研究結論（見 .work/evidence/SSP309-NATIVE-ADAPTER-CONFORMANCE-20260915.md）：
# 原計畫的第三條「lifecycle_event_map 綁定 ai-task-card-record.yaml」已經由
# 兩支既有 validator 各自 fail-closed 做過（讀取 TASK_CARD_SPEC_PATH 並綁定
# 每個 target），本檔不重做，避免「兩份手寫清單互相比對」的重複模式。
#
# repair-01（2026-09-15）：big review NO_GO 兩筆 P2——C-01 只驗 key 存在會被
# `foo_rule: null` 騙過；C-02 掃整份 raw text、count>=2 會被任意 comment 騙
# 過。改為 C-01 要求 *_rule 值是非空 String，C-02 改掃 parsed 後的敘述性欄位
# （design_note／*_rule 的字串值），不再讀 raw file text。

require "set"
require_relative "lib/omos_contract_helpers"

ROOT = File.expand_path("..", __dir__)
CODEX_SPEC_PATH = File.join(ROOT, "規格/v0.1/codex-native-adapter.yaml")
CLAUDE_SPEC_PATH = File.join(ROOT, "規格/v0.1/claude-code-native-adapter.yaml")

# --- 共用：從整份 parsed YAML 遞迴收集「書面理由」文字 ---------------------
#
# 只收 key 為 design_note，或 key 以 _rule 結尾、且值是非空 String 的節點。
# 刻意不掃 raw file text——comment、任意字串都不算數，只有契約自己在敘述性
# 欄位裡真的寫了東西才算「有書面理由」。

def collect_rationale_strings(node, acc)
  case node
  when Hash
    node.each do |key, value|
      acc << value if value.is_a?(String) && !value.strip.empty? && (key == "design_note" || key.to_s.end_with?("_rule"))
      collect_rationale_strings(value, acc)
    end
  when Array
    node.each { |item| collect_rationale_strings(item, acc) }
  end
end

def rationale_text(spec)
  acc = []
  collect_rationale_strings(spec, acc)
  acc.join("\n")
end

# --- C-01：mapping_run 核心欄位／outcomes 一致 -----------------------------
#
# 平台專屬例外只在「本側有 <field>_rule 且值是非空 String（真的寫了理由，
# 不是只放一個空殼 key）、對側完全沒有這個 key」時成立——只驗 key 存在會被
# `foo_rule: null` 這種空殼騙過（big review F-01 找到的洞）。

def platform_specific_field?(field, own_mr, other_mr)
  key = "#{field}_rule"
  rule_value = own_mr[key]
  written = rule_value.is_a?(String) && !rule_value.strip.empty?
  written && !other_mr.key?(key)
end

def mapping_run_conformance_failures(codex_mr, claude_mr)
  failures = []
  codex_fields = codex_mr.fetch("fields", [])
  claude_fields = claude_mr.fetch("fields", [])

  codex_core = codex_fields.reject { |f| platform_specific_field?(f, codex_mr, claude_mr) }
  claude_core = claude_fields.reject { |f| platform_specific_field?(f, claude_mr, codex_mr) }

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

# codex_rationale／claude_rationale 是 rationale_text(spec) 的結果——只來自
# design_note／*_rule 這些「敘述性欄位」的解析後字串值，不是整份 raw YAML
# 文字。comment、任意行都不在這裡面，避免 big review F-02 找到的洞（隨便加
# 兩行無語意 comment 就能騙過 count>=2）。

def error_contract_conformance_failures(codex_ec, claude_ec, codex_rationale, claude_rationale)
  failures = []
  codex_base_to_full = codex_ec.keys.each_with_object({}) { |k, h| h[strip_prefix(k, "CODEX_")] = k }
  claude_base_to_full = claude_ec.keys.each_with_object({}) { |k, h| h[strip_prefix(k, "CLAUDE_CODE_")] = k }

  codex_only = codex_base_to_full.keys - claude_base_to_full.keys
  claude_only = claude_base_to_full.keys - codex_base_to_full.keys

  codex_only.each do |base|
    full = codex_base_to_full.fetch(base)
    assert(codex_rationale.include?(full),
           "codex-native-adapter.yaml 的平台專屬錯誤碼 #{full} 沒有在任何 design_note／*_rule 敘述性欄位裡被引用",
           failures)
  end
  claude_only.each do |base|
    full = claude_base_to_full.fetch(base)
    assert(claude_rationale.include?(full),
           "claude-code-native-adapter.yaml 的平台專屬錯誤碼 #{full} 沒有在任何 design_note／*_rule 敘述性欄位裡被引用",
           failures)
  end
  failures
end

# --- 對真實契約跑 -----------------------------------------------------------

failures = []

codex_spec = read_yaml(CODEX_SPEC_PATH)
claude_spec = read_yaml(CLAUDE_SPEC_PATH)
codex_rationale = rationale_text(codex_spec)
claude_rationale = rationale_text(claude_spec)

failures.concat(mapping_run_conformance_failures(codex_spec.fetch("mapping_run"), claude_spec.fetch("mapping_run")))
failures.concat(error_contract_conformance_failures(codex_spec.fetch("error_contract"), claude_spec.fetch("error_contract"),
                                                     codex_rationale, claude_rationale))

# --- self-test：證明兩條斷言不是恆真，且兩個 big-review finding 的洞已補 ----
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

# big review F-01（2026-09-15）復現：加一個新欄位＋一個空殼 `_rule: null`，
# 沒有真的寫理由，不該獲得平台專屬豁免。
blank_rule_exemption_bypass = mapping_run_conformance_failures(
  codex_spec.fetch("mapping_run").merge(
    "fields" => codex_spec.fetch("mapping_run").fetch("fields") + ["other_platform_field"],
    "other_platform_field_rule" => nil
  ),
  claude_spec.fetch("mapping_run")
)
assert(!blank_rule_exemption_bypass.empty?,
       "self-test 失敗：F-01 復現——*_rule 是 null 時不該被當成已寫理由而獲得豁免，實際通過", self_test_failures)

# 對照組：同一個新欄位，這次 `_rule` 是真的非空字串 → 應該被豁免、視為平台差異。
real_rule_exemption = mapping_run_conformance_failures(
  codex_spec.fetch("mapping_run").merge(
    "fields" => codex_spec.fetch("mapping_run").fetch("fields") + ["other_platform_field"],
    "other_platform_field_rule" => "self-test：這是一個真的寫了理由的平台專屬欄位。"
  ),
  claude_spec.fetch("mapping_run")
)
assert(real_rule_exemption.empty?,
       "self-test 失敗：*_rule 是非空字串、對側沒有同名 key 時應該被豁免，實際被擋", self_test_failures)

undocumented_code_failures = error_contract_conformance_failures(
  codex_spec.fetch("error_contract").merge("CODEX_SURPRISE_UNDOCUMENTED" => "codex_native.error.surprise_undocumented"),
  claude_spec.fetch("error_contract"),
  codex_rationale, # rationale 裡完全沒有這個字串
  claude_rationale
)
assert(!undocumented_code_failures.empty?,
       "self-test 失敗：F-02 復現——平台專屬錯誤碼完全沒被 design_note／*_rule 引用時必須回報，實際通過。" \
       "（原本的洞是掃 raw file text、count>=2，comment 就能騙過；改成只掃 parsed rationale 欄位後，" \
       "comment 這個攻擊面已經在結構上不存在——error_contract_conformance_failures 現在根本不接受 raw text。）",
       self_test_failures)

# 對照組：同一個新碼，這次真的在某個 *_rule 敘述性欄位裡提過一次 → 應該通過。
documented_code_failures = error_contract_conformance_failures(
  codex_spec.fetch("error_contract").merge("CODEX_REAL_NEW_DIFFERENCE" => "codex_native.error.real_new_difference"),
  claude_spec.fetch("error_contract"),
  "#{codex_rationale}\nself-test：CODEX_REAL_NEW_DIFFERENCE 在這裡被真的引用了一次。",
  claude_rationale
)
assert(documented_code_failures.empty?,
       "self-test 失敗：平台專屬錯誤碼真的出現在 rationale 文字裡時不應該被擋下，實際被擋", self_test_failures)

assert(self_test_failures.empty?, "self-test 未全部通過：#{self_test_failures.join('; ')}", failures)

if failures.empty?
  puts "PASS ssp309 native adapter conformance validation"
else
  failures.each { |failure| warn "FAIL #{failure}" }
  exit 1
end
