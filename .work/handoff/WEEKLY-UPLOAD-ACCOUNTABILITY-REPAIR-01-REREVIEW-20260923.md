# 週期帳 repair-01 — 定點 re-review 交付包

## 鎖定

```
base              72d87ec   Freeze C 規格（已 GO，immutable）
original_review   e12ab90   第 1 輪實作（NO_GO，P1×3，immutable）
repair_01         44f4f8b   本次修復
branch            main
```

定點 diff：`git diff e12ab90..44f4f8b`

## 這一輪只審三筆 P1 有沒有真的收掉

規格不重開，實作的其他部分也不重開。逐筆如下。

### P1-1 T-3 只擋「少選」，沒擋「多塞」

`build_done` 另加 `extra = given - due_refs` → `REVIEW_DONE_ITEMS_OUT_OF_SCOPE`。

重播你的變異：測試 `P1-1 多塞不屬於本期 queue 的項目 → 拒絕` 就是你描述的
fixture（`now: anchor + 3600` 建一筆 Candidate 並加進 dispositions）。
前置條件另外斷言了那一筆確實不在本期 queue，避免「因為別的原因被擋」而假綠。

反證 R1（把 `extra` 寫死成空集合，等同修復前）→ RED。

### P1-2 anchor 前安裝會多報上一週 MISSING

`expected_periods` 的第一期改成 **anchor 落在 origin 當下或之後**的那一期。
不是「origin 的 ISO 週」——那在「origin 落在週五 15:00、anchor 是當天 16:00」
時會給出錯的答案。用 anchor 比較同時蓋住你給的週二案例與這個案例。

取樣點改成圍住 anchor 邊界的 `b-ε／b／b+ε`，另加兩個一般點：

```
週五 15:00（b-ε）      → 2026-W38
週五 16:00（b，相等即納入）→ 2026-W38
週五 16:00:01（b+ε）   → 2026-W39
週六 10:00             → 2026-W39
週二 10:00             → 2026-W39   ← 你報的案例
```

反證 R2（起點改回 `period_for(origin)`）→ RED；
R3（邊界改 `<=`，把 anchor 本身排除）→ RED。

### P1-3 自訂排程時間沒有成為 review 的 authority

新增 `Schedule.installed_cadence(home:)`：**只讀 plist、不碰 launchctl**，
沿用既有的 `own?` 與 `installed_anchor_hour/weekday`，沒有新增設定來源。
`CLI#anchor_opts` 改成 `明示 CLI > 已安裝 plist > 預設`。

反證 R4（跳過已安裝 cadence）→ RED；R5（讓已安裝蓋過明示參數）→ RED。

## repair-01 自己揭露的第四個缺口（請一併看）

反證 R6 把 `own?` 歸屬判定拿掉，**全套仍然全綠**——也就是別人的 plist 佔在
我們的路徑上時會決定我們的 review cadence，而原本沒有任何測試釘住。
已補兩條（`installed_cadence` 回 nil、`anchor_opts` 退回預設），R6b 轉紅。

這一點不在你的 finding 清單裡，是修 P1-3 時順著反證找出來的。

## 未收的 P2（依你指定不擋卡）

- P2-1 `ReviewLedger::TERMINAL_STATUSES` 是 upstream vocabulary 的第二份抄本
- P2-2 `schedule status` 判「採預設」只看 `anchor_hour.nil?`，會隱藏 weekday drift

兩筆都記在卡片 §9。

## 交付方自己跑過

```
3a 26/26  ·  3b 34/34  ·  3c 407/407（repair-01 新增 16 條）
六支 validator 全 PASS  ·  git diff --check 乾淨  ·  launchd 殘留 0
反證 7 個：R1–R5 直接轉紅，R6 揭露真缺口、補測後 R6b 轉紅
```

體積：產品 +59、測試 +153。

## 要求

只就上面三筆 P1（加上第四個缺口的補測）給 GO 或 NO_GO。
每一條 P0/P1 請附可重現的變異：改哪一行、哪條測試轉紅，或證明沒有測試會轉紅。
