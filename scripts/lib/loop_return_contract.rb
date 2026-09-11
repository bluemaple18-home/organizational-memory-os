# frozen_string_literal: true
#
# evaluator return contract —— 由 Ruby 語法樹求得，而非掃原始碼文字。
#
# SSP302-F-01 兩度指出同一件事：regex 對「evaluator 到底會回傳什麼」必然是
# under-approximation。
#
#   第一次：掃描只認雙引號字面量，`return 'LOOP_UNDECLARED'` 整個看不見。
#   第二次：形式檢查只看「strip 後以 return 開頭的實體行」，
#           `if run["x"]; return EXPECTED_OUTCOMES.first; end` 整條看不見。
#
# 每補一次 regex，就只是把漏洞推到下一種合法語法。這裡改用 Ripper（Ruby stdlib，
# 不新增相依）解析 validator 自身，取得 evaluator 真正的 return site 集合：
# return site 是窮舉出來的，不是猜的。
#
# 契約：evaluator 內每一個 return 只能是
#   - `return nil`（允許，不帶 code）
#   - `return "<CODE>"` 單一無插值字串字面量，且符合 LOOP_CODE_PATTERN
# 其餘一律歸類為 DISALLOWED，由呼叫端轉紅。

require "ripper"

module LoopReturnContract
  DISALLOWED = :disallowed_return_form
  CODE_PATTERN = /\A[A-Z][A-Z0-9_]*\z/.freeze

  module_function

  # 走訪語法樹，對每個 Array 節點呼叫 block。
  def each_node(node, &block)
    return unless node.is_a?(Array)

    block.call(node)
    node.each { |child| each_node(child, &block) }
  end

  def evaluator_def_node(source_path, evaluator_name)
    sexp = Ripper.sexp(File.read(source_path))
    raise "#{source_path} 無法被解析，無法求得 #{evaluator_name} 的 return site" if sexp.nil?

    found = nil
    each_node(sexp) do |node|
      next unless found.nil? && node[0] == :def
      name = node[1]
      found = node if name.is_a?(Array) && name[1] == evaluator_name
    end
    raise "在 #{source_path} 找不到 #{evaluator_name} 定義" if found.nil?

    found
  end

  def return_nodes(source_path, evaluator_name)
    nodes = []
    each_node(evaluator_def_node(source_path, evaluator_name)) do |node|
      nodes << node if node[0] == :return || node[0] == :return0
    end
    nodes
  end

  # 允許且帶 code → 回傳 code 字串；允許但不帶 code（return nil）→ 回傳 nil；
  # 其餘形式 → 回傳 DISALLOWED。
  def classify(node)
    return DISALLOWED unless node[0] == :return

    args = node[1]
    return DISALLOWED unless args.is_a?(Array) && args[0] == :args_add_block

    list = args[1]
    return DISALLOWED unless list.is_a?(Array) && list.length == 1

    argument = list[0]
    return nil if nil_keyword?(argument)

    code = plain_string_literal(argument)
    return code if code && CODE_PATTERN.match?(code)

    DISALLOWED
  end

  def nil_keyword?(argument)
    argument.is_a?(Array) && argument[0] == :var_ref &&
      argument[1].is_a?(Array) && argument[1][0] == :@kw && argument[1][1] == "nil"
  end

  # 單一段、無插值的字串字面量才算數；"LOOP_#{x}" 會有兩段，直接落回 DISALLOWED。
  def plain_string_literal(argument)
    return nil unless argument.is_a?(Array) && argument[0] == :string_literal

    content = argument[1]
    return nil unless content.is_a?(Array) && content[0] == :string_content

    parts = content[1..]
    return nil unless parts.length == 1 && parts[0].is_a?(Array) && parts[0][0] == :@tstring_content

    parts[0][1]
  end

  # 節點子樹裡第一個 [line, column]，用來把違規 return 指回原始碼位置。
  def position_of(node)
    position = nil
    each_node(node) do |inner|
      next unless position.nil?
      next unless inner.length == 2 && inner.all? { |value| value.is_a?(Integer) }

      position = inner
    end
    position
  end

  # --- 出口形狀凍結（Owner spec-freeze FP-1-B，2026-09-11 簽核）------------
  #
  # 顯式 return 可以窮舉,隱式回傳不行:Ruby 方法會回傳最後一個 expression 的值,
  # 而「最後一個 expression」可以是 if/else、三元、方法呼叫、rescue 子句……
  # 要靜態涵蓋全部 tail position,等於做一個迷你控制流分析 —— 那又是一次逼近
  # 開放集合,正是 SSP302-F-01 連三輪的成因。
  #
  # 因此改為把出口形狀本身凍結,讓出口集合成為全集:
  #   - bodystmt 不得有 rescue / else / ensure 子句(否則會多出 tail position);
  #   - 方法的最後一句必須恰好是 nil 字面量。
  # 如此方法只剩兩種回傳途徑:被分類過的顯式 return,或尾端那個 nil。
  #
  # 邊界:例外不是回傳值。evaluator 拋例外會讓 validator 崩潰並轉紅,
  # 不會變成一個未被宣告的 code。
  def exit_shape_violations(source_path, evaluator_name)
    body = evaluator_def_node(source_path, evaluator_name)[3]
    violations = []

    unless body.is_a?(Array) && body[0] == :bodystmt
      return ["#{evaluator_name} 的函式本體不是可分析的 bodystmt"]
    end

    violations << "#{evaluator_name} 不得有 rescue 子句" unless body[2].nil?
    violations << "#{evaluator_name} 不得有 rescue-else 子句" unless body[3].nil?
    violations << "#{evaluator_name} 不得有 ensure 子句" unless body[4].nil?

    statements = body[1]
    if !statements.is_a?(Array) || statements.empty?
      violations << "#{evaluator_name} 沒有可分析的語句"
    elsif !nil_keyword?(statements.last)
      violations << "#{evaluator_name} 的最後一句必須是 nil 字面量（隱式回傳唯一允許的值）"
    end

    violations
  end

  def classifications(source_path, evaluator_name)
    return_nodes(source_path, evaluator_name).map { |node| [node, classify(node)] }
  end

  def reachable_codes(source_path, evaluator_name)
    classifications(source_path, evaluator_name).map(&:last).grep(String).uniq
  end

  def disallowed_returns(source_path, evaluator_name)
    classifications(source_path, evaluator_name)
      .select { |_, code| code == DISALLOWED }
      .map { |node, _| "line #{position_of(node)&.first || "?"}" }
  end
end
