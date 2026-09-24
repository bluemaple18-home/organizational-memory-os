# frozen_string_literal: true
#
# 用錯 Ruby 要當場大聲失敗，不要拋出一堆誤導的語法／方法錯誤。
#
# 實際發生過：以 macOS 系統 Ruby 2.6 重跑 conformance 會出現看似「產品有 bug」
# 的紅字，實際上只是直譯器版本不對。這支把它變成一句話。
#
# **判準是 ABI 相容，不是版本字串相等。**
#
# 2026-09-24：Homebrew 於 9/23 把 ruby@3.4 升到 3.4.11，本檔原本的
# `RUBY_VERSION == "3.4.10"` 於是擋掉了所有新安裝者——而 bin/pinned-ruby.sh
# 與 OMOS::RuntimeProfile 早就改用 ABI 判準並放行了同一個直譯器。同一條規則
# 存在兩份、其中一份形狀是錯的，就會這樣互相矛盾。
#
# 需要的 ABI 直接由 artifact 自己的內容推導：vendored 原生擴充就放在
# vendor/bundle/ruby/<ABI>/ 底下，那個目錄名**就是**它們被編譯時的 ABI。
# 這與 bin/pinned-ruby.sh 的 OMOS_REQUIRED_ABI 是同一個來源，不另立一份。
require "rbconfig"

module OMOS
  module VersionGuard
    ROOT = File.expand_path("../..", __dir__)

    # 只作為訊息裡的參考版本（也供 pinned-ruby.sh 找 rbenv 路徑），
    # **不是**放行判準。
    REQUIRED = begin
      File.read(File.join(ROOT, ".ruby-version")).strip
    rescue SystemCallError
      "unknown"
    end

    # 目錄不只一個（或讀不到）時回 nil → fail closed。
    REQUIRED_ABI = begin
      dirs = Dir.children(File.join(ROOT, "vendor/bundle/ruby"))
      dirs.size == 1 ? dirs.first : nil
    rescue SystemCallError
      nil
    end

    def self.current_abi = RbConfig::CONFIG["ruby_version"]

    def self.compatible? = !REQUIRED_ABI.nil? && current_abi == REQUIRED_ABI

    def self.assert!
      return if compatible?

      warn <<~MSG
        [omos-personal-memory] Ruby ABI 不符：目前 #{RUBY_VERSION}（ABI #{current_abi}），
        本 artifact 的原生擴充編譯於 ABI #{REQUIRED_ABI || "（無法判定）"}（參考版本 #{REQUIRED}）。
        判準是 ABI 相容，不是版本字串相等——同 #{REQUIRED_ABI} 系列的 patch 升級是可接受的。
        請用專案鎖定的直譯器執行，例如：
          PATH="/opt/homebrew/opt/ruby@3.4/bin:$PATH" bundle exec <指令>
        （系統 /usr/bin/ruby 是 2.6，ABI 2.6.0，不受支援）
      MSG
      exit 78 # EX_CONFIG
    end
  end
end
