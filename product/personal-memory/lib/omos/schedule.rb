# frozen_string_literal: true
#
# Friday trigger（Slice B2）。用 macOS **原生 launchd**，不新建 daemon／runtime。
#
# ## 這支能做什麼、不能做什麼
#
# 能做的只有兩件：把 queue 算出來、提醒人。**不能**做 acceptance、Record、
# Promotion、Company upload 或 terminal closeout——契約（weekly_review_cycle）
# 把 acceptance authority 封死在每個 Candidate 自己的 verification／
# acceptance gate 上，批次確認本身不能接受任何東西。
#
# 「週五有跑 job」**不等於**「這週 review 已完成」。完成仍以既有 closeout
# contract 的 terminal receipt 為準，而那是人做的決定。
#
# ## 逾期不等於 SKIPPED
#
# 超過 catch-up deadline 只呈現「逾期」，**不得**自動判成 SKIPPED。
# SKIPPED 是終局且明確的處置，契約明寫在 catch-up deadline 之前宣告會被直接
# 拒絕；而「deadline 過了」也只是說沒人來做，不是有人決定跳過。
#
# ## repair-01：三個實際行為缺口
#
# 1. **真的管理 launchd job**。原本 install 只寫 plist、remove 只刪 plist，
#    程式裡沒有任何 launchctl，CLI 還印一行叫使用者自己跑 `launchctl load`。
#    那不是「排程已安裝」，那是「檔案已放好」——status 看到檔案就報成功，
#    會把「plist 在、job 沒載入」當成健康。
# 2. **anchor 必須完整傳遞**。plist 可以裝成 15:00，但它啟動的仍是沒有帶
#    anchor 的 `review due`，status 也固定用預設 16:00——於是 15:00 的排程在
#    週五 15:00 被叫醒時，trigger 認為是 W38、status 卻算成 W37。
#    設定能力要嘛完整，要嘛不要有；半套的設定比沒有設定更危險。
# 3. **ownership 要看 plist 裡的 Label，不是檔名**。檔名是誰都能取的；
#    同名但 Label 是別人的 plist 被我們刪掉，就是誤刪第三方。

require "fileutils"
require "json"
require "time"
require "open3"
require_relative "review_queue"
require_relative "runtime"

