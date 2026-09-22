---
id: LAUNCHD-LIFECYCLE-TRANSACTION-SPEC-FREEZE-20260922
status: AWAITING_OWNER_SIGNATURE
contract_review_round_1: NO_GO（2026-09-22，P1×2：rollback 順序未凍死／缺 transaction 單一寫入者；P2×1：未明寫 failure boundary）→ 已補
contract_review_round_2: NO_GO（2026-09-22，P1×1：forward upgrade 的 plist 發布順序未凍死，仍可留下 disk=new／live=old）→ 本版已補
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

#### 1.3.1 交易階段序列（取代三個 boolean）

實作必須沿著一條**明確的階段序列**推進，每一步的結果都記下來；rollback 只
依據「走到哪一階段、該階段的分類是什麼」決定動作，**永遠不問 `loaded?`
現在活著的是誰**。

```text
SNAPSHOT_OLD
  → OLD_STOP_VERIFIED
  → PUBLISH_NEW_PLIST                 （**必須在停掉舊 job 之後**，見 §1.3.3）
  → NEW_ACTIVATION_ATTEMPTED
  → NEW_POSTCONDITION_CLASSIFIED      （§1.1 的四象限之一）
  → CLEANUP_NEW_IF_NEEDED
  → RESTORE_OLD_IF_NEEDED
  → FINAL_VERIFIED
```

- 這是**流程階段**，不是新的資料結構：不得為它建 DB、FSM engine 或
  持久化 ledger。階段狀態存活於單次 lifecycle 呼叫之內。
- `SNAPSHOT_OLD` 至少含：舊 plist 位元組（或「本來沒有」）、舊 job 原本
  是否 loaded。
- `OLD_STOP_VERIFIED` 是 `bootout` 四象限（§1.2）的分類結果，**不是**
  「我們呼叫過 bootout」。
- `NEW_POSTCONDITION_CLASSIFIED` 是 `bootstrap` 四象限（§1.1）的分類結果。

#### 1.3.2 rollback 的順序被凍死（contract review P1-1）

`partial activation` 的清理**自己也可能失敗**，所以順序不能留給實作決定：

1. **新 job 若仍 live，第一步一定是清掉它**（走完整的 `bootout` 四象限）。
2. 在新 job 確認停掉**之前**：
   - **不得**把磁碟 plist 換回舊版；
   - **不得**開始 restore old。
3. 清不掉就停在 **dirty failure**：明確失敗、回專屬錯誤碼，且**磁碟必須
   仍保留與 live job 對應的定義**。

   換句話說：寧可停在 `disk=new / live=new` 的失敗，也**絕不**製造
   `disk=old / live=new`。前者是「升級沒完成但一致」，後者是 split-brain。
4. 只有新 job 確認已停，才進 `RESTORE_OLD_IF_NEEDED`。

#### 1.3.3 正向 upgrade 的發布順序也被凍死（contract review round 2 P1）

§1.3.2 只禁止了 rollback 方向的 `disk=old / live=new`。**正向 upgrade 的
對稱狀態同樣是 split-brain，必須一併凍死。**

`8041188` 目前的順序是：

```text
snapshot old → 寫 new plist → bootout old job → bootstrap new job
```

先寫 plist、後停舊 job，中間必然存在一段：

```text
disk = new 15:00
live = old 16:00
```

這與 rollback 那一側是同一個錯，只是方向相反。不明文禁止的話，實作者照現有
順序改其他部分，仍可能「符合卡片」卻留下同類 split-brain window。

**凍結規則**：

> **`OLD_STOP_VERIFIED` 之前，磁碟 plist 必須維持舊版。只有確認舊 job 已
> 停止後，才可發布 new plist（`PUBLISH_NEW_PLIST`），再進
> `NEW_ACTIVATION_ATTEMPTED`。**

推論（一併凍結，避免實作各自解讀）：

- 首次安裝沒有舊 job，`OLD_STOP_VERIFIED` 直接以「本來就沒有」通過，
  才進 `PUBLISH_NEW_PLIST`。
- 舊 job 停不掉時**不得**發布 new plist——磁碟仍是舊版，與 live 的舊 job
  一致，這是乾淨的失敗。
- `SNAPSHOT_OLD` 仍在最前面：要停舊 job 之前就得先把舊 plist 位元組留下來，
  否則 rollback 無從還原。

### 1.4 lifecycle mutation 必須序列化（contract review P1-2）

目前的交易狀態只在**單一** `install` 流程內成立。兩個 `schedule
install`／`remove` 同時跑時，彼此都可能拿到過期的 `SNAPSHOT_OLD`／
`OLD_STOP_VERIFIED`／`NEW_ACTIVATION_ATTEMPTED`——第二個 process 可以直接把
這套狀態機打穿。

