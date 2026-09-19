# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __dir__)
require "bundler/setup"
$LOAD_PATH.unshift(File.expand_path("../..", __dir__))
require "omos/version_guard"
OMOS::VersionGuard.assert!
require "omos/cli"

exit(OMOS::CLI.run(ARGV) || 0)
