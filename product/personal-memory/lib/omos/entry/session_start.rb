# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __dir__)
require "bundler/setup"
$LOAD_PATH.unshift(File.expand_path("../..", __dir__))
require "omos/version_guard"
OMOS::VersionGuard.assert!
require "omos/session_start"
require "json"

raw = $stdin.tty? ? "{}" : $stdin.read
input = raw.strip.empty? ? {} : JSON.parse(raw)
begin
  puts JSON.generate(OMOS::SessionStart.produce(
    host: input["host"] || ENV["OMOS_HOST"],
    native_session_id: input["native_session_id"] || ENV["OMOS_NATIVE_SESSION_ID"],
    cwd: input["cwd"] || Dir.pwd,
    project_ref: input["project_ref"] || ENV["OMOS_PROJECT_REF"],
    runtime_scope_mode: input["runtime_scope_mode"] || ENV["OMOS_RUNTIME_SCOPE_MODE"],
    project_visibility_scope: input["project_visibility_scope"]
  ))
rescue OMOS::SessionStart::Refused => e
  warn "REFUSED #{e.code}"
  exit 1
end
