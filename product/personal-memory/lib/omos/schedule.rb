# frozen_string_literal: true
#
# Friday trigger（Slice B2）。用 macOS **原生 launchd**，不新建 daemon／runtime。
#
# ## 這支能做什麼、不能做什麼
#
# 能做的只有兩件：把 queue 算出來、提醒人。**不能**做 acceptance、Record、
# Promotion、Company upload 或 terminal closeout——契約
# （weekly_review_cycle）把 acceptance authority 封死在每個 Candidate 自己的
# verification／acceptance gate 上，批次確認本身不能接受任何東西。
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
# ## 為什麼 LaunchAgent 呼叫的是 current 而不是 versioned path
#
# 與 Host hook 同一個理由（Q7 §0.1）：綁 artifact-id 的話，升級後這支 job 會
# 繼續叫一個已經被 GC 掉的版本。一律走穩定的
# `~/.omos/personal-memory/current/...`。

require "fileutils"
require "time"
require_relative "runtime"
require_relative "review_queue"

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

    # 只認自己那一支。`~/Library/LaunchAgents/` 裡通常已經有別人的 plist，
    # 與 Host hook 是同一類 collision 風險：**不得**用前綴或「看起來像 OMOS」
    # 去猜，只認完全相等的 Label。
    def own?(path) = File.basename(path) == "#{LABEL}.plist"

    def install(home:, anchor_hour: ReviewQueue::DEFAULT_ANCHOR_HOUR)
      launcher = launcher_path(home)
      raise Failed.new("SCHEDULE_LAUNCHER_MISSING", launcher) unless File.exist?(launcher)

      FileUtils.mkdir_p(agents_dir(home))
      body = plist(home, anchor_hour)
      path = plist_path(home)
      replaced = File.file?(path)

      # 與 receipt 同一個做法：temp + rename。被截斷的 plist 比沒有 plist 更糟
      # ——launchd 會拒載，而使用者只會發現「週五沒有提醒」。
      tmp = "#{path}.writing-#{Process.pid}"
      begin
        File.binwrite(tmp, body)
        File.rename(tmp, path)
      rescue StandardError
        FileUtils.rm_f(tmp)
        raise
      end

      { label: LABEL, plist: path, replaced: replaced, anchor_hour: anchor_hour }
    end

    # 只移除本產品自己的 job，其餘一律不碰。
    def remove(home:)
      path = plist_path(home)
      return { label: LABEL, removed: false } unless File.file?(path) && own?(path)

      FileUtils.rm_f(path)
      { label: LABEL, removed: true }
    end

    def status(home:, now: Time.now, runtime: nil, surface: Runtime::SURFACES[:cli])
      path = plist_path(home)
      period = ReviewQueue.period_for(now)
      overdue = now >= Time.parse(period[:catch_up_deadline_at])

      base = { label: LABEL, installed: File.file?(path), plist: path,
               period: period[:id],
               scheduled_anchor_at: period[:scheduled_anchor_at],
               catch_up_deadline_at: period[:catch_up_deadline_at],
               # 逾期只是狀態，**不是** SKIPPED。terminal disposition 仍是人的
               # closeout——這一行是本檔最容易被「順手自動化」的地方。
               overdue: overdue }
      return base if runtime.nil?

      q = ReviewQueue.due(runtime, now: now, surface: surface)
      base.merge(due_count: q[:items].size, terminal_closeout: q[:terminal_closeout])
    end

    # 提醒。**通知失敗不得影響 queue correctness**——排程與 queue 是
    # authoritative behavior，notification 只是 presentation。
    #
    # 但也**不得完全靜默**（Owner 裁決）：失敗寫 stderr，並由 schedule status
    # 呈現。刻意不為 notification 另開 ledger，也不塞進 operation_journal
    # ——那份目前是 Store operation evidence，擴它的 kind 會碰既有 runtime
    # contract。
    def notify(count, io: $stderr, runner: method(:osascript))
      return { notified: false, reason: "NO_DUE_ITEMS" } if count.to_i.zero?

      # 失敗只在**一個地方**回報。原本例外與「回非零」各印一次，於是拿掉其中
      # 一處另一處照印——保護看起來還在，其實已經少了一半。失敗原因帶在
      # reason 裡，由這一處統一輸出。
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
