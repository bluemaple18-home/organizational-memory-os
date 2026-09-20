# frozen_string_literal: true
#
# SessionStart hook 與 MCP server 之間的 session 事實交接。
#
# 為什麼需要它（review P1-C）：原本 host_session_binding 是 MCP tool 的參數，
# 模型可以自己組一份形狀合法的 binding 再呼叫工具——那與契約宣告的
# 「native session 是 authority」矛盾。而 SessionStart 的 stdout 在兩個 Host
# 都只是送進模型 context，不能當成可信通道。
#
# repair-02（P1-1）：**cwd 不是 session identity。** 同一個 repo 同時開多個
# Codex task / Claude session 是正常情境；以 cwd 為鍵會讓後者覆蓋前者，
# 舊 session 與並行 session 都可能取得錯的 identity（reviewer 已實測重播）。
# 加 TTL 也解決不了——TTL 無法區分同 cwd 的兩個同時存在的 session。
#
# 因此鍵改為 (host, native_session_id)。MCP server 必須能**獨立**得知自己的
# native session id（見規格 native_session_id_source），取不到就 fail closed。

require "json"
require "digest"
require "fileutils"
require "time"

module OMOS
  module SessionState
    DEFAULT_DIR = "~/.omos/personal-memory/sessions"

    module_function

    def dir(home: Dir.home)
      ENV["OMOS_SESSION_STATE_DIR"] || DEFAULT_DIR.sub(%r{\A~(?=/)}, home)
    end

    def canonical(cwd)
      File.realpath(File.expand_path(cwd))
    rescue Errno::ENOENT
      File.expand_path(cwd)
    end

    # 鍵 = (host, native_session_id)。同一 cwd 的多個並行 session 各有自己的檔案，
    # 不會互相覆蓋。
    def path_for(host, session_id, home: Dir.home)
      slug = Digest::SHA256.hexdigest("#{host}\u0000#{session_id}")
      File.join(dir(home: home), "#{slug}.json")
    end

    def record!(host:, session_id:, cwd:, source: nil, home: Dir.home)
      path = path_for(host, session_id, home: home)
      FileUtils.mkdir_p(File.dirname(path))
      data = { "host" => host, "session_id" => session_id, "cwd" => canonical(cwd),
               "source" => source, "recorded_at" => Time.now.utc.iso8601 }
      File.write(path, "#{JSON.pretty_generate(data)}\n")
      data
    end

    def read(host, session_id, home: Dir.home)
      path = path_for(host, session_id, home: home)
      return nil unless File.exist?(path)

      record = JSON.parse(File.read(path, encoding: "UTF-8"))
      # 防重放：檔名由 (host, session_id) 推導，內容也必須自洽。
      return nil unless record["host"] == host && record["session_id"] == session_id

      record
    end
  end
end
