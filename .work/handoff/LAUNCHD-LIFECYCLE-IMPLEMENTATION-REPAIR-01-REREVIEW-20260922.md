---
id: LAUNCHD-LIFECYCLE-IMPLEMENTATION-REPAIR-01-REREVIEW-20260922
card: CARD-LAUNCHD-LIFECYCLE-IMPLEMENTATION-20260922
contract: CARD-LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922
repair: 01
type: rereview
verdict: GO
reviewed_commit: 10f2add
---

# Launchd lifecycle implementation repair-01 再 review｜GO

| 級別 | 數量 |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 0 |
| P3 | 0 |

## 1. pre-lock race 已關閉

reviewer 用同一類構造重播（install 停在 `with_lifecycle_lock` 前 → remove
完整移除 → install 再繼續）：不再吃舊快照，install 重新取得 lock 內狀態，
最後正常安裝成 15:00，`plist=true / live=true`，**沒有 `ENOENT`**。

## 2. 真兩 thread 競態

```text
install/install = SUCCESS | SCHEDULE_LIFECYCLE_BUSY
install/remove  = SUCCESS | SCHEDULE_LIFECYCLE_BUSY
```

沒有兩邊同時成功，也沒有過期快照例外。

## 3. 靜態邊界

`install` 在 lock 前只剩參數驗證與 `plist_path` 計算；existence、ownership、
launcher existence、old bytes、loaded state 全部已進 lock。`remove` 同樣邊界。

## 4. 測試接縫裁決

**接受目前做法，不要求新增 production injection seam。** 這個不變式本質上
就是「authoritative read 必須位於 lock 內」，結構斷言適合鎖它；行為面由
reviewer 本輪的 deterministic concurrency 獨立證明。

**可選的後續**（非要求）：若要把 deterministic replay 常設化，可只利用既有的
`launchctl` 注入，在第一個 transaction 持鎖時用 barrier 卡住、再啟第二個
thread，**無須往產品碼新增 hook**。

## 5. §1.3.4 derived rule

`restore_old` 的 partial 補回 freeze 的方式與上一輪裁決一致。

## 6. reviewer 側實跑

| 項目 | 結果 |
|---|---|
| 3a | 26/26 PASS |
| 3b | 34/34 PASS |
| 3c | 329/329 PASS |
| validators | 40/40 |
| `git diff --check` | clean |
| launchd residue | ABSENT |

**`10f2add` 可以收。下一步回 Slice B closeout；Acceptance #8 真 launchd
實證仍照原約定留在 closeout。**
