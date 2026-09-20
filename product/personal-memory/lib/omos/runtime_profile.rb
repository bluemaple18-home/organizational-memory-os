# frozen_string_literal: true
#
# Runtime profile guard（Slice B）。
#
# 取代原本 `pinned-ruby.sh` 的 `RUBY_VERSION == "3.4.10"` 判準。Q6 Part 1 證明
# 版本字串既**過嚴**（拒絕 ABI 其實相容的 patch 升級）又**過鬆**（放行裝在別的
# 路徑、實際載不動我們 extension 的同版本 Ruby）。真正的約束是
# **native linkage 可解析 ＋ ABI 相容**。
#
# 本檔消費 Slice A 產生的兩份宣告，**不重新定義第二份**：
#   native-dependencies.json  production native dependency manifest
#   runtime-profile.json      已 qualification 的 runtime 組合
#
# 為什麼驗證放在開機路徑、而不是另外 spawn 探針：產品開機本來就會載入這些
# 原生擴充，另開一個 probe 進程等於把同樣的工作做兩次（每次 hook 觸發、
# 每次 MCP 啟動都要多付一次）。把 probe 併進開機，「真實載入」這件事就不是
# 模擬而是本來就會發生的事實。
#
# 「能跑」與「已 qualified」是**兩件事**（Q7 §0.3）：
#   probe 成功      → 這台機器載得動，可以繼續跑
#   profile 未列入  → 我們沒承諾支援這個組合；必須是**明確可辨識的狀態**，
#                     不得靜默放行，但也不該因此拒絕一個能跑的環境

require "json"
require "digest"
require "rbconfig"

module OMOS
  module RuntimeProfile
    class Unsupported < StandardError
      attr_reader :code, :detail

      def initialize(code, detail)
        @code = code
        @detail = detail
        super("#{code}: #{detail}")
      end
    end

    ARTIFACT_ROOT = File.expand_path("../..", __dir__)
    MANIFEST_PATH = File.join(ARTIFACT_ROOT, "native-dependencies.json")
    PROFILE_PATH = File.join(ARTIFACT_ROOT, "runtime-profile.json")

    QUALIFIED = "QUALIFIED"
    UNQUALIFIED = "UNQUALIFIED_RUNTIME_PROFILE"

    class << self
      def manifest
        @manifest ||= load_json(MANIFEST_PATH, "MANIFEST").fetch("production_native_dependencies")
      end

      def qualified_profiles
        @qualified_profiles ||= load_json(PROFILE_PATH, "PROFILE").fetch("qualified_profiles")
      end

      # 目前這個 runtime 的身分。刻意**不含版本字串**——ABI 目錄才是原生擴充
      # 的相容邊界（3.4 系列共用 "3.4.0"）。
      def current
        {
          "host_os" => RbConfig::CONFIG["host_os"],
          "host_cpu" => RbConfig::CONFIG["host_cpu"],
          "ruby_engine" => RUBY_ENGINE,
          "ruby_abi" => RbConfig::CONFIG["ruby_version"],
          "native_linkage_digest" => linkage_digest
        }
      end

      def linkage_digest
        pairs = manifest.map { |e| [e.fetch("extension"), e.fetch("non_system_libraries")] }.sort
        Digest::SHA256.hexdigest(JSON.generate(pairs))
      end

      # 實際選中的 Ruby。診斷時要能回答「到底是哪一支跑起來的」。
      def ruby_executable = RbConfig.ruby

      # 四項檢查。任何一項不過即 fail closed，並指出**實際缺的是什麼**，
      # 不是只說「版本不符」。
      #
      # 回傳 QUALIFIED 或 UNQUALIFIED_RUNTIME_PROFILE——後者代表載得動但不在
      # 承諾支援的清單裡，呼叫端必須讓它可被看見。
      def verify!
        manifest.each do |entry|
          name = entry.fetch("require")
          extension = entry.fetch("extension")

          # (1) 真實 load probe：用 manifest 宣告的 require 名稱去載。
          #     這裡**必須**用 entry 的 require，不能改用「掃已載入的東西」
          #     ——那樣拼錯的 require 會被其他已載入的證據掩蓋。
          begin
            require name
          rescue LoadError => e
            raise Unsupported.new("OMOS_NATIVE_REQUIRE_FAILED",
                                  "manifest 宣告的 require #{name.inspect}（#{extension}）載入失敗：#{e.message}")
          end

          # (2) 解析到的必須真的是這個 artifact 內、且是宣告的那個 extension
          loaded = loaded_extension_path(extension)
          if loaded.nil?
            raise Unsupported.new("OMOS_NATIVE_EXTENSION_NOT_RESOLVED",
                                  "require #{name.inspect} 成功，但沒有解析到本 artifact 內的 #{extension}")
          end

          # (3) 宣告的非系統相依必須真的解析得到
          missing = entry.fetch("non_system_libraries").reject { |lib| File.exist?(lib) }
          next if missing.empty?

          raise Unsupported.new("OMOS_NATIVE_DEPENDENCY_UNRESOLVED",
                                "#{extension} 需要的函式庫在本機不存在：#{missing.join(", ")}")
        end

        # (4) qualification 比對——與「能不能跑」分開。
        qualified_profiles.include?(current) ? QUALIFIED : UNQUALIFIED
      end

      # 入口用的包裝：fail closed 時印出**實際缺什麼**再以非零退出；
      # 能跑但未 qualified 時不擋，但必須讓它看得見（stderr ＋ 環境變數，
      # doctor 會把它呈現出來）。靜默放行是不被允許的。
      def assert_supported!(io: $stderr)
        status = verify!
        if status == UNQUALIFIED
          ENV["OMOS_RUNTIME_PROFILE_STATUS"] = UNQUALIFIED
          io.puts("[omos-personal-memory] #{UNQUALIFIED}：此 runtime 組合載得動但不在已" \
                  "qualification 的清單內（#{current["host_os"]}/#{current["host_cpu"]} " \
                  "#{current["ruby_engine"]} ABI #{current["ruby_abi"]}）。" \
                  "能執行不等於我們承諾支援。")
        else
          ENV["OMOS_RUNTIME_PROFILE_STATUS"] = QUALIFIED
        end
        status
      rescue Unsupported => e
        io.puts("[omos-personal-memory] #{e.code}")
        io.puts("  #{e.detail}")
        io.puts("  選用的 Ruby：#{ruby_executable}")
        exit 78
      end

      private

      # 比對前兩側都要 realpath。這正是 Q7 §1.2 記載的不對稱：透過
      # `current/exe/...` 啟動時，$LOADED_FEATURES 記的是 current/ 底下的路徑，
      # 而本檔的 __dir__ 已經被解析成 versions/<id>/。只比字串前綴會誤判成
      # 「沒有解析到本 artifact 內的 extension」。
      def loaded_extension_path(extension)
        root = "#{File.realpath(ARTIFACT_ROOT)}/"
        $LOADED_FEATURES.find do |f|
          next false unless f.end_with?(".bundle") && File.basename(f, ".bundle") == extension
          next false unless File.exist?(f)

          File.realpath(f).start_with?(root)
        end
      end

      def load_json(path, what)
        raise Unsupported.new("OMOS_RUNTIME_#{what}_MISSING", "找不到 #{path}") unless File.file?(path)

        JSON.parse(File.read(path, encoding: "UTF-8"))
      rescue JSON::ParserError => e
        raise Unsupported.new("OMOS_RUNTIME_#{what}_UNREADABLE", "#{path}：#{e.message}")
      end
    end
  end
end
