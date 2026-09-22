---
id: LAUNCHD-LIFECYCLE-IMPLEMENTATION-20260922
status: CONTRACT_GAP_FROM_REAL_RUNTIME_EVIDENCE
note: 10f2add 對**瞬時模型**是 GO，但 Acceptance 8 真機證據證明 freeze 本身少了時間維度。
  順序改為：補完 freeze（§1.0 狀態收斂語意）→ 契約 review → 實作 → 重跑 Acceptance 8。
accepted_at: 10f2add（重做 dfc9e75、repair-01 10f2add）
review_round_2: GO（2026-09-22，P0/P1/P2/P3 皆 0；.work/handoff/LAUNCHD-LIFECYCLE-IMPLEMENTATION-REPAIR-01-REREVIEW-20260922.md）
review_round_1: NO_GO（2026-09-22，P1×1：lock 邊界太晚，交易判斷依據仍可能是 lock 前的過期快照）→ repair-01 已修；restore_old 的 partial 裁決獲接受並補入契約 §1.3.4
type: implementation
severity: P1
contract: CARD-LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922（OWNER_SIGNED 2026-09-22）
parent_card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
replaces: B2 repair-01～04（CARD-PERSONAL-INBOX-SLICE-B-RESEARCH-20260921 §3.6–§3.9）
baseline: 8041188
authority: organizational-memory-os
---

# Launchd lifecycle — 依凍結契約重做

👉 [假設與目標確認]
- **目標**：把 `lib/omos/schedule.rb` 的生命週期改成符合已簽署契約的實作。
- **邊界**：只動 `schedule.rb` 與其測試；**不碰** `ReviewQueue`（B1 已 GO）、
  Slice A、installer、delivery-path。不擴充排程能力。
- **這不是 repair-05**：契約已凍結，本卡依契約重做，repair-01～04 的既有
  修法**逐條對照**、不自動沿用。

## 1. 必須實作的（全部來自已簽契約）

| 契約條款 | 實作要點 |
|---|---|
| §1.1 `bootstrap` 四象限 | 含 **exit 非 0 + 實際已 loaded = partial activation**（目前完全沒處理） |
| §1.2 `bootout` 四象限 | 含 **exit 非 0 + 實際已停 = 成功**（目前會誤判成失敗） |
| §1.3.1 階段序列 | `SNAPSHOT_OLD → OLD_STOP_VERIFIED → PUBLISH_NEW_PLIST → NEW_ACTIVATION_ATTEMPTED → NEW_POSTCONDITION_CLASSIFIED → CLEANUP_NEW_IF_NEEDED → RESTORE_OLD_IF_NEEDED → FINAL_VERIFIED`。**流程階段，不是資料結構**——不得建 FSM engine／ledger／DB |
| §1.3.2 rollback 順序 | 新 job 仍 live 時**先清掉它**；清掉前不得換回舊 plist、不得 restore old；清不掉停在 dirty failure，磁碟保留與 live 對應的定義 |
| §1.3.3 正向發布順序 | **`OLD_STOP_VERIFIED` 之前磁碟維持舊版**；確認舊 job 停止後才 `PUBLISH_NEW_PLIST`。`8041188` 現行的「先寫 plist 再停舊 job」**必須改掉** |
| §1.4 序列化 | 同一 `Label` 的 lifecycle mutation 序列化；拿不到序列權明確失敗（`SCHEDULE_LIFECYCLE_BUSY`），不排隊半套、不靜默跳過。用 OS 既有最薄手段，不得新建 daemon／broker |
| §1.5 boundary | crash／斷電／外部改動列為 recovery boundary，不在保證範圍 |

## 2. repair-01～04 既有修法的逐條對照（契約驗收第 10 項）

| 既有修法 | 對照結果 |
|---|---|
| `install`／`remove` 真的呼叫 launchctl（repair-01） | **沿用** |
| `installed` = plist 是我們的 **且** job 真的載入（repair-01） | **沿用** |
| anchor 完整傳遞 ＋ 從 plist 讀回（repair-01） | **沿用** |
| ownership 看 plist 內部 `Label`（repair-01） | **沿用** |
| `install`／`remove` 是交易（repair-02） | **重做**——階段序列與發布順序都變了 |
| `bootstrap_and_verify`（repair-03） | **重做**——需涵蓋第四象限 |
| `bootout_and_verify`（repair-04） | **重做**——需涵蓋第四象限 |
| `restore_previous` 用 `loaded?` 判斷舊 job 是否還活著（repair-04） | **移除**——契約 §1.3 明文禁止 |
| 先寫 plist 再停舊 job（repair-01 起沿用至今） | **移除**——違反 §1.3.3 |

## 3. Acceptance

直接引用契約 §2 的 11 項，不重寫。額外要求：

12. 測試不得把 job 載進執行者的真實 session；收尾檢查
    `launchctl print gui/$(id -u)/com.omos.personal-memory.weekly-review`
    為 ABSENT。
13. 各情境測試互相隔離（獨立 `mktmpdir`），反證不得連鎖。
14. 行數 delta 逐檔回報，並說明淨增是否符合 `MINIMUM_SUFFICIENT`。

## 3.1 實作結果（2026-09-22）

