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
    TRIGGER_LOG_PREFIX = "OMOS_SCHEDULE_TRIGGER "

    # 契約 §1.0：有界收斂。command 只呼叫一次，之後只輪詢 `launchctl print`。
    CONVERGENCE_WINDOW_SECONDS = 5.0
    POLL_INTERVAL_SECONDS = 0.1

    # `launchctl print` 對**明確不存在**的 service 回 113（實測 macOS 26）。
    # 其餘非零一律是 observation_error——例如壞 domain 回 64、別人的 uid 回 112。
    # 把它們壓成 not_loaded 會在 bootout 路徑上判定收斂成功、刪掉 plist，
    # 但 job 其實還活著（契約 §1.0.1 明文禁止）。
    PRINT_SERVICE_NOT_FOUND = 113

    module_function

    def agents_dir(home) = File.join(home, "Library/LaunchAgents")
    def plist_path(home) = File.join(agents_dir(home), "#{LABEL}.plist")
    def launcher_path(home) = File.join(home, ".omos/personal-memory/current/exe/omos-personal-memory")
    def trigger_log_path(home) = File.join(home, ".omos/personal-memory/schedule.log")
    def domain = "gui/#{Process.uid}"

    # launchd 的 stdout/stderr 本來就落在 schedule.log；pilot 只補一行結構化、
    # 不含知識內容的 marker，不另建 trigger state file／telemetry channel。
    def trigger_marker(period_id, observed_at: Time.now)
      "#{TRIGGER_LOG_PREFIX}#{JSON.generate({ "review_period_id" => period_id,
                                             "observed_at" => observed_at.iso8601 })}"
    end

    def trigger_observation(home:, period_id:)
      path = trigger_log_path(home)
      return nil unless File.file?(path)

      found = nil
      File.foreach(path, encoding: "UTF-8") do |line|
        next unless line.start_with?(TRIGGER_LOG_PREFIX)

        payload = JSON.parse(line.delete_prefix(TRIGGER_LOG_PREFIX))
        found = payload["observed_at"] if payload["review_period_id"] == period_id
      rescue JSON::ParserError
        next
      end
      found
    end

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
                anchor_weekday: ReviewQueue::FRIDAY,
                launchctl: method(:launchctl), plutil: method(:plutil_json),
                clock: method(:monotonic), sleeper: method(:sleep))
      unless (0..23).cover?(anchor_hour.to_i)
        raise Failed.new("SCHEDULE_ANCHOR_HOUR_INVALID", anchor_hour.inspect)
      end
      # T-7：限週一～週五。catch-up 以「下一個工作日」定義，允許週末 anchor
      # 會讓那個語意破掉。
      unless ReviewQueue::WEEKDAY_RANGE.cover?(anchor_weekday.to_i)
        raise Failed.new("SCHEDULE_ANCHOR_WEEKDAY_INVALID",
                         "#{anchor_weekday.inspect}；須為 1(週一)～5(週五)")
      end

      path = plist_path(home)

      with_lifecycle_lock(home) do
        FileUtils.mkdir_p(agents_dir(home))

        # **所有 authoritative state 都在 lock 之內讀取。**
        #
        # review P1：原本 existence／ownership／launcher 都在取得 lock 之前就
        # 讀了，進 lock 後再拿那份 `existing` 去決定要不要 binread。實測競態：
        #
        #   install：讀到 existing=true，停在 lock 前
        #   remove ：取得 lock → 正常移除 plist
        #   install：繼續 → 取得 lock → 仍用舊的 existing=true → binread 炸出
        #            Errno::ENOENT
        #
        # 有 flock 卻用 lock 前的快照，等於序列化只保護了寫入、沒保護判斷依據。
        # 契約 §1.4 要的是**整段 lifecycle mutation** 序列化，所以判斷依據必須
        # 在 lock 內重新取得。
        #
        # ownership 仍排在 launcher 之前：我們路徑上躺著別人的 plist，比
        # 「本地安裝不完整」更該先講。
        existing = File.file?(path)
        if existing && !own?(path, plutil: plutil)
          raise Failed.new("SCHEDULE_FOREIGN_PLIST_AT_OUR_PATH", path)
        end

        launcher = launcher_path(home)
        raise Failed.new("SCHEDULE_LAUNCHER_MISSING", launcher) unless File.exist?(launcher)

        # ── SNAPSHOT_OLD ────────────────────────────────────────────────
        # 必須在停舊 job **之前**：停掉之後才想留位元組就來不及了。
        # 也必須在 lock 之內：lock 外讀到的 bytes 可能已被別人換掉。
        #
        # review P1：原本寫 `loaded: loaded?(...)`，把 `:observation_error`
        # 壓成 `false`——於是觀測失敗時會**跳過 OLD_STOP**，直接把 plist 寫成
        # 新版，而舊 job 其實還活著，當場就是 disk=new／live=old。
        # 契約 §1.0.1 明文禁止第三態被壓成 false。
        #
        # 在明確知道舊 job 是 loaded 還是 not_loaded 之前，**不得發布新 plist**。
        snapshot = converge_definite(launchctl: launchctl, clock: clock, sleeper: sleeper)
        unless snapshot[:ok]
          raise Failed.new("SCHEDULE_OLD_STATE_UNOBSERVABLE",
                           "無法判定 #{domain}/#{LABEL} 目前是否載入" \
                           "（#{cause_text(snapshot[:cause])}），因此不發布新版 plist。" \
                           "磁碟維持原狀。")
        end

        old = { bytes: existing ? File.binread(path) : nil,
                loaded: snapshot[:observed] == :loaded }

        # ── OLD_STOP_VERIFIED ───────────────────────────────────────────
        # 舊 job 停不掉就**不得**發布新 plist：磁碟維持舊版、與 live 的舊 job
        # 一致，這是乾淨的失敗。
        if old[:loaded]
          out = bootout_and_verify(launchctl, clock: clock, sleeper: sleeper)
          raise Failed.new("SCHEDULE_LAUNCHCTL_BOOTOUT_FAILED", out[:detail]) unless out[:ok]
        end

        # ── PUBLISH_NEW_PLIST ───────────────────────────────────────────
        write_atomic(path, plist(home, anchor_hour.to_i, anchor_weekday.to_i))

        # ── NEW_ACTIVATION_ATTEMPTED ／ NEW_POSTCONDITION_CLASSIFIED ────
        verdict = bootstrap_and_verify(path, launchctl, clock: clock, sleeper: sleeper)
        if verdict[:ok]
          # ── FINAL_VERIFIED ──
          next { label: LABEL, plist: path, replaced: existing,
                 anchor_hour: anchor_hour.to_i, anchor_weekday: anchor_weekday.to_i,
                 loaded: true }
        end

        # ── CLEANUP_NEW_IF_NEEDED ───────────────────────────────────────
        # partial activation（§1.1 第四象限）：bootstrap 回非零但 job 其實已
        # 活起來。**必須先清掉新 job**，而且在清掉之前磁碟不准動——否則就是
        # disk=old／live=new。
        settled = verdict[:observed]
        if settled == :loaded
          cleanup = bootout_and_verify(launchctl, clock: clock, sleeper: sleeper)
          if cleanup[:ok]
            settled = :not_loaded
          elsif cleanup[:observed] == :loaded
            # 知道清不掉 → dirty failure。磁碟**保留新版**，與仍在跑的新 job
            # 對應。寧可停在「升級沒完成但一致」，也不製造 split-brain。
            raise Failed.new("SCHEDULE_PARTIAL_ACTIVATION_NOT_CLEANED",
                             "#{verdict[:detail]}；新 job 仍在載入中且清除失敗" \
                             "（#{cleanup[:detail]}）。磁碟保留新版以與 live job 一致，" \
                             "請手動處理 #{domain}/#{LABEL}")
          else
            # **不知道**清掉了沒——與上一格處置相同，但成因不同，錯誤碼分開。
            raise Failed.new("SCHEDULE_CLEANUP_STATE_UNOBSERVABLE",
                             "#{verdict[:detail]}；清除新 job 後仍無法判定狀態" \
                             "（#{cleanup[:detail]}）。磁碟保留新版，請手動檢查 " \
                             "#{domain}/#{LABEL}")
          end
        end

        # ── RESTORE_OLD_IF_NEEDED ───────────────────────────────────────
        # 契約 §1.0.1.1：**恢復舊 plist 之前必須明確觀察到 not_loaded。**
        # 仍無法判定就停在 dirty failure——在「不知道」的狀態下寫回舊版，
        # 可能正是被禁止的 disk=old／live=new。
        #
        # mixed observation 也走這一關：窗口裡曾經出現過正常觀測，不等於
        # 已確認停止。
        unless settled == :not_loaded
          raise Failed.new("SCHEDULE_RESTORE_BLOCKED_UNOBSERVABLE",
                           "#{verdict[:detail]}；無法明確確認新 job 已停止，" \
                           "因此不還原舊版（避免 disk=old／live=new）。" \
                           "磁碟保留新版，請手動檢查 #{domain}/#{LABEL}")
        end

        unless restore_old(path, old, launchctl, clock: clock, sleeper: sleeper)
          raise Failed.new("SCHEDULE_INSTALL_FAILED_AND_NOT_RESTORED",
                           "#{verdict[:detail]}；舊 plist／loaded 狀態未能完整還原，" \
                           "請手動檢查 #{path}")
        end

        raise Failed.new("SCHEDULE_LAUNCHCTL_BOOTSTRAP_FAILED", verdict[:detail])
      end
    end

    # 只移除本產品自己的 job：先確認 plist 內部 Label，再 bootout ＋ 刪檔。
    def remove(home:, launchctl: method(:launchctl), plutil: method(:plutil_json),
               clock: method(:monotonic), sleeper: method(:sleep))
      path = plist_path(home)

      # 卸載一個還在跑的東西，必須先真的把它停掉：忽略 bootout 成敗就刪 plist
      # 會留下一個誰都管不到的孤兒 job。
      with_lifecycle_lock(home) do
        # 與 install 同一個理由（review P1）：existence 與 ownership 都是這筆
        # 交易的判斷依據，必須在 lock 之內讀，否則兩個 process 會各自依據
        # 不同時刻的磁碟狀態動作。
        next { label: LABEL, removed: false, reason: "NOT_INSTALLED" } unless File.file?(path)
        unless own?(path, plutil: plutil)
          next { label: LABEL, removed: false, reason: "NOT_OURS",
                 found_label: plist_label(path, plutil: plutil) }
        end

        # 契約 §1.0 timeout 一致性：bootout timeout **不得刪 plist**，與
        # clean failure 同等對待——避免孤兒 job。
        if observe(launchctl: launchctl) != :not_loaded
          out = bootout_and_verify(launchctl, clock: clock, sleeper: sleeper)
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
    def restore_old(path, old, launchctl, clock: method(:monotonic), sleeper: method(:sleep))
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
      verdict = bootstrap_and_verify(path, launchctl, clock: clock, sleeper: sleeper)
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
    # 契約 §1.2 的四象限，post-condition 依 §1.0 的**有界收斂**判定：
    #
    #   exit 0   ＋ 5 秒內 not_loaded → 成功
    #   exit 0   ＋ 仍 loaded         → false success／timeout failure
    #   exit 非0 ＋ 5 秒內 not_loaded → 成功（其實已經停了）
    #   exit 非0 ＋ 仍 loaded         → clean failure
    #
    # 成功與否只看**有沒有收斂到 not_loaded**；exit code 只決定失敗時的說法。
    # Acceptance 8 的真機證據：bootout 回 exit=0 但立刻複查仍 loaded，
    # sleep 1 後才消失——post-condition 是 eventual，不是瞬時。
    def bootout_and_verify(launchctl, clock: method(:monotonic), sleeper: method(:sleep))
      res = launchctl.call("bootout", "#{domain}/#{LABEL}")   # 只呼叫一次，不 retry
      conv = converge_to(:not_loaded, launchctl: launchctl, clock: clock, sleeper: sleeper)
      return { ok: true, observed: :not_loaded, detail: nil } if conv[:ok]

      prefix = res[:ok] ? "launchctl bootout 回報成功（exit=#{res[:status]}）" \
                        : "launchctl bootout 回報失敗（exit=#{res[:status]} " \
                          "#{res[:err].to_s.strip[0, 80]}）"
      { ok: false, observed: conv[:observed], cause: conv[:cause],
        detail: "#{prefix}，但 #{domain}/#{LABEL} #{cause_text(conv[:cause])}" }
    end

    # **唯一**的 bootstrap 入口。install 與 rollback 都走這裡。
    # 契約 §1.1 的四象限，post-condition 同樣依 §1.0 的有界收斂判定：
    #
    #   exit 0   ＋ 5 秒內 loaded     → 成功
    #   exit 0   ＋ 仍未 loaded       → false success／timeout failure
    #   exit 非0 ＋ 5 秒內 loaded     → partial activation（沿用 §1.3.2 rollback）
    #   exit 非0 ＋ 仍未 loaded       → clean failure
    #
    # :observed 帶出「我們到底知不知道現在的狀態」，供 §1.0.1.1 的 restore
    # gate 判斷——那一關只接受**明確的** :not_loaded。
    def bootstrap_and_verify(path, launchctl, clock: method(:monotonic), sleeper: method(:sleep))
      res = launchctl.call("bootstrap", domain, path)   # 只呼叫一次，不 retry
      conv = converge_to(:loaded, launchctl: launchctl, clock: clock, sleeper: sleeper)

      if conv[:ok]
        return { ok: true, partial: false, observed: :loaded, detail: nil } if res[:ok]

        return { ok: false, partial: true, observed: :loaded,
                 detail: "launchctl bootstrap 回報失敗（exit=#{res[:status]} " \
                         "#{res[:err].to_s.strip[0, 80]}），但 #{domain}/#{LABEL} " \
                         "已載入（partial activation）" }
      end

      prefix = res[:ok] ? "launchctl bootstrap 回報成功（exit=#{res[:status]}）" \
                        : "launchctl bootstrap 回報失敗（exit=#{res[:status]} " \
                          "#{res[:err].to_s.strip[0, 80]}）"
      { ok: false, partial: false, observed: conv[:observed], cause: conv[:cause],
        detail: "#{prefix}，且 #{domain}/#{LABEL} #{cause_text(conv[:cause])}" }
    end

    # 契約 §1.0.1 的觀測**三態**。
    #
    #   :loaded            明確觀察到 service 存在
    #   :not_loaded        明確觀察到 service 不存在
    #   :observation_error 無法判定（權限、domain、I/O、其他非預期失敗）
    #
    # 第三態**不得**被壓成前兩態的任何一個。
    def observe(launchctl: method(:launchctl))
      res = launchctl.call("print", "#{domain}/#{LABEL}")
      return :loaded if res[:ok]

      res[:status] == PRINT_SERVICE_NOT_FOUND ? :not_loaded : :observation_error
    end

    # 有界收斂（契約 §1.0）。
    #
    # 先立即查一次，之後每 100ms 一次，最長 5 秒；看到目標狀態**立刻**結束。
    # 用 monotonic clock——牆上時鐘會被校時拉動，拿它當 correctness 等於讓
    # 逾時判斷隨系統設定漂移。
    #
    # observation_error **不終止輪詢**（它可能是暫時的），但也永遠不計為達成
    # 目標狀態。整個窗口的觀測序列留在 :seen 裡，供分類成因用。
    #
    # clock／sleeper 可注入：驗收要求 deterministic 的時間邊界測試，而測試
    # 不得真的 sleep 5 秒。這是 test seam，production 走預設值。
    # 單一的輪詢迴圈。`accept` 決定什麼算「到了」——收斂到某個狀態，或只是
    # 「拿到一個明確的答案」。判斷只寫一份；兩個包裝共用它。
    #
    # **deadline 是硬的**：每一輪先算 elapsed，逾時就**連這次觀測都不做**。
    # review P1：原本先 observe 再檢查時間，於是 sleeper 每次推進 110ms 時，
    # 在 5.06 秒才出現的 target 仍會被接受——契約寫的是「最長 5 秒」。
    def converge(launchctl:, clock: method(:monotonic), sleeper: method(:sleep), &accept)
      started = clock.call
      seen = []
      loop do
        elapsed = clock.call - started
        break if elapsed > CONVERGENCE_WINDOW_SECONDS

        observed = observe(launchctl: launchctl)
        seen << observed
        return { ok: true, observed: observed, seen: seen } if accept.call(observed)
        break if elapsed >= CONVERGENCE_WINDOW_SECONDS

        sleeper.call(POLL_INTERVAL_SECONDS)
      end

      { ok: false, seen: seen, cause: classify(seen) }
    end

    # 收斂到指定狀態。
    def converge_to(target, launchctl:, clock: method(:monotonic), sleeper: method(:sleep))
      r = converge(launchctl: launchctl, clock: clock, sleeper: sleeper) { |o| o == target }
      return r if r[:ok]

      r.merge(observed: settled_observation(r[:seen], target))
    end

    # 只要一個**明確**的答案（`:loaded` 或 `:not_loaded`），不管是哪一個。
    # SNAPSHOT_OLD 用它：在知道舊 job 到底在不在之前，不准發布新 plist。
    def converge_definite(launchctl:, clock: method(:monotonic), sleeper: method(:sleep))
      r = converge(launchctl: launchctl, clock: clock, sleeper: sleeper) do |o|
        o != :observation_error
      end
      return r if r[:ok]

      r.merge(observed: :unknown)
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    # 窗口結束而未達目標時，我們到底**知不知道**現在的狀態？
    # 只要出現過一次 observation_error 就是「不知道」——曾經看過幾次正常觀測
    # 不能讓我們宣稱已確認（契約 §1.0.1.1 的 mixed observation 解讀）。
    def settled_observation(seen, target)
      return :unknown if seen.include?(:observation_error)

      other = target == :loaded ? :not_loaded : :loaded
      seen.all? { |o| o == other } ? other : :unknown
    end

    # 契約 §1.0.1 第 4 點：三種成因必須分得開。
    def classify(seen)
      errors = seen.count(:observation_error)
      return :all_unobservable if errors == seen.size
      return :no_convergence if errors.zero?

      :mixed_observation
    end

    CAUSE_TEXT = {
      all_unobservable: "整個收斂窗口內都無法判定狀態",
      no_convergence: "觀測正常，但狀態未在 #{CONVERGENCE_WINDOW_SECONDS} 秒窗口內收斂",
      mixed_observation: "窗口內既有正常觀測也有無法判定（mixed observation）"
    }.freeze

    def cause_text(cause) = CAUSE_TEXT.fetch(cause, cause.to_s)

    # 便利包裝。**不得**用它取代收斂判定——它只回答「此刻」。
    # 接受並忽略 clock／sleeper，只為與其他入口簽名一致。
    def loaded?(launchctl: method(:launchctl), clock: nil, sleeper: nil)
      _ = [clock, sleeper]
      observe(launchctl: launchctl) == :loaded
    end

    def status(home:, now: Time.now, runtime: nil, surface: Runtime::SURFACES[:cli],
               launchctl: method(:launchctl), plutil: method(:plutil_json),
               clock: method(:monotonic), sleeper: method(:sleep))
      path = plist_path(home)
      present = File.file?(path)
      ours = present && own?(path, plutil: plutil)
      # repair-01 P1-2：anchor 從**已安裝的 plist** 讀回來，不用預設值猜。
      # 猜的話 15:00 的排程會被 status 當成 16:00，算出上一期的 period。
      hour = ours ? installed_anchor_hour(path, plutil: plutil) : nil
      weekday = ours ? installed_anchor_weekday(path, plutil: plutil) : nil
      effective = hour || ReviewQueue::DEFAULT_ANCHOR_HOUR
      effective_weekday = weekday || ReviewQueue::FRIDAY
      period = ReviewQueue.period_for(now, anchor_hour: effective,
                                           anchor_weekday: effective_weekday)
      # status 是**查詢**，不是 mutation：用單次觀測即可，不進收斂窗口。
      # clock／sleeper 只為與其他入口簽名一致而接受，這裡用不到。
      _ = [clock, sleeper]
      loaded = observe(launchctl: launchctl) == :loaded

      base = { label: LABEL, plist_present: present, plist_is_ours: ours,
               # 「已安裝」= plist 是我們的 **且** job 真的載入了。
               installed: ours && loaded, loaded: loaded,
               anchor_hour: hour, effective_anchor_hour: effective,
               anchor_weekday: weekday, effective_anchor_weekday: effective_weekday,
               plist: path, period: period[:id],
               scheduled_anchor_at: period[:scheduled_anchor_at],
               catch_up_deadline_at: period[:catch_up_deadline_at],
               # 逾期只是狀態，**不是** SKIPPED。terminal disposition 仍是人的
               # closeout——這一行是本檔最容易被「順手自動化」的地方。
               overdue: now >= Time.parse(period[:catch_up_deadline_at]) }
      return base if runtime.nil?

      q = ReviewQueue.due(runtime, now: now, anchor_hour: effective,
                                   anchor_weekday: effective_weekday, surface: surface)
      base.merge(due_count: q[:items].size, terminal_closeout: q[:terminal_closeout])
    end

    # 已安裝 plist 宣告的 anchor 小時。兩個來源必須一致：
    # StartCalendarInterval 的 Hour，與傳給 `review due` 的 --anchor-hour。
    # 不一致代表 plist 被手改過，寧可回 nil 讓上層退回預設並顯示，不猜。
    # 與 hour 同一個做法：兩個來源（StartCalendarInterval 與 ProgramArguments）
    # 必須一致，不一致回 nil 讓上層退回預設並顯示——不猜。
    # repair-01 P1-3：`review done/history` 需要知道「使用者實際排的是星期幾
    # 幾點」，但它不該為了問這件事去碰 launchctl——那是 mutation 路徑的東西。
    # 這支只讀 plist，且沿用既有的 own?／installed_anchor_* 判定，不新增
    # 第二個設定來源。plist 不是我們的、或兩處寫的 cadence 不一致時一律回
    # nil，由呼叫端退回預設（fail-open 到預設，不是猜一個值）。
    def installed_cadence(home:, plutil: method(:plutil_json))
      path = plist_path(home)
      return { anchor_hour: nil, anchor_weekday: nil } unless File.file?(path) &&
                                                              own?(path, plutil: plutil)

      { anchor_hour: installed_anchor_hour(path, plutil: plutil),
        anchor_weekday: installed_anchor_weekday(path, plutil: plutil) }
    rescue StandardError
      { anchor_hour: nil, anchor_weekday: nil }
    end

    def installed_anchor_weekday(path, plutil: method(:plutil_json))
      doc = plutil.call(path)
      return nil unless doc.is_a?(Hash)

      from_calendar = doc.dig("StartCalendarInterval", "Weekday")
      args = doc["ProgramArguments"]
      i = args.is_a?(Array) ? args.index("--anchor-weekday") : nil
      from_args = i && args[i + 1] && Integer(args[i + 1], exception: false)
      from_calendar == from_args ? from_calendar : nil
    end

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

    def plist(home, anchor_hour, anchor_weekday = ReviewQueue::FRIDAY)
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
            <string>--scheduled-trigger</string>
            <string>--anchor-hour</string>
            <string>#{anchor_hour}</string>
            <string>--anchor-weekday</string>
            <string>#{anchor_weekday}</string>
          </array>
          <key>StartCalendarInterval</key>
          <dict>
            <key>Weekday</key><integer>#{anchor_weekday}</integer>
            <key>Hour</key><integer>#{anchor_hour}</integer>
            <key>Minute</key><integer>0</integer>
          </dict>
          <key>RunAtLoad</key><true/>
          <key>StandardErrorPath</key><string>#{trigger_log_path(home)}</string>
          <key>StandardOutPath</key><string>#{trigger_log_path(home)}</string>
        </dict>
        </plist>
      XML
    end
  end
end
