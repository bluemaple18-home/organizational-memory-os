# frozen_string_literal: true
#
# SessionStart hook 與 MCP server 之間的 session 事實交接。
#
# 為什麼需要它（review P1-C）：原本 host_session_binding 是 MCP tool 的參數，
# 模型可以自己組一份形狀合法的 binding 再呼叫工具——那與契約宣告的
# 「native session 是 authority」矛盾。而 SessionStart 的 stdout 在兩個 Host
# 都只是送進模型 context，不能當成可信通道。
#
# 因此改成：hook 把**Host 給它的原生事實**（session_id / cwd / source）落地成
# 檔案，MCP server 啟動時以自己的 cwd 去讀回來。模型既不經手也無法改寫，
# 讀不到就 fail closed。

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

    # 以 cwd 為鍵：同一個工作目錄同時只會有一個 Host session 在跑。
    # 必須用 realpath：macOS 的 /var 是 /private/var 的 symlink，hook 拿到的是
    # Host 給的路徑，MCP server 拿到的是 chdir 後的 Dir.pwd，兩者字面不同。
    def canonical(cwd)
      File.realpath(File.expand_path(cwd))
    rescue Errno::ENOENT
      File.expand_path(cwd)
    end

    def path_for(cwd, home: Dir.home)
      File.join(dir(home: home), "#{Digest::SHA256.hexdigest(canonical(cwd))}.json")
    end

    def record!(host:, session_id:, cwd:, source: nil, home: Dir.home)
      path = path_for(cwd, home: home)
      FileUtils.mkdir_p(File.dirname(path))
      data = { "host" => host, "session_id" => session_id, "cwd" => canonical(cwd),
               "source" => source, "recorded_at" => Time.now.utc.iso8601 }
      File.write(path, "#{JSON.pretty_generate(data)}\n")
      data
    end

    def read(cwd, home: Dir.home)
      path = path_for(cwd, home: home)
      return nil unless File.exist?(path)

      JSON.parse(File.read(path))
    end
  end
end