**凍結要求**：同一個 launchd `Label` 的 lifecycle mutation（install／remove）
必須**序列化**。

- 序列化的範圍是「同一個 Label」，不是整個產品。
- 不得為它新建 daemon、broker 或第二套鎖服務；用作業系統既有的檔案鎖等
  最薄的手段即可（實作卡再定具體機制）。
- 拿不到序列權時要**明確失敗**（例如 `SCHEDULE_LIFECYCLE_BUSY`），
  **不得**排隊等到逾時後半套執行，也不得靜默跳過。

### 1.5 failure boundary：明寫不保證的部分（contract review P2）

以下**不在**本卡與實作卡的保證範圍，屬於 recovery boundary：

- **process 被 `SIGKILL`／當機**：交易階段狀態存活於呼叫之內，行程消失即
  失去，無法自動續做或回滾。
- **斷電／檔案系統層的非預期中斷**。
- **外部程式直接改動 launchd 或我們的 plist**（包含使用者手動
  `launchctl load/bootout`、編輯或刪除 plist）。

這三項的復原手段是重跑 `schedule install`（它會依 §1.1／§1.2 的四象限
重新分類當下實況並收斂），或 `schedule remove` 後重裝。

**§2 驗收第 5 項的「任何失敗路徑」僅指本卡定義的、由 launchctl 回傳值與
post-condition 組成的失敗路徑**，不含上列三項。此段存在的理由是：不寫清楚
的話，這幾項未來會被當成缺口重新開單。

## 2. 驗收

1. `bootstrap` 四種結果各有測試，**含 exit 非 0 + loaded 的 partial
   activation**：新 job 必須被清掉，舊狀態必須恢復，磁碟與 live 一致。
2. `bootout` 四種結果各有測試，含「exit 非 0 但其實已停」視為成功。
3. **任何時刻磁碟 plist 與 live job 的設定必須一致**，或明確失敗並說出
   不一致的內容。不得出現 `disk=A / live=B` 而回報成功。
4. rollback 的判斷**不得**來自 `loaded?` 的推測；測試必須能構造
   「新 job 已 live 但 bootstrap 回失敗」並證明 rollback 仍然正確。
5. 不得留下孤兒 job：任何失敗路徑結束後（**範圍見 §1.5**），`Label` 要嘛
   對應到磁碟上的 plist，要嘛完全不存在。
6. **rollback 順序**（§1.3.2）：構造「新 job 已 live 但 bootstrap 回失敗，
   且清理新 job 也失敗」，確認結果是 dirty failure、磁碟保留與 live job
   對應的定義，**且不曾出現 `disk=old / live=new` 的中間狀態**。
7. **正向 upgrade 順序**（§1.3.3）：upgrade 全路徑**不得出現
   `disk=new / live=old` 的中間狀態**。測試必須在 `bootout` 與 `bootstrap`
   的每個觀察點檢查磁碟與 live 的對應關係，而不是只看最終結果——
   split-brain window 的定義就是「中間存在過」。
   另須涵蓋：舊 job 停不掉時磁碟仍是舊版；首次安裝時
   `OLD_STOP_VERIFIED` 以「本來就沒有」通過後才發布 plist。
8. **序列化**（§1.4）：並行跑 `install`／`install`、`install`／`remove`，
   確認第二個明確失敗（`SCHEDULE_LIFECYCLE_BUSY` 之類），且結束後磁碟與
   live 一致；不得兩個都回成功。
9. **階段序列**（§1.3.1）：實作不得在 rollback 路徑上用 `loaded?` 判斷
   「現在活著的是舊的還是新的」——以靜態檢查或注入測試證明。
10. repair-01～04 的既有修法逐條對照新契約，**含發布順序**，**不符者一併改**；
   符合者註明沿用。
11. 每一項附鑑別力反證，且各情境測試互相隔離（獨立 `mktmpdir`），
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
  installer 的 activation，也不把同型教訓推廣成通用框架。§1.3.1 的階段序列
  是流程描述，**不得**據以新建 FSM engine、ledger 或 DB；§1.4 的序列化用
  作業系統既有的最薄手段，不得新建 daemon 或 broker。
- **do_not_absorb**：不吸收 Acceptance #8 的真機實證（需 Owner 明示）；
  不吸收 delivery-path 驗收（upgrade／zip／quarantine）；不吸收 §1.5 列為
  recovery boundary 的三項（crash／斷電／外部改動）。
