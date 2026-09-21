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

    def install(home:, anchor_hour: ReviewQueue::DEFAULT_ANCHOR_HOUR,
                launchctl: method(:launchctl), plutil: method(:plutil_json))
      unless (0..23).cover?(anchor_hour.to_i)
        raise Failed.new("SCHEDULE_ANCHOR_HOUR_INVALID", anchor_hour.inspect)
      end

      # ownership 先驗：我們路徑上若躺著別人的 plist，無論本地安裝是否完整都
      # 不能覆寫它。把這條排在 launcher 檢查之後的話，一個還沒安裝完的環境會
      # 先收到 LAUNCHER_MISSING，掩蓋掉「那裡有別人的東西」這個更該先講的事實。
      path = plist_path(home)
      existing = File.file?(path)
      if existing && !own?(path, plutil: plutil)
        raise Failed.new("SCHEDULE_FOREIGN_PLIST_AT_OUR_PATH", path)
      end

      launcher = launcher_path(home)
      raise Failed.new("SCHEDULE_LAUNCHER_MISSING", launcher) unless File.exist?(launcher)

      # install 是一筆交易（repair-02）。
      #
      # 原本先覆寫 plist、再 bootout、最後 bootstrap，bootstrap 失敗時什麼都
      # 不還原——於是一次失敗的升級會把**原本正常運作的排程**打壞：新 plist
      # 留著、舊 job 已被 bootout、anchor 變成新版的。使用者下週五不會收到
      # 提醒，而現場看起來「檔案都在」。
      #
      # 所以先把舊狀態完整存下來（plist 位元組 ＋ 是否真的載入），失敗就整組
      # 還原：plist 位元組相同地寫回，原本有載入的就重新 bootstrap 回去。
      FileUtils.mkdir_p(agents_dir(home))
      previous_bytes = existing ? File.binread(path) : nil
      previous_loaded = loaded?(launchctl: launchctl)

      write_atomic(path, plist(home, anchor_hour.to_i))
      begin
        # 重裝要先 bootout 再 bootstrap，否則 launchd 會拒收同一個 Label。
        # 這裡的 bootout 失敗不是錯誤——本來就可能沒載入過。
        launchctl.call("bootout", "#{domain}/#{LABEL}") if previous_loaded
        res = launchctl.call("bootstrap", domain, path)
        unless res[:ok]
          raise Failed.new("SCHEDULE_LAUNCHCTL_BOOTSTRAP_FAILED",
                           "exit=#{res[:status]} #{res[:err].to_s.strip[0, 120]}")
        end
      rescue StandardError => e
        restored = restore_previous(path, previous_bytes, previous_loaded, launchctl)
        raise e if restored

        # 還原也失敗：**不得**假裝升級只是沒成功。這種狀態必須自己講出來，
        # 否則使用者會以為舊排程還在。
        raise Failed.new("SCHEDULE_INSTALL_FAILED_AND_NOT_RESTORED",
                         "#{e.message}；舊 plist／loaded 狀態未能完整還原，請手動檢查 #{path}")
      end

      { label: LABEL, plist: path, replaced: existing, anchor_hour: anchor_hour.to_i,
        loaded: loaded?(launchctl: launchctl) }
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
      if loaded?(launchctl: launchctl)
        res = launchctl.call("bootout", "#{domain}/#{LABEL}")
        if !res[:ok] || loaded?(launchctl: launchctl)
          raise Failed.new("SCHEDULE_BOOTOUT_FAILED",
                           "job 仍在載入中，plist 保留於 #{path}（exit=#{res[:status]} " \
                           "#{res[:err].to_s.strip[0, 120]}）")
        end
      end

      FileUtils.rm_f(path)
      { label: LABEL, removed: true, loaded: loaded?(launchctl: launchctl) }
    end

    # 把 plist 與載入狀態一起還原。任何一步失敗就回 false，讓呼叫端據實回報
    # ——「還原失敗」與「升級失敗」是兩種不同的現場，不能混為一談。
    def restore_previous(path, previous_bytes, previous_loaded, launchctl)
      if previous_bytes.nil?
        FileUtils.rm_f(path)
      else
        write_atomic(path, previous_bytes)
      end

      return true unless previous_loaded

      launchctl.call("bootout", "#{domain}/#{LABEL}")
      launchctl.call("bootstrap", domain, path)[:ok] == true
    rescue StandardError
      false
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
