# frozen_string_literal: true
#
# 用錯 Ruby 要當場大聲失敗，不要拋出一堆誤導的語法／方法錯誤。
#
# 實際發生過：以 macOS 系統 Ruby 2.6 重跑 conformance 會出現看似「產品有 bug」
# 的紅字，實際上只是直譯器版本不對。這支把它變成一句話。

module OMOS
  module VersionGuard
    REQUIRED = File.read(File.expand_path("../../.ruby-version", __dir__)).strip

    def self.assert!
      return if RUBY_VERSION == REQUIRED

      warn <<~MSG
        [omos-personal-memory] Ruby 版本不符：目前 #{RUBY_VERSION}，本產品鎖定 #{REQUIRED}。
        請用專案鎖定的直譯器執行，例如：
          PATH="/opt/homebrew/opt/ruby@3.4/bin:$PATH" bundle exec <指令>
        （系統 /usr/bin/ruby 是 #{RUBY_VERSION == "2.6.10" ? "2.6.10" : "舊版"}，不受支援）
      MSG
      exit 78 # EX_CONFIG
    end
  end
end
