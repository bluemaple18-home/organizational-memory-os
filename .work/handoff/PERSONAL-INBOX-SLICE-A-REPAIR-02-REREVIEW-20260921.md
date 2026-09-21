---
id: PERSONAL-INBOX-SLICE-A-REPAIR-02-REREVIEW-20260921
card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
slice: A
repair: 02
type: rereview
verdict: GO
reviewed_commit: 77e11e0
residual: P2×1（tmp uniqueness 的常設 regression 未開真 thread；不阻塞）
---

# Slice A repair-02 再 review｜GO

| 級別 | 數量 |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 1（residual，不阻塞） |
| P3 | 0 |

## 1. 三筆 repair 都關閉

- **owner ref**：reviewer 用**自己挑的**畸形值測，確認守住最低的
  `urn:omos:<kind>:<id>` 邊界，沒有偷偷升級成 UUIDv7。
- **真實兩個 process race**：一邊成功，另一邊正確回
  `INBOX_EVIDENCE_OWNER_CONFLICT`，不再偷拿對方 provenance，
  `.writing-*` 殘骸為 0。
- **同 process 兩 thread**：一邊建立、一邊 replay，兩邊都成功；
  故意把 tmp uniqueness 退回固定值後立刻重現 `Errno::ENOENT`，
  證明 `SecureRandom` 修法真的 load-bearing。

## 2. 兩個修法彼此獨立

reviewer 單獨撤掉 `adopt_existing` 的 provenance 驗證：race 立刻重新變成
兩邊都成功、輸家拿到贏家的 identity。**證明兩個修法不是互相遮蔽**——
這正是交付方主動揭露的疑點（反證「tmp 名改回只有 pid」時 P1-2 也轉紅）。

## 3. 測試接縫的裁決

`capture(before_rename:)` **收**。理由：bounded deterministic failure／race
injection，形狀與先前已接受的 `rollback(fail_before_receipt:)` 一致，
且 production caller 沒有使用它。

## 4. P2 residual（不阻塞）

repo 裡目前的 tmp uniqueness 測試主要驗 **tmp 名字的形狀**，沒有真的開兩個
thread，因此常設 regression 對「同 process 併發」的鑑別力比 reviewer 這輪
實測弱。建議 **Slice B 開工前**順手改成真正的兩-thread barrier 測試。

## 5. reviewer 側實跑

| 項目 | 結果 |
|---|---|
| 3a | 26/26 PASS |
| 3b | 34/34 PASS |
| 3c | 224/224 PASS |
| validators | 40/40 PASS |
| `git diff --check` | clean |

**Slice A 可收片，Slice B 可以開工。**
