---
id: EMEM11-SLICE-C-REPAIR-01-REREVIEW-20260921
card: CARD-EMEM11-STANDALONE-PACKAGING-IMPLEMENTATION-20260921
slice: C
repair: 01
type: rereview
verdict: GO
reviewed_commit: d652bee
evidence: .work/handoff/EMEM11-SLICE-C-REPAIR-01-EVIDENCE-20260921.md
---

# Slice C repair-01 再 review｜GO

| 級別 | 數量 |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 0 |
| P3 | 0 |

兩筆 P1 **CLOSED**。

## 1. 重播結果

- **P1-1 GC**：重播 `A → B → B`，receipt 維持 `current=B / previous=A`，
  `versions/` 同時保留 A/B，之後 rollback 可正常回 A。
- **P1-2 rollback transaction**：注入 `ROLLBACK_INJECTED_FAILURE` 後，
  `current`、receipt bytes、Host 設定全部恢復，pointer 與 receipt 仍一致。
- 上一輪的 `receipt chmod 0444` exploit 也重播：改成 `temp + rename` 後
  rollback 正常完成，不再造成 split。

## 2. reviewer 自己的鑑別力反證

reviewer **未沿用交付方的反轉點**：讓 `rollback_reachable_ids` 只回
current、不回 previous，立即重現「receipt 還指得到 previous、實物已被
GC」。保護不是假綠。

## 3. 狀態來源未重新分裂

rollback 與 GC 都只認 receipt；upgrade 走 install；uninstall 移除
activation ＋ receipt。

## 4. 待裁定項的裁定

`Installer#rollback(fail_before_receipt:)` **接受保留**。它與既有
`install(fail_after:)` 是同級 deterministic failure seam；為了這一個
failure path 再抽一層 writer injection 反而增加不必要結構。用途明確、
預設不啟用。

## 5. reviewer 側實跑

| 項目 | 結果 |
|---|---|
| 3a | 26/26 PASS |
| 3b | 34/34 PASS |
| 3c | 134/134 PASS |
| validators | 40/40 PASS |
| `git diff --check` | clean |

**Slice C repair-01 可收。**
