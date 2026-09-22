#!/usr/bin/env ruby
# frozen_string_literal: true
#
# EMEM-11 Slice C｜source ↔ packaged governance 漂移閘（**雙向**）
#
# 為什麼需要這支：產品不再從 repo 的原始位置讀治理檔，而是讀自己 artifact 內
# 的 governance/ 副本（Slice A）。副本一旦與原件脫節，就會出現
# 「產品與 repo 的 39 支 validator 依不同規則判定同一件事」——那正是憲法禁止
# 的**第二套治理**。
#
# 因此這支必須是**雙向**的，兩個方向都會紅：
#   1. 有人改了 repo 原件卻沒有重新產生 package  → 紅
#   2. 有人動了 package 內的副本                → 紅
#
# 只驗第二種（「副本有沒有被竄改」）是不夠的：最可能發生的情況正是第一種
# ——修 spec 的人根本不知道有一份副本要跟著更新。
#
# 本檔刻意**不做自動同步**。自動補齊會讓「漂移」這件事永遠不被看見，
# 而漂移的當下正是需要有人判斷「這次 spec 變更是否該進產品」的時刻。

require "digest"
require "set"

ROOT = File.expand_path("..", __dir__)
PACKAGE_ROOT = File.join(ROOT, "product/personal-memory/governance")

# 與 OMOS::Installer::GOVERNANCE_FILES 同一組。這裡刻意重列而非 require 產品
# 程式碼：這支 validator 要能在產品完全跑不起來時仍然給出判定。
GOVERNANCE_FILES = [
  "規格/v0.1/personal-harness-integration.yaml",
  "規格/v0.1/common-vocabulary.yaml",
  *%w[omos_contract_helpers host_session_binding_shape personal_memory_resource_evaluator
      weekly_closeout_history minimal_evidence_package_shape runtime_log_oracle
      personal_memory_host_binding].map { |n| "scripts/lib/#{n}.rb" }
].freeze

failures = []

# 注意：這支由系統 Ruby（2.6）執行，與其他 39 支 validator 一致。
# 不得使用 3.0+ 語法（endless method 等），否則會在 parse 階段就失敗。
def digest(path)
  File.exist?(path) ? Digest::SHA256.file(path).hexdigest : nil
end

# 方向 1＋2：逐檔雙向比對
GOVERNANCE_FILES.each do |rel|
  src = File.join(ROOT, rel)
  pkg = File.join(PACKAGE_ROOT, rel)

  if digest(src).nil?
    failures << "原件不存在：#{rel}"
    next
  end
  if digest(pkg).nil?
    failures << "package 缺少副本：governance/#{rel}（原件改了卻沒重新產生 package？）"
    next
  end
  next if digest(src) == digest(pkg)

  failures << "漂移：#{rel}\n    原件    #{digest(src)}\n    package #{digest(pkg)}"
end

# 方向 3：package 內不得有多出來的東西——多的檔案同樣是漂移，
# 而且會被算進 artifact identity。
packaged = Dir.glob("**/*", base: PACKAGE_ROOT).reject { |r| File.directory?(File.join(PACKAGE_ROOT, r)) }
extra = packaged.to_set - GOVERNANCE_FILES.to_set
failures << "package 內有非預期的檔案：#{extra.to_a.sort.inspect}" unless extra.empty?

if failures.empty?
  puts "PASS packaged governance drift gate (#{GOVERNANCE_FILES.size} files byte-identical)"
else
  failures.each { |f| warn "FAIL #{f}" }
  warn ""
  warn "  修法：重新產生 package（把原件複製到 product/personal-memory/governance/ 的同一相對路徑），"
  warn "  並確認這次 spec 變更確實應該進入產品——本閘不自動同步，就是為了讓這個判斷不被跳過。"
  exit 1
end
