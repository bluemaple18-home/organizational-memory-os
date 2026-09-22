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

      def profile_document
        @profile_document ||= load_json(PROFILE_PATH, "PROFILE")
      end

      def qualified_profiles
        @qualified_profiles ||= profile_document.fetch("qualified_profiles")
      end

      # qualification 的比對 key。刻意**不含任何版本字串**——ABI 目錄才是原生
      # 擴充的相容邊界（3.4 系列共用 "3.4.0"），OS 的 build 版本不是。
      #
      # 為什麼 host_os 不在這裡（Owner 裁決 2026-09-21）：`RbConfig` 的
      # `host_os` 是**編這顆 Ruby 的那台機器**的 darwin build 版本，Homebrew
      # 每個 macOS 版本各出一份 bottle，於是它會隨使用者而異（實測：本機
      # darwin25、同事機 darwin24，同一包 artifact、probe 都過）。把它放進
      # 比對，等於「一個 macOS build 一列」，永遠列不完；而它與「我們的原生
      # 擴充載不載得動」沒有因果關係。這正是 Q6 Part 1 否掉的那個錯——
      # 用版本字串當判準——只是高了一層。
      #
      # `native_linkage_digest` 同樣不在這裡：它由 artifact 自己的 manifest
      # 算出，對同一包 artifact 在任何機器上恆為同值，**零機器鑑別力**。
      # 它改去驗 artifact integrity，見 assert_artifact_integrity!。
      def qualification_key
        {
          "os_family" => os_family,
          "host_cpu" => RbConfig::CONFIG["host_cpu"],
          "ruby_engine" => RUBY_ENGINE,
          "ruby_abi" => RbConfig::CONFIG["ruby_version"]
        }
      end

      # 記錄下來但**不參與判定**的觀測值。診斷、回報與日後要重新檢視判準時
      # 需要它們；參與判定的話就會變回逐版本矩陣。
      def observation
        {
          "host_os" => RbConfig::CONFIG["host_os"],
          "native_linkage_digest" => linkage_digest
        }
      end

      # `darwin25` → `darwin`。只取前導字母，不做版本比較——一旦開始比較
      # 版本大小，就又回到版本字串判準了。
      def os_family
        RbConfig::CONFIG["host_os"][/\A[A-Za-z]+/] || RbConfig::CONFIG["host_os"]
      end

      def linkage_digest
        pairs = manifest.map { |e| [e.fetch("extension"), e.fetch("non_system_libraries")] }.sort
        Digest::SHA256.hexdigest(JSON.generate(pairs))
      end

      # artifact integrity：manifest 是否仍是當初被 qualification 的那一份。
      # 這**不是**機器判定——它在每台機器上的答案都一樣。不符代表 artifact
      # 被改過或打包錯了，屬於 fail closed。
      #
      # review P1-1：原本 `return if declared.nil?`，於是**把宣告整個刪掉就能
      # 關掉這道 guard**——實測回 PASSED_WITHOUT_DECLARATION。一道「刪掉就會
      # 消失」的保護不是保護。缺欄位、格式不對、digest 不符，三者一律 fail
      # closed；缺宣告甚至比不符更可疑，因為它連「當初被 qualification 的是
      # 哪一份」都答不出來。
      DIGEST_SHAPE = /\A[0-9a-f]{64}\z/

      def assert_artifact_integrity!
        declared = profile_document["artifact_native_linkage_digest"]

        if declared.nil?
          raise Unsupported.new("OMOS_ARTIFACT_LINKAGE_DIGEST_MISSING",
                                "runtime-profile.json 沒有宣告 artifact_native_linkage_digest；" \
                                "無法確認這份 artifact 是否就是當初被 qualification 的那一份")
        end

        unless declared.is_a?(String) && DIGEST_SHAPE.match?(declared)
          raise Unsupported.new("OMOS_ARTIFACT_LINKAGE_DIGEST_MALFORMED",
                                "artifact_native_linkage_digest 不是 64 位小寫十六進位字串" \
                                "（#{declared.inspect[0, 40]}）")
        end

        return if declared == linkage_digest

        raise Unsupported.new("OMOS_ARTIFACT_LINKAGE_DIGEST_MISMATCH",
                              "native-dependencies.json 與 runtime-profile.json 宣告的不符" \
                              "（宣告 #{declared[0, 12]}…／實際 #{linkage_digest[0, 12]}…）")
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

        # (4) artifact integrity——與機器無關，不符即 fail closed。
        assert_artifact_integrity!

        # (5) qualification 比對——與「能不能跑」分開。比的是 qualification_key，
        #     observation 不參與。
        qualified_profiles.include?(qualification_key) ? QUALIFIED : UNQUALIFIED
      end

      # 入口用的包裝：fail closed 時印出**實際缺什麼**再以非零退出；
      # 能跑但未 qualified 時不擋，但必須讓它看得見（stderr ＋ 環境變數，
      # doctor 會把它呈現出來）。靜默放行是不被允許的。
      def assert_supported!(io: $stderr)
        status = verify!
        if status == UNQUALIFIED
          ENV["OMOS_RUNTIME_PROFILE_STATUS"] = UNQUALIFIED
          k = qualification_key
          io.puts("[omos-personal-memory] #{UNQUALIFIED}：此 runtime 組合載得動但不在已" \
                  "qualification 的清單內（#{k["os_family"]}/#{k["host_cpu"]} " \
                  "#{k["ruby_engine"]} ABI #{k["ruby_abi"]}；" \
                  "觀測 host_os=#{observation["host_os"]}）。" \
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
