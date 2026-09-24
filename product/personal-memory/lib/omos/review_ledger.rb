# frozen_string_literal: true
#
# 週期帳（T-5／T-10 與決策函式）。
#
# 這一層回答三個管理問題：這禮拜有沒有上傳、是不是本週的版本、少了哪週。
# 全部不需要看任何人的知識內容——closeout receipt 本來就是 content-free 的
# pointer record，這正是它被設計成這樣的原因。
#
# **本檔不發明 lifecycle。** 它是「UX → 既有契約」的 deterministic adapter：
# 把人輸入的東西翻譯成既有 weekly_closeout_history evaluator 收得下的 payload。
# 合法性一律由那支 evaluator 判定，本檔不重寫第二份 SKIPPED／terminal／
# idempotency 規則。
#
# 契約卡：CARD-WEEKLY-UPLOAD-ACCOUNTABILITY-PREP-20260923。

require "date"
require "time"
require "set"
require_relative "review_queue"
require_relative "runtime"
require_relative "contract"

module OMOS
  module ReviewLedger
    PHASES = %i[before scheduled catch_up late].freeze
    TERMINAL_STATUSES = %w[COMPLETE SKIPPED NO_PROMOTION].freeze

    module_function

    # ---- T-5：phase classifier ------------------------------------------
    #
    # 四個 phase 一律是**半開區間**，三個邊界都是精確的瞬間：
    #
    #   A  = scheduled_anchor_at
    #   D0 = anchor 隔日 00:00:00 local     ← 不是「當日 23:59:59」
    #   C  = catch_up_deadline_at
    #
    #   BEFORE    (-∞, A)
    #   SCHEDULED [A, D0)
    #   CATCH_UP  [D0, C)      ← 週六日屬此段
    #   LATE      [C, +∞)
    #
    # 邊界左閉右開，**b 本身屬於後一個 phase**。寫成精確瞬間是為了讓
    # b-ε / b / b+ε 的邊界測試寫得出來——「當日結束」不是一個瞬間。
    #
    # **比較時間戳，不比較小時。** 既有 ReviewQueue.period_for 用的是
    # `local.hour < anchor_hour`，在 anchor 邊界剛好正確，但用在 D0 這種
    # 零時邊界會讓同一小時內的 ε 完全不改變結果，邊界測試形同虛設。
    def phase_of(now, period)
      t = now.getlocal
      a = Time.parse(period[:scheduled_anchor_at]).getlocal
      c = Time.parse(period[:catch_up_deadline_at]).getlocal
      d0 = day_after_local(a)

      return :before if t < a
      return :scheduled if t < d0
      return :catch_up if t < c

      :late
    end

    # anchor 當日的隔日零時（本機時區）。
    def day_after_local(anchor)
      d = anchor.to_date + 1
      Time.new(d.year, d.month, d.day, 0, 0, 0)
    end

    def catch_up_deadline_passed?(now, period) = phase_of(now, period) == :late

    # ---- T-10：history reducer ------------------------------------------
    #
    # 決策函式的輸入是 (current_phase, prior_failed_phase, has_terminal)，
    # 但真實輸入是按 attempt_seq 排好的整段 closeout history。這一步若各寫
    # 各的，決策函式的矩陣可以**全綠而產品仍判錯**。
    #
    # 三個出口，一個都不能少：
    #   has_terminal            history 含 terminal
    #   prior_failed_phase=nil  history 為空
    #   prior_failed_phase=<p>  **最後一筆** FAILED 的 actual_closeout_at 所屬 phase
    #
    # 「最後一筆」是全部重點：取第一筆在
    # `SCHEDULED FAILED → 跨進 CATCH_UP → CATCH_UP FAILED` 上就會判錯。
    def reduce_history(closeouts, period)
      return { has_terminal: true, prior_failed_phase: nil } if
        closeouts.any? { |c| TERMINAL_STATUSES.include?(c["final_status"]) }

      last_failed = closeouts.reverse.find { |c| c["final_status"] == "FAILED" }
      return { has_terminal: false, prior_failed_phase: nil } if last_failed.nil?

      at = Time.parse(last_failed.fetch("actual_closeout_at"))
      { has_terminal: false, prior_failed_phase: phase_of(at, period) }
    end

    # ---- attempt_kind：唯一的決策函式 -----------------------------------
    #
    # RETRY 只在**同一階段**內成立；跨階段一律回到該階段的首次種類。
    # 回傳 :reject 代表不得提交，由呼叫端給明確錯誤碼。
    def attempt_kind(current_phase:, prior_failed_phase:, has_terminal:)
      return :reject if has_terminal
      return :reject if current_phase == :before
      return "RETRY" if prior_failed_phase == current_phase

      current_phase == :scheduled ? "SCHEDULED" : "CATCH_UP"
    end

    # ---- 預期週期序列 ----------------------------------------------------
    #
    # 從**穩定的** origin（T-6 的 weekly_review_origin_at）起算，每個 ISO 週
    # 一個 period。origin 以前沒有可證明的資料，**視為 unknown，不得倒推成
    # MISSING**——偽造歷史比留白更糟。
    WEEK_SECONDS = 7 * 24 * 3600

    def expected_periods(origin_at, now, anchor_hour: ReviewQueue::DEFAULT_ANCHOR_HOUR,
                         anchor_weekday: ReviewQueue::FRIDAY)
      origin = Time.parse(origin_at.to_s).getlocal
      cursor = ReviewQueue.period_for(origin, anchor_hour: anchor_hour,
                                              anchor_weekday: anchor_weekday)
      current = ReviewQueue.period_for(now, anchor_hour: anchor_hour,
                                            anchor_weekday: anchor_weekday)
      # repair-01 P1-2：`period_for(origin)` 找的是「origin 之前最近一次
      # anchor」——origin 若落在週二，它會回到**上一個週五**的期別，於是
      # 安裝前一週被憑空報成 MISSING。規格簽的是「origin 以前不得倒推」，
      # 所以第一期必須是 **anchor 落在 origin 當下或之後**的那一期。
      # 原本的測試只挑 anchor 瞬間當 origin（anchor == origin，相等即納入），
      # 所以看不到這個洞。
      first = cursor
      first = ReviewQueue.period_for(origin + WEEK_SECONDS, anchor_hour: anchor_hour,
                                                            anchor_weekday: anchor_weekday) if
        Time.parse(cursor[:scheduled_anchor_at]) < origin

      out = []
      date = Date.parse(first[:scheduled_review_period_start])
      last = Date.parse(current[:scheduled_review_period_start])
      while date <= last
        out << ReviewQueue.period_for(Time.new(date.year, date.month, date.day, anchor_hour),
                                      anchor_hour: anchor_hour, anchor_weekday: anchor_weekday)
        date += 7
      end
      out
    end

    # ---- T-9：由 `--period` 反推該週期 ----------------------------------
    #
    # `2026-W38` → 該 ISO 週的 anchor 日 → 完整 period。
    # **兩個 cadence 欄位都綁這裡算出來的 anchor**，不得用「今天」——
    # 跨週補做時用當下時間會直接觸發 WRC_PERIOD_START_INCONSISTENT。
    ISO_WEEK = /\A(\d{4})-W(\d{2})\z/

    def period_from_iso_week(week, anchor_hour: ReviewQueue::DEFAULT_ANCHOR_HOUR,
                             anchor_weekday: ReviewQueue::FRIDAY)
      m = ISO_WEEK.match(week.to_s)
      raise ArgumentError, "--period 必須是 YYYY-Www，例如 2026-W38：#{week.inspect}" if m.nil?

      date = Date.commercial(m[1].to_i, m[2].to_i, anchor_weekday)
      ReviewQueue.period_for(Time.new(date.year, date.month, date.day, anchor_hour),
                             anchor_hour: anchor_hour, anchor_weekday: anchor_weekday)
    end

    # ---- closeout payload builder ---------------------------------------
    #
    # 只組 payload，合法性一律交既有 evaluator。本檔**不**重寫 SKIPPED／
    # terminal／idempotency 規則。
    class Rejected < StandardError
      attr_reader :code

      def initialize(code, detail = nil)
        @code = code
        super(detail.nil? ? code : "#{code}: #{detail}")
      end
    end

    # T-1：disposition 形狀**恰為** {category}。
    # 上游 allowlist 有四欄（category／record_ref／promotion_ref／
    # promotion_idempotency_key），只擋第五種——所以這是 **builder 自己保證**
    # 的收緊，沒有任何 evaluator 規則在守它。
    def build_done(runtime, period, dispositions, now: Time.now, surface: Runtime::SURFACES[:cli])
      # T-4 必須**最先**檢查。實測 bug：原本先算 due items，於是指向未來週期時
      # 回的是「漏掉項目」，而真正的問題是「這個週期還沒開始」——錯誤訊息把人
      # 導向錯的方向。
      assert_started!(now, period)

      # repair-02 P1-3：改用 `due_for`，cadence 一律從 period 身上讀。
      # 修正前這裡重新呼叫 `due` 卻沒把 cadence 傳下去，於是「設定讀對了、
      # 真正算本期 queue 時又用錯設定」——排週三 15:00 的人做 review done
      # 會拿到 REVIEW_DONE_ITEMS_OUT_OF_SCOPE。
      due_refs = ReviewQueue.due_for(runtime, period, surface: surface)[:items]
                            .map { |i| i["candidate_id"] }.to_set
      given = dispositions.keys.to_set

      # T-3：selected **恰為**該週期的 due items——兩個方向都要鎖。
      # 上游只要求 selected 與 dispositions 鍵集合相同，不要求涵蓋整個 queue
      # ——但契約明寫 NEEDS_ORG_FOLLOWUP 是唯一合法的「延後但不回答」，
      # 不是 silent carry-over。要延後必須明確給那個分類，不能靠不選它。
      #
      # repair-01 P1-1：原本只算 `due_refs - given`，於是「少選」被擋、
      # 「多塞」沒被擋——reviewer 塞了一筆 anchor 之後才建立、根本不屬於本期
      # queue 的 Candidate，build_done 照樣接受，下一期的資料就被寫進本期的
      # terminal closeout。集合的包含關係只鎖一個方向等於沒鎖。
      missing = due_refs - given
      unless missing.empty?
        raise Rejected.new("REVIEW_DONE_ITEMS_INCOMPLETE",
                           "#{missing.size} 筆待 review 沒有 disposition：" \
                           "#{missing.to_a.first(3).join(", ")}#{missing.size > 3 ? " …" : ""}")
      end

      extra = given - due_refs
      unless extra.empty?
        raise Rejected.new("REVIEW_DONE_ITEMS_OUT_OF_SCOPE",
                           "#{extra.size} 筆不屬於 #{period[:id]} 的 queue：" \
                           "#{extra.to_a.first(3).join(", ")}#{extra.size > 3 ? " …" : ""}")
      end

      categories = Contract.disposition_categories
      dispositions.each do |ref, category|
        unless categories.include?(category)
          raise Rejected.new("REVIEW_DONE_UNKNOWN_CATEGORY",
                             "#{category.inspect}；可用：#{categories.to_a.sort.join(", ")}")
        end
      end

      # T-2：final_status 固定 NO_PROMOTION。上游允許 COMPLETE／FAILED——
      # 但本產品的 review 只做「看過並分類」，不做 promotion，宣稱 COMPLETE
      # 會讓 closeout 讀起來像完成了一件其實沒做的事。
      base(period, dispositions.keys, dispositions.transform_values { |c| { "category" => c } },
           "NO_PROMOTION", runtime, now)
    end

    # T-8：review skip 固定送空集合。**上游並未要求 SKIPPED 必須是空集合**
    # ——這是產品縮窄合法輸入。
    def build_skip(runtime, period, now: Time.now)
      # 同上：T-4 先於 catch-up 期限檢查。未來週期的正確答案是
      # REVIEW_PERIOD_NOT_STARTED，不是「catch-up 期限尚未過」。
      assert_started!(now, period)

      unless phase_of(now, period) == :late
        raise Rejected.new("REVIEW_SKIP_BEFORE_CATCH_UP_EXHAUSTED",
                           "catch-up 期限（#{period[:catch_up_deadline_at]}）尚未過，不得宣告 SKIPPED")
      end

      base(period, [], {}, "SKIPPED", runtime, now)
    end

    # Pilot receipt 只投影週期帳的 content-free 事實，不輸出 disposition 內容。
    # 非 terminal 的 FAILED attempt 仍要看得到；完全沒有 attempt 才是 MISSING。
    def receipt_state(runtime, period)
      entries = runtime.store.closeouts_for(period[:id])
      terminal = entries.reverse.find { |e| TERMINAL_STATUSES.include?(e["final_status"]) }
      latest = entries.last
      { review_status: terminal&.fetch("final_status", nil) || latest&.fetch("final_status", nil) || "MISSING",
        attempt_count: entries.size,
        terminal_closeout: !terminal.nil? }
    end

    # T-4：BEFORE 拒絕。**上游不擋提前關帳**，這是產品收緊。
    def assert_started!(now, period)
      return unless phase_of(now, period) == :before

      raise Rejected.new("REVIEW_PERIOD_NOT_STARTED",
                         "#{period[:id]} 的 anchor 是 #{period[:scheduled_anchor_at]}，尚未到")
    end

    def base(period, selected, dispositions, final_status, runtime, now)
      assert_started!(now, period)
      current = phase_of(now, period)
      reduced = reduce_history(runtime.store.closeouts_for(period[:id]), period)
      kind = attempt_kind(current_phase: current,
                          prior_failed_phase: reduced[:prior_failed_phase],
                          has_terminal: reduced[:has_terminal])
      if kind == :reject
        raise Rejected.new("REVIEW_PERIOD_ALREADY_TERMINAL",
                           "#{period[:id]} 已有終局 closeout")
      end

      { "review_period_id" => period[:id],
        # T-9：兩個 cadence 欄位都綁 --period 的 anchor，不用「今天」。
        "scheduled_review_period_start" => period[:scheduled_review_period_start],
        "scheduled_anchor_at" => period[:scheduled_anchor_at],
        "actual_closeout_at" => now.getlocal.iso8601,
        "attempt_kind" => kind,
        "final_status" => final_status,
        "catch_up_deadline_passed" => current == :late,
        "selected_item_refs" => selected,
        "item_dispositions" => dispositions }
    end

    # ---- 週期帳 ----------------------------------------------------------
    #
    # 每個預期週期一列。**MISSING 就是「少了哪週」的答案**——沒有這一列，
    # 漏掉的週只是空白，而空白無法管理。
    def history(runtime, origin_at, now: Time.now, anchor_hour: ReviewQueue::DEFAULT_ANCHOR_HOUR,
                anchor_weekday: ReviewQueue::FRIDAY)
      expected_periods(origin_at, now, anchor_hour: anchor_hour,
                                       anchor_weekday: anchor_weekday).map do |period|
        entries = runtime.store.closeouts_for(period[:id])
        terminal = entries.find { |e| TERMINAL_STATUSES.include?(e["final_status"]) }
        { "period" => period[:id].split(":").last,
          "period_ref" => period[:id],
          "scheduled_review_period_start" => period[:scheduled_review_period_start],
          "status" => terminal ? terminal["final_status"] : "MISSING",
          "attempts" => entries.size,
          "phase" => phase_of(now, period).to_s.upcase,
          "closed_at" => terminal && terminal["actual_closeout_at"] }
      end
    end
  end
end