module OMOS
  module Schedule
    class Failed < StandardError
      attr_reader :code

      def initialize(code, detail = nil)
        @code = code
        super(detail.nil? ? code : "#{code}: #{detail}")
      end
    end

    LABEL = "com.omos.personal-memory.weekly-review"
    FRIDAY_WEEKDAY = 5   # launchd: 0=Sunday

    module_function

    def agents_dir(home) = File.join(home, "Library/LaunchAgents")
    def plist_path(home) = File.join(agents_dir(home), "#{LABEL}.plist")
    def launcher_path(home) = File.join(home, ".omos/personal-memory/current/exe/omos-personal-memory")
    def domain = "gui/#{Process.uid}"

    # 真正呼叫 launchctl 的預設實作。測試注入替身，**不得**在 conformance 裡
    # 把 job 載進使用者真正的 session——那是會留在機器上的外部副作用。
    def launchctl(*args)
      out, err, st = Open3.capture3("/bin/launchctl", *args)
      { ok: st.success?, status: st.exitstatus, out: out, err: err }
    end

    # ---- ownership ----------------------------------------------------
    #
    # repair-01 P1-3：檔名任何人都能取。只有 plist **內部的 Label** 能證明
    # 這支 job 是我們的。解析失敗一律視為「不是我們的」——看不懂的東西不刪。
    def plist_label(path, plutil: method(:plutil_json))
      return nil unless File.file?(path)

      doc = plutil.call(path)
      doc.is_a?(Hash) ? doc["Label"] : nil
    end

    def plutil_json(path)
      out, _, st = Open3.capture3("/usr/bin/plutil", "-convert", "json", "-o", "-", path)
      st.success? ? JSON.parse(out) : nil
    rescue JSON::ParserError
      nil
    end

    def own?(path, plutil: method(:plutil_json))
      plist_label(path, plutil: plutil) == LABEL
    end

    # ---- 生命週期 ------------------------------------------------------

    # 依已簽署契約（CARD-LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922）
    # 實作的階段序列：
    #
    #   SNAPSHOT_OLD → OLD_STOP_VERIFIED → PUBLISH_NEW_PLIST
    #     → NEW_ACTIVATION_ATTEMPTED → NEW_POSTCONDITION_CLASSIFIED
    #     → CLEANUP_NEW_IF_NEEDED → RESTORE_OLD_IF_NEEDED → FINAL_VERIFIED
    #
    # 這是**流程階段**，不是資料結構：沒有 FSM engine、沒有 ledger、沒有 DB，
    # 狀態只活在這一次呼叫的區域變數裡。
    #
    # 兩個順序被契約凍死，不得改：
    #
    #   §1.3.3 OLD_STOP_VERIFIED **之前磁碟必須維持舊版**。先寫 plist 再停舊
    #          job（repair-01 起沿用至今的順序）會留下 disk=new／live=old。
    #   §1.3.2 rollback 時新 job 若仍 live，**第一步一定是清掉它**；清掉前不得
    #          換回舊 plist、不得 restore old，否則變成 disk=old／live=new。
    #
    # 兩者是同一個 split-brain 的兩個方向。
    def install(home:, anchor_hour: ReviewQueue::DEFAULT_ANCHOR_HOUR,
                launchctl: method(:launchctl), plutil: method(:plutil_json))
      unless (0..23).cover?(anchor_hour.to_i)
        raise Failed.new("SCHEDULE_ANCHOR_HOUR_INVALID", anchor_hour.inspect)
      end

      path = plist_path(home)
      # ownership 先驗：我們路徑上若躺著別人的 plist，無論本地安裝是否完整都
      # 不能覆寫它。排在 launcher 檢查之後的話，未安裝完的環境會先收到
      # LAUNCHER_MISSING，掩蓋掉「那裡有別人的東西」這個更該先講的事實。
      existing = File.file?(path)
      if existing && !own?(path, plutil: plutil)
        raise Failed.new("SCHEDULE_FOREIGN_PLIST_AT_OUR_PATH", path)
      end

      launcher = launcher_path(home)
      raise Failed.new("SCHEDULE_LAUNCHER_MISSING", launcher) unless File.exist?(launcher)

      with_lifecycle_lock(home) do
        FileUtils.mkdir_p(agents_dir(home))

        # ── SNAPSHOT_OLD ────────────────────────────────────────────────
        # 必須在停舊 job **之前**：停掉之後才想留位元組就來不及了。
        old = { bytes: existing ? File.binread(path) : nil,
                loaded: loaded?(launchctl: launchctl) }

        # ── OLD_STOP_VERIFIED ───────────────────────────────────────────
        # 舊 job 停不掉就**不得**發布新 plist：磁碟維持舊版、與 live 的舊 job
        # 一致，這是乾淨的失敗。
        if old[:loaded]
          out = bootout_and_verify(launchctl)
          raise Failed.new("SCHEDULE_LAUNCHCTL_BOOTOUT_FAILED", out[:detail]) unless out[:ok]
        end

        # ── PUBLISH_NEW_PLIST ───────────────────────────────────────────
        write_atomic(path, plist(home, anchor_hour.to_i))

        # ── NEW_ACTIVATION_ATTEMPTED ／ NEW_POSTCONDITION_CLASSIFIED ────
        verdict = bootstrap_and_verify(path, launchctl)
        if verdict[:ok]
          # ── FINAL_VERIFIED ──
          next { label: LABEL, plist: path, replaced: existing,
                 anchor_hour: anchor_hour.to_i, loaded: true }
        end

        # ── CLEANUP_NEW_IF_NEEDED ───────────────────────────────────────
        # partial activation（§1.1 第四象限）：bootstrap 回非零但 job 其實已
        # 活起來。**必須先清掉新 job**，而且在清掉之前磁碟不准動——否則就是
        # disk=old／live=new。
        if verdict[:partial] || loaded?(launchctl: launchctl)
          cleanup = bootout_and_verify(launchctl)
          unless cleanup[:ok]
            # 清不掉 → dirty failure。磁碟**保留新版**，與仍在跑的新 job 對應。
            # 寧可停在「升級沒完成但一致」，也不製造 split-brain。
            raise Failed.new("SCHEDULE_PARTIAL_ACTIVATION_NOT_CLEANED",
                             "#{verdict[:detail]}；新 job 仍在載入中且清除失敗" \
                             "（#{cleanup[:detail]}）。磁碟保留新版以與 live job 一致，" \
                             "請手動處理 #{domain}/#{LABEL}")
          end
        end

        # ── RESTORE_OLD_IF_NEEDED ───────────────────────────────────────
        unless restore_old(path, old, launchctl)
          raise Failed.new("SCHEDULE_INSTALL_FAILED_AND_NOT_RESTORED",
                           "#{verdict[:detail]}；舊 plist／loaded 狀態未能完整還原，" \
                           "請手動檢查 #{path}")
        end

        raise Failed.new("SCHEDULE_LAUNCHCTL_BOOTSTRAP_FAILED", verdict[:detail])
      end
    end

    # 只移除本產品自己的 job：先確認 plist 內部 Label，再 bootout ＋ 刪檔。
    def remove(home:, launchctl: method(:launchctl), plutil: method(:plutil_json))
      path = plist_path(home)
      return { label: LABEL, removed: false, reason: "NOT_INSTALLED" } unless File.file?(path)
      unless own?(path, plutil: plutil)
        return { label: LABEL, removed: false, reason: "NOT_OURS",
                 found_label: plist_label(path, plutil: plutil) }
      end

      # repair-02：原本忽略 bootout 成敗就刪 plist——bootout 失敗時 job 仍然
      # loaded，而管理它的檔案已經不見了，留下一個誰都管不到的孤兒 job。
      # 卸載一個還在跑的東西，必須先真的把它停掉。
      with_lifecycle_lock(home) do
        if loaded?(launchctl: launchctl)
          out = bootout_and_verify(launchctl)
          unless out[:ok]
            raise Failed.new("SCHEDULE_BOOTOUT_FAILED", "#{out[:detail]}；plist 保留於 #{path}")
          end
        end

        FileUtils.rm_f(path)
        { label: LABEL, removed: true, loaded: false }
      end
    end

    # 還原舊狀態。呼叫此函式的前提（由 install 的階段序列保證）是：
    # **新 job 已經確認不在跑了**——CLEANUP_NEW_IF_NEEDED 已經走完。
    #
    # 契約 §1.3 明文禁止用 `loaded?` 判斷「現在活著的是舊的還是新的」：它只
    # 回答「這個 Label 有沒有東西在跑」，在 partial activation 下會把新 job
    # 誤認成舊 job。repair-04 就是踩在這裡。所以這裡**完全不問**現在活著的是
    # 誰，只依 SNAPSHOT_OLD 記下來的事實動作。
    def restore_old(path, old, launchctl)
      if old[:bytes].nil?
        FileUtils.rm_f(path)
      else
        write_atomic(path, old[:bytes])
      end

      return true unless old[:loaded]

      # 這裡接受 partial：磁碟上**已經**是舊版位元組（上面剛寫回），所以此刻
      # 若 job 是 live 的，它只可能是舊設定——這是由階段序列推得的事實，
      # 不是用 `loaded?` 去猜「活著的是舊的還是新的」。
      #
      # 契約 §1.1 的 partial 處理（先清掉再恢復）針對的是**新** activation；
      # 還原自己的 bootstrap 若 exit 非 0 但 job 已起來，最終狀態正是我們要的
      # disk=old／live=old，判成失敗反而會讓使用者以為舊排程沒回來。
      verdict = bootstrap_and_verify(path, launchctl)
      verdict[:ok] || verdict[:partial] == true
    rescue StandardError
      false
    end

    # 同一個 launchd Label 的 lifecycle mutation 必須序列化（契約 §1.4）。
    #
    # 交易狀態只活在單次呼叫內，兩個 process 同時跑 install／remove 時，彼此
    # 都可能拿到過期的 SNAPSHOT_OLD——第二個 process 可以直接把這套狀態機打穿。
    # 用作業系統既有的 flock 就夠，**不新建 daemon 或 broker**。
    #
    # 拿不到序列權一律當場失敗：排隊等到逾時再半套執行，比直接失敗更難查。
    def with_lifecycle_lock(home)
      # 鎖放在**我們自己的**狀態目錄，不放 ~/Library/LaunchAgents——那個目錄
      # 屬於 launchd，往裡面丟一個 dotfile 鎖既髒又會被我們自己的
      # 「只認自己那一支 plist」邏輯數進去。
      FileUtils.mkdir_p(File.dirname(lock_path(home)))
      File.open(lock_path(home), File::CREAT | File::RDWR, 0o644) do |lock|
        unless lock.flock(File::LOCK_EX | File::LOCK_NB)
          raise Failed.new("SCHEDULE_LIFECYCLE_BUSY",
                           "另一個 #{LABEL} 的 install／remove 正在進行中")
        end

        begin
          yield
        ensure
          lock.flock(File::LOCK_UN)
        end
      end
    end

    def lock_path(home) = File.join(home, ".omos/personal-memory/#{LABEL}.lifecycle.lock")

    # **唯一**的 bootout 入口。install／rollback／remove 都走這裡。
    # 契約 §1.2 的**四象限**，與 bootstrap 對稱：
    #
    #   exit 0   ＋ not loaded    → 成功
    #   exit 0   ＋ loaded        → 假成功
    #   exit 非0 ＋ loaded        → clean failure
    #   exit 非0 ＋ **not loaded** → **其實已經停了**，視為成功。原本會誤判成
    #                               失敗——job 本來就沒載入時 launchctl 回非零，
    #                               那不是錯誤。
    #
    # 判準一律是**實際狀態**，exit code 只是輔助訊息。
    def bootout_and_verify(launchctl)
      res = launchctl.call("bootout", "#{domain}/#{LABEL}")
      return { ok: true, detail: nil } unless loaded?(launchctl: launchctl)

      if res[:ok]
        return { ok: false,
                 detail: "launchctl bootout 回報成功（exit=#{res[:status]}），" \
                         "但 #{domain}/#{LABEL} 仍在載入中" }
      end

      { ok: false,
        detail: "exit=#{res[:status]} #{res[:err].to_s.strip[0, 120]}；" \
                "#{domain}/#{LABEL} 仍在載入中" }
    end

    # **唯一**的 bootstrap 入口。install 與 rollback 都走這裡。
    # 契約 §1.1 的**四象限**，一個都不能少：
    #
    #   exit 0   ＋ loaded      → 成功
    #   exit 0   ＋ not loaded  → 假成功
    #   exit 非0 ＋ not loaded  → clean failure
    #   exit 非0 ＋ **loaded**  → **partial activation**：命令說失敗，job 卻
    #                             活起來了。這一象限原本完全沒處理，於是
    #                             「失敗」路徑會留下一個沒人管的新 job。
    #
    # partial 由 :partial 標出來，讓呼叫端知道**必須先清掉新 job**才能往下走。
    def bootstrap_and_verify(path, launchctl)
      res = launchctl.call("bootstrap", domain, path)
      now_loaded = loaded?(launchctl: launchctl)

      if res[:ok]
        return { ok: true, partial: false, detail: nil } if now_loaded

        return { ok: false, partial: false,
                 detail: "launchctl bootstrap 回報成功（exit=#{res[:status]}），" \
                         "但 #{domain}/#{LABEL} 實際未載入" }
      end

      if now_loaded
        return { ok: false, partial: true,
                 detail: "launchctl bootstrap 回報失敗（exit=#{res[:status]} " \
                         "#{res[:err].to_s.strip[0, 80]}），但 #{domain}/#{LABEL} " \
                         "實際已載入（partial activation）" }
      end

      { ok: false, partial: false,
        detail: "exit=#{res[:status]} #{res[:err].to_s.strip[0, 120]}" }
    end

    # job 是否**真的載入**，不是「檔案在不在」。
    def loaded?(launchctl: method(:launchctl))
      launchctl.call("print", "#{domain}/#{LABEL}")[:ok] == true
    end

    def status(home:, now: Time.now, runtime: nil, surface: Runtime::SURFACES[:cli],
               launchctl: method(:launchctl), plutil: method(:plutil_json))
      path = plist_path(home)
      present = File.file?(path)
      ours = present && own?(path, plutil: plutil)
      # repair-01 P1-2：anchor 從**已安裝的 plist** 讀回來，不用預設值猜。
      # 猜的話 15:00 的排程會被 status 當成 16:00，算出上一期的 period。
      hour = ours ? installed_anchor_hour(path, plutil: plutil) : nil
      effective = hour || ReviewQueue::DEFAULT_ANCHOR_HOUR
      period = ReviewQueue.period_for(now, anchor_hour: effective)
      loaded = loaded?(launchctl: launchctl)

      base = { label: LABEL, plist_present: present, plist_is_ours: ours,
               # 「已安裝」= plist 是我們的 **且** job 真的載入了。
               installed: ours && loaded, loaded: loaded,
               anchor_hour: hour, effective_anchor_hour: effective,
               plist: path, period: period[:id],
               scheduled_anchor_at: period[:scheduled_anchor_at],
               catch_up_deadline_at: period[:catch_up_deadline_at],
               # 逾期只是狀態，**不是** SKIPPED。terminal disposition 仍是人的
               # closeout——這一行是本檔最容易被「順手自動化」的地方。
               overdue: now >= Time.parse(period[:catch_up_deadline_at]) }
      return base if runtime.nil?

      q = ReviewQueue.due(runtime, now: now, anchor_hour: effective, surface: surface)
      base.merge(due_count: q[:items].size, terminal_closeout: q[:terminal_closeout])
    end

    # 已安裝 plist 宣告的 anchor 小時。兩個來源必須一致：
    # StartCalendarInterval 的 Hour，與傳給 `review due` 的 --anchor-hour。
    # 不一致代表 plist 被手改過，寧可回 nil 讓上層退回預設並顯示，不猜。
    def installed_anchor_hour(path, plutil: method(:plutil_json))
      doc = plutil.call(path)
      return nil unless doc.is_a?(Hash)

      from_calendar = doc.dig("StartCalendarInterval", "Hour")
      args = doc["ProgramArguments"]
      i = args.is_a?(Array) ? args.index("--anchor-hour") : nil
      from_args = i && args[i + 1] && Integer(args[i + 1], exception: false)
      from_calendar == from_args ? from_calendar : nil
    end

    # ---- 提醒 ----------------------------------------------------------
    #
    # **通知失敗不得影響 queue correctness**——排程與 queue 是 authoritative
    # behavior，notification 只是 presentation。但也**不得完全靜默**：失敗寫
    # stderr，並由 schedule status 呈現。
    #
    # 失敗只在**一個地方**回報。原本例外與「回非零」各印一次，於是拿掉其中
    # 一處另一處照印——保護看起來還在，其實已經少了一半。
    def notify(count, io: $stderr, runner: method(:osascript))
      return { notified: false, reason: "NO_DUE_ITEMS" } if count.to_i.zero?

      message = "Personal Memory：本週有 #{count} 筆待 review"
      reason = nil
      ok = begin
        runner.call(message) == true
      rescue StandardError => e
        reason = "#{e.class}: #{e.message}"
        false
      end
      unless ok
        reason ||= "osascript 回非零"
        io&.puts "[omos-personal-memory] 通知失敗（不影響 queue）：#{reason}"
      end

      { notified: ok, message: message, reason: reason }
    end

    def osascript(message)
      system("/usr/bin/osascript", "-e",
             %(display notification #{message.inspect} with title "omos-personal-memory"),
             out: File::NULL, err: File::NULL)
    end

    # ---- plist ---------------------------------------------------------

    def write_atomic(path, body)
      tmp = "#{path}.writing-#{Process.pid}"
      File.binwrite(tmp, body)
      File.rename(tmp, path)
    rescue StandardError
      FileUtils.rm_f(tmp)
      raise
    end

    def plist(home, anchor_hour)
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key><string>#{LABEL}</string>
          <key>ProgramArguments</key>
          <array>
            <string>#{launcher_path(home)}</string>
            <string>review</string>
            <string>due</string>
            <string>--notify</string>
            <string>--anchor-hour</string>
            <string>#{anchor_hour}</string>
          </array>
          <key>StartCalendarInterval</key>
          <dict>
            <key>Weekday</key><integer>#{FRIDAY_WEEKDAY}</integer>
            <key>Hour</key><integer>#{anchor_hour}</integer>
            <key>Minute</key><integer>0</integer>
          </dict>
          <key>RunAtLoad</key><true/>
          <key>StandardErrorPath</key><string>#{File.join(home, ".omos/personal-memory/schedule.log")}</string>
          <key>StandardOutPath</key><string>#{File.join(home, ".omos/personal-memory/schedule.log")}</string>
        </dict>
        </plist>
      XML
    end
  end
end
