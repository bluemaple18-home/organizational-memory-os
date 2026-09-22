---
id: LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922
status: AWAITING_OWNER_SIGNATURE
type: spec-freeze
severity: P1
parent_card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
supersedes_repair_line: CARD-PERSONAL-INBOX-SLICE-B-RESEARCH-20260921 §3.6–§3.9（B2 repair-01～04）
hard_stop_reason: 同一根因連續四輪 repair，違反「同一 blocker 第 3 次失敗即停」
authority: organizational-memory-os
---

# Launchd lifecycle transaction — spec freeze

👉 [假設與目標確認]
- **目標**：一次把 launchd 生命週期的狀態機**凍結完整**，取代逐輪補 `if`
  的 repair 線。
- **邊界**：只定義契約與驗收；**本卡不含實作**。實作依凍結後的契約重做，
  並重新檢視 repair-01～04 既有修法是否符合。
- **現況**：`AWAITING_OWNER_SIGNATURE`。契約未簽前不動產品碼。

## 0. 為什麼停掉 repair 線（Hard Stop）

CLAUDE.md：**同類連兩次無進展→停；同一 blocker 第 3 次失敗即停。**

B2 的 launchd 生命週期連做了四輪，每一輪 reviewer 都給 NO_GO：

| 輪次 | reviewer 標題 | 實際根因 |
|---|---|---|
| repair-01 | install/remove 沒真的管理 launchd job | command 回傳值 ≠ 實際狀態 |
| repair-02 | install/remove 不是交易 | 同上 |
| repair-03 | bootstrap 回 0 不等於已載入 | 同上 |
| repair-04 | bootout 回 0 不等於已停止 | 同上 |
| （未開）repair-05 | bootstrap 回非零時未檢查是否其實已載入 | 同上 |

**四輪的根因是同一句話**：command 的回傳值不等於系統的實際狀態。
每一輪的修法形狀也相同——再抽一個 verify seam、再補一次 post-condition。
這已經證明它不是「再補一個 `if`」能乾淨收掉的問題。

交付方未在第三輪停下，是違規；本卡即為 Hard Stop 的產出。

## 1. 必須凍結的狀態機

### 1.1 `bootstrap` 的四種結果（目前只處理三種）

| exit | 實際 loaded | 語意 | 必須怎麼做 |
|---|---|---|---|
| 0 | true | 成功 | 完成 |
| 0 | false | 假成功 | 失敗；清乾淨 |
| 非 0 | false | clean failure | 失敗；無殘留 |
| 非 0 | **true** | **partial activation** | **先清掉新 job，再恢復舊狀態**——目前完全沒處理 |

第四種是 reviewer 最後一輪實測到的兩個壞狀態的來源：

- 首次安裝：bootstrap 回 failure 但 15:00 job 其實已 live → 回錯誤碼、
  plist 被刪 → **15:00 job 變孤兒**。
- 升級 16:00→15:00：舊 job 已成功停掉，新 job bootstrap 回 failure 但其實
  已 live → rollback 把 plist 還原成 16:00，又因為看到 `loaded=true` 誤以為
  舊 job 已恢復 → **disk=16:00 / live=15:00**。

### 1.2 `bootout` 的四種結果（對稱，同樣必須列全）

| exit | 實際 loaded | 語意 | 必須怎麼做 |
|---|---|---|---|
| 0 | false | 成功 | 完成 |
| 0 | true | 假成功 | 失敗；不得往下走 |
| 非 0 | true | clean failure | 失敗；保留 plist |
| 非 0 | **false** | 其實已經停了 | **視為成功**——目前會誤判成失敗 |

### 1.3 rollback 不得再用 `loaded?` 猜

**這是本卡的核心裁決。** `loaded?` 只回答「這個 Label 現在有沒有東西在跑」，
**答不出跑的是舊的還是新的**。repair-04 用它來判斷「舊 job 從未被停掉」，
在 partial activation 下就會把新 job 誤認成舊 job。

rollback 必須依據**明確記錄的交易狀態**，至少包含：

- 舊 job 原本是否 loaded
- 舊 job 是否**已成功**停掉（`bootout_and_verify` 的結果，不是推測）
- 新 activation 是否**已嘗試**、結果為何（含 partial）

## 2. 驗收

1. `bootstrap` 四種結果各有測試，**含 exit 非 0 + loaded 的 partial
   activation**：新 job 必須被清掉，舊狀態必須恢復，磁碟與 live 一致。
2. `bootout` 四種結果各有測試，含「exit 非 0 但其實已停」視為成功。
3. **任何時刻磁碟 plist 與 live job 的設定必須一致**，或明確失敗並說出
   不一致的內容。不得出現 `disk=A / live=B` 而回報成功。
4. rollback 的判斷**不得**來自 `loaded?` 的推測；測試必須能構造
   「新 job 已 live 但 bootstrap 回失敗」並證明 rollback 仍然正確。
5. 不得留下孤兒 job：任何失敗路徑結束後，`Label` 要嘛對應到磁碟上的
   plist，要嘛完全不存在。
6. repair-01～04 的既有修法逐條對照新契約，**不符者一併改**；
   符合者註明沿用。
7. 每一項附鑑別力反證，且各情境測試互相隔離（獨立 `mktmpdir`），
   反證不得連鎖。

### Acceptance #8 residual（沿用）

conformance 全程注入替身，沒有真 launchd 成功路徑的實證。**Slice B closeout
前必須在正常使用者 HOME 實跑一次**：`schedule install` → `launchctl print`
（存在）→ `schedule remove` → `launchctl print`（不存在）。
此項會在 Owner 機器上真的註冊 LaunchAgent，**需 Owner 明示才執行**。

## 3. 不做

不改 `ReviewQueue`（B1 已 GO，無 blocker）、不改 Slice A、不擴充排程能力
（多重 anchor／多 job／非 macOS）、不引入第三方排程相依。

## 4. Minimum Sufficient

- **why_not_less**：只修第四種 bootstrap 結果，就是 repair-05，而這條路
  已經證明會有第五次。契約不列全，下一個未處理的組合仍會以「新 P1」的形式
  回來。
- **why_not_more**：只凍結 launchd 這一個子系統的狀態機；不順手重寫
  installer 的 activation，也不把同型教訓推廣成通用框架。
- **do_not_absorb**：不吸收 Acceptance #8 的真機實證（需 Owner 明示）；
  不吸收 delivery-path 驗收（upgrade／zip／quarantine）。
