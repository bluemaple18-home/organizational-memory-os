# frozen_string_literal: true

# artifact 必須用**自己的** Gemfile 與 vendored gem，不得繼承呼叫端的 bundler
# 環境。原本寫 ||=，於是從任何 bundler 專案目錄（或被這類行程 spawn）執行時，
# 繼承來的 BUNDLE_GEMFILE 會讓 artifact 去載別人的 gem——實測已安裝的 artifact
# 因此載到 repo 的 vendor 而非自己的。一律強制覆寫並清掉繼承的 bundler 狀態。
ENV["BUNDLE_GEMFILE"] = File.expand_path("../../../Gemfile", __dir__)
%w[RUBYOPT BUNDLE_PATH BUNDLE_BIN_PATH BUNDLE_APP_CONFIG BUNDLER_VERSION
   BUNDLER_SETUP].each { |k| ENV.delete(k) }
require "bundler/setup"
$LOAD_PATH.unshift(File.expand_path("../..", __dir__))
require "omos/version_guard"
OMOS::VersionGuard.assert!
require "omos/runtime_profile"
OMOS::RuntimeProfile.assert_supported!
require "omos/mcp_server"

store = ENV["OMOS_PERSONAL_MEMORY_STORE"] ||
        File.expand_path("~/.omos/personal-memory/personal.db")
OMOS::MCPServer.serve_stdio(store)
