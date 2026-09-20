# frozen_string_literal: true
#
# SessionStart hook 入口。
#
# **吃的是真 Host 的 stdin**（review P1-B）：兩個 Host 都送
#   { session_id, cwd, hook_event_name, source, ... }
# 本專案自訂的 host / runtime_scope_mode 不在其中，因此由 installer 寫進
# 註冊時的命令列參數（設定檔即信任邊界，hook 沒有 env 欄位可用）。
#
# 輸出的 binding 只是給模型看的 context；**真正被信任的是落地的 session 記錄**，
# 由 MCP server 自己讀回（見 lib/omos/session_state.rb）。

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __dir__)
require "bundler/setup"
$LOAD_PATH.unshift(File.expand_path("../..", __dir__))
require "omos/version_guard"
OMOS::VersionGuard.assert!
require "omos/session_start"
require "omos/session_state"
require "json"
require "optparse"

opts = { host: ENV["OMOS_HOST"], scope_mode: ENV["OMOS_RUNTIME_SCOPE_MODE"] }
OptionParser.new do |o|
  o.on("--host HOST") { |v| opts[:host] = v }
  o.on("--runtime-scope-mode MODE") { |v| opts[:scope_mode] = v }
end.parse!(ARGV)

raw = $stdin.tty? ? "" : $stdin.read.to_s
payload = raw.strip.empty? ? {} : (JSON.parse(raw) rescue {})

session_id = payload["session_id"]
cwd = payload["cwd"] || Dir.pwd
source = payload["source"]

if opts[:host].nil? || opts[:scope_mode].nil?
  warn "REFUSED MISSING_TRUSTED_AUTHORITY_INPUT（installer 應以命令列參數提供 --host 與 --runtime-scope-mode）"
  exit 1
end
if session_id.nil? || session_id.to_s.strip.empty?
  warn "REFUSED MISSING_HOST_SESSION_ID（stdin 未提供 session_id；hook_event_name=#{payload["hook_event_name"].inspect}）"
  exit 1
end

begin
  binding_out = OMOS::SessionStart.produce(
    host: opts[:host],
    native_session_id: session_id,
    cwd: cwd,
    project_ref: OMOS::SessionStart.project_ref_for(cwd),
    runtime_scope_mode: opts[:scope_mode]
  )
rescue OMOS::SessionStart::Refused => e
  warn "REFUSED #{e.code}"
  exit 1
end

# 落地可信事實，供 MCP server 讀回；模型不經手。
OMOS::SessionState.record!(host: opts[:host], session_id: session_id, cwd: cwd, source: source)

puts JSON.generate({ "hookSpecificOutput" => {
                       "hookEventName" => payload["hook_event_name"] || "SessionStart",
                       "additionalContext" =>
                         "omos-personal-memory 已綁定此 session（effective_scope=" \
                         "#{binding_out["effective_scope"]}）。寫入一律經 Runtime 治理層。"
                     } })