| 契約條款 | 實作 |
|---|---|
| §1.1 四象限 | `bootstrap_and_verify` 回 `{ok:, partial:, detail:}`；partial ＝ exit 非 0 但已載入 |
| §1.2 四象限 | `bootout_and_verify` 一律以**實際狀態**判定；exit 非 0 但已停 → 成功 |
| §1.3.1 階段序列 | `install` 內以區域變數 `old` 推進，無 FSM／ledger／DB |
| §1.3.2 rollback 順序 | partial 先 `CLEANUP_NEW_IF_NEEDED`；清不掉 → `SCHEDULE_PARTIAL_ACTIVATION_NOT_CLEANED`，**磁碟保留新版**與 live 一致 |
| §1.3.3 發布順序 | `OLD_STOP_VERIFIED` 之後才 `write_atomic`；舊 job 停不掉即失敗且磁碟維持舊版 |
| §1.4 序列化 | `with_lifecycle_lock` 用 `flock(LOCK_NB)`；拿不到即 `SCHEDULE_LIFECYCLE_BUSY`。鎖放 `~/.omos/personal-memory/`，**不放** `~/Library/LaunchAgents`（那是 launchd 的目錄，且會被自己的 plist 計數邏輯數進去） |
| §1.5 boundary | 未實作任何 crash recovery，符合契約列為 out-of-scope |

### 契約未明寫、實作時補齊的一條推論

`restore_old` 自己的 bootstrap 若是 **partial**（exit 非 0 但 job 已起來），
**視為還原成功**。理由：磁碟上此刻已經是舊版位元組，所以 live 的只可能是舊
設定——這是由階段序列推得的事實，不是用 `loaded?` 猜。契約 §1.1 的 partial
處理針對的是**新** activation；把還原判成失敗反而會讓使用者以為舊排程沒回來。

**此推論請 reviewer 裁定是否併入契約。**

### 行數 delta

| 檔案 | +/- |
|---|---|
| `lib/omos/schedule.rb` | +162 / −74（程式 74、註解 76、空白 13） |
| `test/conformance_3c.rb` | +230 |

產品程式**淨增 0 行**（74 加入、74 刪除）——本卡是重寫既有生命週期，不是加
功能。註解多於程式是刻意的：四象限與兩個方向的順序都必須在程式旁說清楚
為什麼，否則下一個人又會「順手」把它改回去。

## 3.2 repair-01（2026-09-22）：lock 邊界

reviewer 的 P1：`install`／`remove` 在取得 lifecycle lock **之前**就讀了
existence／ownership，進 lock 後又拿那份過期的 `existing` 去決定是否
`binread`。實測競態：

```text
install：讀到 existing=true，停在 lock 前
remove ：取得 lock → 正常移除 plist
install：繼續 → 取得 lock → 仍用舊的 existing=true → Errno::ENOENT
```

有 `flock` 卻用 lock 前的快照，等於序列化只保護了寫入、**沒保護判斷依據**。

修法：`install` 與 `remove` 的 existence／ownership／launcher／old bytes／
loaded 狀態**全部移進 `with_lifecycle_lock`**，在鎖內重新取得。
契約 §1.4 一併補上這句要求。

### 測試的分工（交付方揭露）

- **行為測試**：8 輪真 barrier 的 `install ↔ remove` 併發，斷言不得因過期
  快照炸出例外，且結束後磁碟與 live 一致。
- **結構檢查**：掃 `install`／`remove` 在 `with_lifecycle_lock` 之前是否出現
  `File.file?`／`binread`／`own?`／`loaded?`／`plist_label`。

**兩筆反證只有結構檢查抓到，行為測試沒抓到。** 原因是修好之後那個競態
**從外部已經構造不出來**——reviewer 上一輪是靠「讓第一個 install 停在 lock
前」構造的，那需要一個注入點。交付方選擇不為此開注入接縫，改用結構檢查
鎖住順序性質。**裁決（review round 2）**：**接受目前做法，不要求新增 production injection
seam。** 這個不變式本質上就是「authoritative read 必須位於 lock 內」，結構
斷言適合鎖它；行為面由 reviewer 的 deterministic concurrency 獨立證明。

可選的後續（非要求）：要把 deterministic replay 常設化，可只利用既有的
`launchctl` 注入，在第一個 transaction 持鎖時用 barrier 卡住再啟第二個
thread，無須往產品碼新增 hook。

## 4. 不做

不改 `ReviewQueue`／Slice A／installer、不擴充排程能力（多重 anchor／多 job／
非 macOS）、不引入第三方排程相依、不建 FSM engine／ledger／DB、不新建
daemon／broker、不做 Acceptance #8 真機實證（需 Owner 明示）。

## 5. Minimum Sufficient

- **why_not_less**：契約已凍結四象限與階段順序；少實作任一項，下一個未處理
  的組合仍會以「新 P1」回來——這正是 repair 線失敗的原因。
- **why_not_more**：只重做 lifecycle；ownership／anchor／notify 等已 GO 的
  部分沿用不動。
- **do_not_absorb**：不吸收 Acceptance #8 真機實證、delivery-path 驗收、
  §1.5 的 recovery boundary 三項。
