# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __dir__)
require "bundler/setup"
$LOAD_PATH.unshift(File.expand_path("../..", __dir__))
require "omos/version_guard"
OMOS::VersionGuard.assert!
require "omos/mcp_server"

store = ENV["OMOS_PERSONAL_MEMORY_STORE"] ||
        File.expand_path("~/.omos/personal-memory/personal.db")
OMOS::MCPServer.serve_stdio(store)
