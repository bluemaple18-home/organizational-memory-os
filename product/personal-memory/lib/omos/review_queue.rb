# frozen_string_literal: true
#
# Weekly review queue（Slice B1）。
#
# **queue 是 projection，不是資料表。** 每次由既有事實重算：store 裡的
# PersonalMemoryCandidate ＋ closeouts。不新增 review_queue table——多一張表就
#多一份會漂移的狀態，而週期身分正是最不能漂移的東西。
#
# 這一層**只準備 queue 與回報**。契約（weekly_review_cycle）已經把
# acceptance authority 封死在每個 Candidate 自己的 verification／acceptance
# gate 上，批次確認本身不能接受任何東西。所以這裡沒有、也不該有任何
# closeout／Promotion／Record 的寫入路徑。
#
# ## review_period_id 怎麼來
#
# 契約明文禁止「用工作實際發生在哪一天去重新推導身分」：同一個排定週期的
# 每一次嘗試——準時、隔日 catch-up、失敗後 retry——都必須帶同一個 id。
#
# 因此 id 是**排定 anchor 那一天**的函數，不是今天的函數。既有資料已經定下
# 形狀（`urn:omos:personal-memory:review-period:2026-W38` 配
# `scheduled_review_period_start: 2026-09-18`），所以這裡沿用而不是新造：
# 取 anchor 那個週五的 ISO 年週。
#
# 這個區別是本檔最容易出錯的地方：週五排定的週期，在下週一做 catch-up 時，
# **今天**的 ISO 週已經是下一週了。拿今天去算就會憑空生出一個新週期，把這一
# 期的工作記到下一期頭上——正是契約禁止的那件事。

require "date"
require "set"
require "time"
require "json"
require_relative "runtime"

module OMOS
  module ReviewQueue
    REF_PREFIX = "urn:omos:personal-memory:review-period:"
    FRIDAY = 5

    # anchor 的預設時刻（FRIDAY_AFTERNOON）。契約允許 tenant 設定其他
    # Friday-afternoon 時間，但改 anchor 不得連帶改 closeout_statuses、
    # attempt_kinds 或 receipt schema——所以這裡只是一個時刻，沒有別的語意。
    DEFAULT_ANCHOR_HOUR = 16

    module_function

    # 現在（now）所屬的排定週期。
    #
    # 規則：**最近一個已經到達的 anchor**。週五 anchor 之前仍屬於上一期——
    # 這一期的 anchor 還沒到，queue 自然還不該被喚起。
    def period_for(now, anchor_hour: DEFAULT_ANCHOR_HOUR)
      d = now.to_date
      back = (d.wday - FRIDAY) % 7
      friday = d - back
      friday -= 7 if back.zero? && now.hour < anchor_hour

      { id: "#{REF_PREFIX}#{friday.strftime("%G-W%V")}",
        scheduled_review_period_start: friday.to_s,
        scheduled_anchor_at: Time.utc(friday.year, friday.month, friday.day, anchor_hour).iso8601,
        catch_up_deadline_at: catch_up_deadline(friday, anchor_hour) }
    end

    # catch-up 窗口到**下一個工作日**結束。契約只說 "next business day"，
    # 沒有給演算法；這裡取週一到週五，**不含國定假日**——產品沒有行事曆，
    # 而假造一份行事曆比沒有更糟（它會在不同地區悄悄算錯）。
    # 這個限制寫在這裡，不是藏在某個常數裡。
    def catch_up_deadline(friday, anchor_hour)
      d = friday + 1
      d += 1 while [0, 6].include?(d.wday)   # 跳過週六、週日
      Time.utc(d.year, d.month, d.day, anchor_hour).iso8601
    end

    # 這一期的 queue。
    #
    # 選取條件刻意只有兩條，而且都由契約直接推得：
    #
    #   1. Candidate 還停在 PROPOSED——還沒被任何人處置過。
    #   2. 它的 chronology.created_at **不晚於本期 anchor**。契約明寫
    #      「下一期的新證據絕不混進這一期的 review」，所以時間窗是硬性的，
    #      不是為了讓數字好看。
    #
    # 已經在本期 terminal closeout 裡被處置過的項目要排除——否則同一筆會在
    # closeout 之後仍然出現在 queue 裡，看起來像沒做完。
    def due(runtime, now: Time.now.utc, anchor_hour: DEFAULT_ANCHOR_HOUR,
            surface: Runtime::SURFACES[:cli])
      period = period_for(now, anchor_hour: anchor_hour)
      rows = runtime.read_rows(surface: surface)
      handled = dispositioned_refs(runtime, period[:id])
      anchor = Time.parse(period[:scheduled_anchor_at])

      items = rows.select { |r| r[:kind] == "PersonalMemoryCandidate" }.filter_map do |r|
        res = r[:resource]
        next unless res["candidate_status"] == "PROPOSED"
        next if handled.include?(r[:row_id])

        created = parse_time(res.dig("chronology", "created_at"))
        next if created.nil? || created > anchor

        { "candidate_id" => r[:row_id],
          "memory_kind" => res["memory_kind"],
          "created_at" => res.dig("chronology", "created_at"),
          "employee_owner_ref" => res["employee_owner_ref"] }
      end

      period.merge(items: items.sort_by { |i| [i["created_at"].to_s, i["candidate_id"]] },
                   terminal_closeout: terminal_closeout?(runtime, period[:id]),
                   catch_up_deadline_passed: now >= Time.parse(period[:catch_up_deadline_at]))
    end

    # closeouts_for 已經回 parse 過的 Hash，這裡不再自己 parse 一次——
    # 多一份解析就多一個會與 store 漂移的地方。
    def dispositioned_refs(runtime, period_id)
      runtime.store.closeouts_for(period_id).flat_map do |payload|
        (payload["item_dispositions"] || {}).keys
      end.to_set
    end

    def terminal_closeout?(runtime, period_id)
      runtime.store.db.get_first_value(
        "SELECT COUNT(*) FROM closeouts WHERE review_period_id = ? AND is_terminal = 1", [period_id]
      ).to_i.positive?
    end

    def parse_time(value)
      value.nil? ? nil : Time.parse(value)
    rescue ArgumentError
      nil
    end
  end
end
