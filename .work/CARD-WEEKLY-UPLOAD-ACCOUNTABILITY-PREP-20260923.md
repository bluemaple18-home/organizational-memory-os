---
id: WEEKLY-UPLOAD-ACCOUNTABILITY-PREP-20260923
jira: 尚無對應 ticket，需補開一張並回填此欄
impl_review_round_1: NO_GO（2026-09-23，P1×3：T-3 只鎖單向／expected_periods 起點倒推一週／
  已安裝 cadence 未成為 review 的 authority；P2×2 另記不擋卡）→ repair-01 已收
impl_review_round_2: NO_GO（2026-09-23，P1-1／P1-2／own? 三筆 CLOSED；P1×1：P1-3 未收完，
  build_done 重新算 due queue 時沒把 cadence 傳下去）→ repair-02 改結構
status: REPAIR_02_AWAITING_REREVIEW
freeze_c_review_round_1: NO_GO（2026-09-23，P1×2：驗收 14 誤稱 evaluator 會擋合法 ref 欄位／attempt_kind 只看歷史會標錯；P2×2：C-2 應消費既有 seam／C-3 的 COMPLETE 語意是新政策非契約）→ 已補
freeze_c_review_round_2: NO_GO（2026-09-23，P1×1：C-7 四格與自身散文衝突且未列未到期週期；P2×1：§3.3 開頭過度宣稱「全部來自既有契約」）→ 已補
freeze_c_review_round_3: NO_GO（2026-09-23，P1×1：驗收 14 未鎖 LATE 分叉；P2×1：C-7 整個 phase classifier 未標為產品推導）→ 已補
freeze_c_review_round_4: NO_GO（2026-09-23，P1×2：attempt 矩陣仍是人工列舉／§3.4 清單本身漏 T-8、T-9；P2×1：索引規則不可機器自驗）
  → **不做第五輪 patch**。四輪同一根因（手工列舉的第二份 authority），依
  「同一 blocker 第 3 次失敗即停」重構 Freeze C 為
  Rule → Generated Coverage → Builder → Existing Evaluator
freeze_c_review_round_5: NO_GO（2026-09-23，重構方向獲確認；P1×1：缺 history → prior_failed_phase 的 reducer；
  P2×1：T-9 只綁 scheduled_anchor_at，應擴成兩個 cadence 欄位）→ 已補
freeze_c_review_round_6: NO_GO（2026-09-23，P1×1：composition 反證兩筆 FAILED 同屬 SCHEDULED phase，
  取第一筆與取最後一筆算出同一個值，反證不會轉紅）→ 已補
freeze_c_review_round_7: NO_GO（2026-09-23，P1×1：reducer composition 缺 empty history 與 terminal 兩個出口；
  P2×1：T-9 反證兩欄一起填錯仍會過）→ 已補，並把兩類根因各收成一條結構規則（§6.0）
freeze_c_review_round_8: NO_GO（2026-09-23，P1×1：R-1 對 phase classifier 不夠強，算錯邊界仍能命中四種輸出；
  P2×1：T-9 的 expected 未要求獨立於 production derivation）→ 本版已補
type: bounded-product-capability
priority: MVP
parent_card: CARD-PERSONAL-INBOX-WEEKLY-REVIEW-RUNTIME-20260921
related:
  - CARD-SSP295-FULL-PRODUCT-PILOT-20260921（跨人可見度屬 pilot 之後）
  - CARD-SSP324-MINIMAL-EVIDENCE-PACKAGE-20260917（公司端只收 submission package）
authority: organizational-memory-os
---

# 每週上傳的可管理性 — 本機端準備

👉 [假設與目標確認]
- **目標**：從本功能的穩定 history origin 起，讓**每一個週期都有一筆明確結果**，
  沒有無法解釋的空白。這樣日後公司端才能
  回答「這禮拜有沒有上傳／是不是本週的版本／少了哪週」。
- **邊界**：**只做本機端**。不做跨人可見度、不做公司端提交、不碰隱私契約。
- **不是**：不建 dashboard、不建第二個 DB、不改 SSP-323 的 weekly semantics。

## 1. Owner 的管理需求（原話）

> 以後到公司端要可以記錄每個人這禮拜有沒有上傳、是不是上傳本週的版本、
> 不是的話是少了哪週。我要為這個管理做準備。

以及大原則：

> 一個禮拜一定要一次，不管哪天。如果設定日期沒做，就是遞延，或者下禮拜做兩次。

## 2. 契約已經給了對的形狀（不需要新發明）

`closeout_receipt` 是 **content-free 的 pointer record**，必填欄位裡已經有
`review_period_id`、`scheduled_review_period_start`、`actual_closeout_at`、
`attempt_kind`、`final_status`、`catch_up_deadline_passed`；
而 `forbidden_fields` 明文禁止夾帶 `personal_store_snapshot`、
`weekly_work_summary` 等內容。

因此那三個管理問題**不需要看任何人的知識內容**就能回答——這正是它被設計成
pointer record 的原因。

`SKIPPED` 也已經是契約定義的終局狀態，且明文規定必須**等 catch-up 期限過了**
才能宣告，不得提前認賠。所以「怕一直遞延」的答案不是延長期限，是**讓沒做的
那一週也留下一筆明確的結果**。

## 3. 真正缺的只有一件：預期序列

目前漏掉的週是**空白**，不是「有紀錄的沒做」。沒有預期序列就算不出差集，
空白無法管理。

預期序列可由既有事實推導，**不需要新資料表**。但歷史起點不能直接用
`receipt.installed_at`：現行 installer 每次 install／upgrade 都會重寫它，若把它
當起點，升級後舊的 MISSING 週期會被靜默洗掉。

本卡凍結以下兩個實作前提：

### 3.1 Freeze A — history origin 必須跨升級穩定

- 在**既有 install receipt** 增加一個穩定欄位 `weekly_review_origin_at`；不新增
  registry／DB／ledger。
- fresh install 第一次建立時寫入當下時間；之後 reinstall／upgrade 必須原樣保留，
  不得用新的 `installed_at` 覆蓋。
- 舊版 receipt 尚無此欄位時，第一次升級採用該 receipt 現有的
  `installed_at` 作 migration origin。這只是「目前仍可證明的最早起點」，
  **origin 之前的週期視為 unknown，不得倒推成 MISSING**。
- rollback／再次 upgrade 不得讓 origin 往後移；驗收必須鎖住這件事。

因此預期序列改為：

```text
穩定起點（receipt.weekly_review_origin_at）
  → 每個 ISO 週一個 period（anchor 由使用者設定）
  → 對照 closeouts 實際有的 review_period_id
  → 差集 ＝「少了哪週」
```

與 `review due` 同一個做法：projection，不落地。

### 3.2 Freeze B — done／skip 必須明確指定週期

`review done` 與 `review skip` **不得靠「今天」猜要關哪一週**。missed period 可以
在下一週補做，而同一週也可能同時處理「上一週 catch-up + 本週 current」；若沒有
明確 target，兩筆 closeout 會無法區分。

CLI 固定採人類可輸入的 ISO week：

```text
review done --period 2026-W38
review skip --period 2026-W38
```

CLI 只負責把 `2026-W38` 正規化成既有
`urn:omos:personal-memory:review-period:2026-W38`，並依該週的 anchor 產生既有
closeout 所需 cadence 欄位；**最後仍必須走 `Runtime.commit_closeout` 與既有
`weekly_closeout_history` evaluator**。CLI 不得重寫第二份 SKIPPED／terminal／
idempotency 規則。

缺 `--period` 必須 fail closed，不提供會在有多個 open period 時改變含義的
「自動猜本週」捷徑。`review history` 要直接顯示可複製的 `YYYY-Www`。

### 3.3 Freeze C — `review done` / `review skip` 的 deterministic adapter

**第四輪 review 後重構。** 前四輪一直爆，不是因為 Freeze C 難，而是因為中間
長出了「故事案例、集中清單、散文解釋、Acceptance 案例」幾份半重複的 authority
——每多一份，就會有一份忘記更新。

本節改用一條標準：

> **Normative rule 只存在一次；矩陣、索引、Acceptance 都從它導出或綁回它。**

這與 launchd lifecycle 最後收斂成單一 `bootstrap_and_verify` /
`bootout_and_verify` 是同一種解法。

#### 3.3.0 四層 authority，不得互相冒充

| 層 | Authority | 本卡可不可以動 |
|---|---|---|
| Weekly lifecycle 合法性 | 既有 SSP-323 evaluator | **不可** |
| Personal Inbox 額外限制 | Owner／Product | 可，但必須標 `[T-n]` |
| `attempt_kind` 怎麼推導 | deterministic derived rule（§3.3.2） | 可，且**只有一份** |
| CLI 怎麼讓人操作 | UX adapter | 可 |

**Freeze C 不發明 lifecycle。** 它只是「UX → 既有契約」的 deterministic
adapter：把人輸入的東西，翻譯成既有 evaluator 收得下的 payload。

鏈路固定為：

```text
既有 Weekly Contract
  → Owner／Product 收緊
  → 唯一的決策函式
  → closeout payload builder
  → Runtime.commit_closeout
  → 既有 weekly_closeout_history evaluator
```

#### 3.3.1 規則清單（每條自帶 authority 標記）

標記長在規則旁邊，**不另外維護第二份清單**。

- `[UPSTREAM]` `SKIPPED` 必須 `catch_up_deadline_passed == true`，否則
  `WRC_SKIPPED_BEFORE_CATCH_UP_EXHAUSTED`。
- `[UPSTREAM]` disposition 的 allowlist 是
  `category / record_ref / promotion_ref / promotion_idempotency_key`，
  **第五種**未知欄位才被擋。
- `[UPSTREAM]` `selected_item_refs` 與 `item_dispositions` 鍵集合必須相同。
- `[UPSTREAM]` item ref 必須是 PersonalMemoryCandidate 的 URN。
- `[UPSTREAM]` `NEEDS_ORG_FOLLOWUP` 不得帶 `record_ref`／`promotion_ref`。
- `[UPSTREAM]` 跨 attempt 四條：至多一次 `SCHEDULED`、
  `scheduled_review_period_start` 必須一致、至多一次 terminal、
  terminal 必須是最後一筆。
- `[UPSTREAM]` 分類詞彙的 authority 是 `Contract.disposition_categories`
  ——**必須消費它**，不得自己再讀一次 spec（`NEEDS_ORG_FOLLOWUP` 是在這個
  seam 才被併進去的，自己讀就會手抄一次）。

- `[T-1 PRODUCT]` `review done` 產生的 disposition 形狀**恰為** `{category}`。
  上游允許四欄，這是 **builder 自己保證**，沒有 evaluator 規則在守。
- `[T-2 OWNER]` `final_status` 固定 `NO_PROMOTION`。上游 `COMPLETE` 與
  `NO_PROMOTION` 都合法；本片的意思是「**這次 closeout 當下**沒有產生
  Promotion」，不是「這週沒做完」。日後 SSP-324 產生 promotion record 時
  **不得回頭改寫這筆 terminal closeout**。
- `[T-3 PRODUCT]` `review done` 的 selected 預設＝該週期 `review due` 的
  **全部**項目，缺一即 fail closed。上游只要求鍵集合相同。要延後必須明確給
  `NEEDS_ORG_FOLLOWUP`，不得靠「不選它」。
- `[T-4 PRODUCT]` `BEFORE` 階段拒絕 closeout。上游不擋提前關帳。
- `[T-5 PRODUCT]` §3.3.2 的整個 phase classifier 與決策函式。上游只檢查
  `attempt_kind` 在三個值之內與上述跨 attempt 四條，**不驗階段推導**。
- `[T-6 PRODUCT]` `weekly_review_origin_at` 與「origin 以前視為 unknown」
  （Freeze A）。上游沒有歷史起點的概念。
- `[T-7 PRODUCT]` `--period` 必填、`--anchor-weekday` 限週一～五（Freeze B
  與範圍第 1 項）。上游對 CLI 形狀無規定。
- `[T-8 PRODUCT]` `review skip` 固定送 `selected_item_refs: []` ＋
  `item_dispositions: {}`。**上游並未要求 SKIPPED 必須是空集合**，這是產品
  縮窄合法輸入。
- `[T-9 PRODUCT]` **兩個 cadence 欄位都必須由 `--period` 的 anchor 推導**：
  `scheduled_review_period_start` 與 `scheduled_anchor_at`。
  上游只要求兩者是非空字串，且跨 attempt **一致**——但**不驗它們真的對應
  該 period**：整段 history 一起填錯同一個值，evaluator 照樣放行。
  （刻意不拆成 T-10：這是**同一個 binding**，拆兩份就又回到「同一規則寫兩處」。）
- `[T-10 PRODUCT]` §3.3.2(a) 的 history reducer。上游不規定 `prior_failed_phase`
  怎麼從 history 算出來——它只驗最終送進去的 `attempt_kind` 合法。

#### 3.3.2 `attempt_kind` 的唯一決策函式

**這是 canonical，不得再有第二份描述。** 矩陣與 Acceptance 都由它導出。

##### (a) history reducer — 唯一的一份

決策函式的輸入是 `(current_phase, prior_failed_phase, has_terminal)`，但**真實
輸入是按 `attempt_seq` 排好的整段 closeout history**。中間這一步若各寫各的，
Cartesian product 可以**全綠而產品仍判錯**——例如實作取「第一個 `FAILED`」
而不是「最近一個 `FAILED`」。

因此 reducer 也只能有一份：

```text
reduce(history):                       # history 依 attempt_seq 排序
  任一筆為 terminal                    → has_terminal = true（其餘不必再算）
  history 為空                          → prior_failed_phase = none
  否則                                  → prior_failed_phase =
      **最後一筆** final_status == "FAILED" 的 actual_closeout_at 所屬 phase
```

「**最後一筆**」是這條的全部重點。取第一筆在
`SCHEDULED FAILED → RETRY FAILED → 跨進 CATCH_UP` 這種序列上就會判錯，
而那正是矩陣測不出來的地方——因為矩陣的輸入已經是 reduce 之後的值。

##### (b) 決策函式

```text
決策(current_phase, prior_failed_phase | none, has_terminal):

  has_terminal                      → REJECT（交既有 evaluator／unique index）
  current_phase == BEFORE           → REJECT [T-4]

  prior_failed_phase == none:
    current_phase == SCHEDULED      → SCHEDULED
    current_phase ∈ {CATCH_UP,LATE} → CATCH_UP

  prior_failed_phase == current_phase → RETRY

  prior_failed_phase != current_phase:
    current_phase == SCHEDULED      → SCHEDULED
    current_phase ∈ {CATCH_UP,LATE} → CATCH_UP
```

一句話：**`RETRY` 只在同一階段內成立；跨階段一律回到該階段的首次種類。**

`phase` 的定義（同屬 `[T-5]`）：

**四個 phase 一律定義成半開區間**，每個邊界都是一個**精確的瞬間**——
否則 §6.0 R-1 要求的 `b-ε / b / b+ε` 根本寫不出來（「當日結束」不是一個瞬間）。

| phase | 區間（本機時區） |
|---|---|
| `BEFORE` | `(-∞, A)` |
| `SCHEDULED` | `[A, D0)` |
| `CATCH_UP` | `[D0, C)`（週六日屬此段） |
| `LATE` | `[C, +∞)` |

三個邊界：

- **`A` = `scheduled_anchor_at`**（該 period anchor 的時刻）
- **`D0` = anchor 隔日 `00:00:00` local**（不是「當日 23:59:59」——
  取隔日零時才是精確瞬間）
- **`C` = `catch_up_deadline_at`**（下一個工作日的同一時刻）

邊界一律**左閉右開**：`b` 本身屬於**後**一個 phase。

> **實作限制**：phase classifier 必須比較**時間戳**，不得比較「小時」。
> 既有 `ReviewQueue.period_for` 用的是 `local.hour < anchor_hour`——
> **不要沿用那個寫法**。實測 15:59→W37、16:00→W38 在 anchor 邊界上剛好正確，
> 但用在 `D0` 這種零時邊界會讓 ε 測試完全失效（同一小時內的 ε 不改變結果）。

`catch_up_deadline_passed` 亦由 phase 決定：`LATE` 為 `true`，其餘 `false`。

**Owner 裁決**：`LATE` 階段**仍可** `review done`。逾期不自動判死——`SKIPPED`
是明確放棄這一期，不是逾期的自動結果；否則「下週補上週、同週做兩次」這個
原始需求會被打掉。

#### 3.3.3 輸入形狀（UX adapter 層）

```text
review done --period 2026-W38 --item <candidate-urn>=<CATEGORY> [--item ...]
review done --period 2026-W38 --dispositions FILE.json
review skip --period 2026-W38
```

CLI 只負責把 `2026-Www` 正規化成既有 URN、依該週 anchor 產生 cadence 欄位、
組 payload；**最後一律走 `Runtime.commit_closeout` 與既有 evaluator**。
CLI 不得重寫第二份 `SKIPPED`／terminal／idempotency 規則。

### 3.4 T-ID 索引（**非 normative**）

本節**沒有新語意**，漏一列不會改變產品規則——normative 的來源是 §3.3.1 的
inline 標記。這裡只是給實作 review 用的對照表。

實作 review **必須**附上這張表，每個 T-ID 都要有 guard 與 test：

```text
T-ID → rule location（§3.3.1 的哪一條）→ implementation guard → test
```

## 4. 範圍

1. **`--anchor-weekday`**（限週一～週五）。每個人自己選哪一天上傳——放假時間
   每個人不同，產品不內建行事曆。選到的那天遇到假日，既有 catch-up 會順延到
   下一個工作日。
2. **`review history`**：本機週期帳。每個 ISO 週一列，狀態為
   `COMPLETE`／`NO_PROMOTION`／`SKIPPED`／**MISSING**（從未 closeout）。
   MISSING 就是「少了哪週」的答案。
3. **`review skip`**：在 catch-up 期限過後，把該週明確記成 `SKIPPED`。
   期限未到就宣告必須**直接拒絕**（契約明文）；呼叫端必須明確給 `--period`。
4. **`review done`**：把手寫 closeout JSON 這件事變成一般人做得到的操作。
   現況是 `closeout --file FILE` 要餵一份組好的 JSON——實際上等於沒人會留紀錄，
   而沒紀錄就沒有可管理性。呼叫端同樣必須明確給 `--period`。

## 5. 明確不做（需要 Owner／契約裁決才能碰）

- **跨人可見度**：看不到別人的 Personal store 是**核心隱私邊界**
  （`EMPLOYEE_PRIVATE` / `visibility_scope: SELF_ONLY`），不是尚未實作。
- **公司端提交管道**：SSP-324 明訂「公司只收到明確 submission package，
  且不存在 reverse-access path」。要送什麼、誰能看，是那條線的決定。
- **沒做的人怎麼處置**：管理政策，不是產品行為。

本卡只保證一件事：**從 `weekly_review_origin_at` 起，每一週都能被判成 terminal
結果或 MISSING**。origin 以前沒有可證明的資料，不偽造歷史。有了這個，日後要把
週期帳做成可提交的內容，才有東西可送。

## 6. Acceptance

### 6.0 兩條結構規則（先於個別條目）

第 5～7 輪 review 的發現可歸成兩類，各出現兩次。**不等第三次**，收成規則：

#### R-1 coverage 由**函式的輸出空間**生成，不由輸入故事列舉

適用於本卡所有 deterministic function（決策函式、reducer、phase classifier）。

> 每個函式必須列出它的**完整輸出集合**，測試對**每一個輸出**都有至少一筆
> 生成的輸入命中它。
>
> **對有序輸出（phase classifier）另加 boundary coverage**：每個邊界 `b`
> 都要驗 `b-ε` / `b` / `b+ε` 三點。

「每個輸出至少命中一次」對 phase classifier **不夠**——把時間邊界整個算錯，
仍然可以命中 `BEFORE`／`SCHEDULED`／`CATCH_UP`／`LATE` 四種輸出，測試照樣
全綠。真正鎖住它的是邊界，不是輸出種類。

phase classifier 有**三個邊界**（定義見 §3.3.2 的半開區間）：`A`、`D0`、`C`，
共 9 個生成點。**每個邊界必須在卡上寫明它屬於哪一側**——不寫明的話
`b` 這一點要斷言什麼就是未定義的。

`attempt_kind` 決策函式已經這樣做（Cartesian product）。**reducer 也必須**
——它的輸出空間是三個：

| reducer 輸出 | 命中條件 |
|---|---|
| `has_terminal = true` | history 含 terminal（`FAILED* → terminal` 亦屬之） |
| `prior_failed_phase = none` | **history 為空** |
| `prior_failed_phase = <phase>` | 取 `attempt_seq` **最後一筆** `FAILED` 所屬 phase |

第 7 輪就是敗在只測了第三個出口——「矩陣全綠但空 history 算錯」的實作可以
完全通過。

（附帶更正一個錯誤前提：合法 history **不可能**出現「`FAILED` 中間夾非
`FAILED`」——`COMPLETE`／`SKIPPED`／`NO_PROMOTION` 都是 terminal，
terminal 之後不得再有任何 attempt。）

#### R-2 每個反證都必須先證明它**會**轉紅

> 反證條目必須同時寫出三件事：
> **(i)** 反轉什麼；**(ii)** 哪一條斷言轉紅；
> **(iii)** **反轉前後的輸出為什麼不同**。
>
> **寫不出 (iii) 的反證一律無效**——它只是看起來有保護。

兩次教訓：

- composition 反證用了兩筆同屬 `SCHEDULED` 的 `FAILED`，取第一筆與取最後
  一筆**算出同一個值**；
- T-9 反證只斷言「不觸發 `WRC_PERIOD_START_INCONSISTENT`」，但兩個 cadence
  欄位**一起填成同一組錯值**時 evaluator 照樣放行。

兩者都是「宣稱有保護，卻沒驗證那個保護真的會失效」。


1. `--anchor-weekday` 可設 Mon–Fri；週末一律拒絕（catch-up 以工作日定義）。
2. 改變 anchor 的那一天**不得**造成週期重複或消失——period 身分綁 ISO 週，
   需有測試鎖住，不得只靠推論。
3. anchor weekday 與 hour 同樣從已安裝 plist 讀回；兩個來源不一致即退回預設
   並顯示。
4. `review history` 由既有事實重算，**不新增資料表**；MISSING 的判定來自
   「預期序列 vs 實際 closeouts」的差集。
5. `weekly_review_origin_at` 在 reinstall／upgrade 後 byte-for-byte 維持原值；
   upgrade 前已是 MISSING 的週期，upgrade 後仍必須是 MISSING。
6. 舊版 receipt 首次遷移只從仍可證明的 `installed_at` 起算；origin 以前不得
   被 `review history` 誤報為 MISSING。
7. `review done`／`review skip` 缺 `--period` 必須拒絕；同一個自然週內要能分別
   對上一期與本期各提交一次，且兩筆 `review_period_id` 不得混淆。
8. `review skip` 在 catch-up 期限**未到**時必須被拒絕，錯誤碼明確。
9. 期限已過時 `review skip` 產生的 receipt 必須通過既有 closeout evaluator，
   `catch_up_deadline_passed` 為 true。
10. `review done` 產生的 receipt 同樣通過既有 evaluator；**不得**夾帶
   `forbidden_fields` 任何一欄。
11. 一個 `review_period_id` 至多一次 terminal closeout——沿用既有 unique index，
   需有測試證明重複提交被擋。
12. done／skip 只組 payload 並呼叫既有 `Runtime.commit_closeout`；不得在 CLI 或
    新 helper 複製 `weekly_closeout_history` 的 terminal／SKIPPED 規則。
13. 3a／3b／3c 全綠；validators 全綠；`git diff --check` clean。
14. **Freeze C**：
    - **`attempt_kind` 的 coverage 由 §3.3.2 的決策函式生成，不得手寫故事案例。**
      測試自行展開 `current_phase × prior_failed_phase(含 none)` 的
      Cartesian product，逐格斷言；`has_terminal` 與 `BEFORE` 另列。
    - **必須測 reducer → 決策函式的 composition**（T-10），不得只測決策函式。
      矩陣的輸入已經是 reduce 之後的值，所以「取第一筆 `FAILED` 而非最後一筆」
      這種錯**矩陣全綠也抓不到**。

      **coverage 同樣用生成的，不寫故事**，且依 R-1 必須命中 reducer 的
      **全部三個輸出**：

      - `prior_failed_phase = <phase>`：多筆 `FAILED` **分屬不同 phase**，
        斷言永遠取 `attempt_seq` 最後一筆；
      - `prior_failed_phase = none`：**history 為空**；
      - `has_terminal = true`：`FAILED* → terminal`，且**不得再進**
        attempt decision。

      只測第一個出口的話，「空 history 算錯」的實作會完全通過矩陣。

      > **反證必須先證明它會轉紅。** 本卡前一版寫的反證是
      > `SCHEDULED FAILED → RETRY FAILED → 跨進 CATCH_UP`——但那兩筆 `FAILED`
      > **都在 SCHEDULED phase**，取第一筆與取最後一筆算出**同一個值**，
      > 錯誤實作照樣全綠。
      >
      > 有鑑別力的最小例子是
      > `SCHEDULED FAILED → 跨進 CATCH_UP → CATCH_UP FAILED → 同一 CATCH_UP 再做`：
      > 取最後一筆得 `CATCH_UP` → `RETRY`；取第一筆得 `SCHEDULED` → `CATCH_UP`。
      >
      > 差別在於**多筆 `FAILED` 必須分屬不同 phase**——這正是生成式 coverage
      > 要涵蓋的維度，而不是再挑一個故事。

      這樣日後新增一個 phase，矩陣會**立刻**指出有格子沒定義——而不是等
      reviewer 找出第 21 個故事。前四輪就是敗在「取樣」而不是「窮舉」。
    - **`[T-n]` 每一條都必須有 guard 與 test**，並在實作 review 附上
      §3.4 的 `T-ID → rule location → guard → test` 對照表。
      T-1～T-10 一條都不能少。
    - **`[UPSTREAM]` 的條目不得被複製成產品自己的判斷**——
      分類詞彙必須消費 `Contract.disposition_categories`；改動 upstream 的
      集合後產品接受的集合必須跟著變（此為證明沒有第二份詞彙的反證）。
    - `review done` 漏掉任一待辦項目 → fail closed（T-3）。
    - `review skip` 的空 selected／dispositions 能通過 evaluator（T-8）。
    - **T-9 改驗 exact binding，不驗「沒觸發錯誤」**：直接斷言
      `scheduled_review_period_start == 該 period anchor 的日期` 且
      `scheduled_anchor_at == 該 period anchor 的時刻`。

      **expected 必須獨立於 production derivation**：用**固定 fixture**
      （硬寫的日期字串）當 oracle，**不得**呼叫產品的推導 helper 去算 expected
      ——否則 helper 整體錯一週時，兩欄會一起錯、測試仍然 PASS。

      （既有 3c 已有此前例：`"2026-W38"`／`"2026-09-18"` 都是硬寫的期望值。）

      依 R-2 的 (iii)，反證與輸出差異：把 production derivation 整體 `+1 week`，
      兩個 cadence 欄**仍彼此一致**、evaluator 仍放行，但與固定 fixture 不符
      → T-9 測試轉紅。只斷言「不觸發 `WRC_PERIOD_START_INCONSISTENT`」的版本
      在這個反證下**不會紅**。
    - `LATE` 階段仍可 `review done`（Owner 裁決），不得自動判成 `SKIPPED`。
15. 每項附鑑別力反證。

## 7. Minimum Sufficient

- **why_not_less**：少了預期序列就算不出差集，漏掉的週仍是空白；少了
  `review skip`／`review done`，實務上不會有人留紀錄，可管理性是空談。
- **why_not_more**：不做跨人、不做公司端、不做 dashboard、不建第二個 DB、
  不改 SSP-323 的 catch-up 語意。
- **do_not_absorb**：不吸收 SSP-324 的提交面與隱私裁決；不吸收國定假日
  行事曆（每個人放假不同，產品不該內建一份）。

---

## 8. 實作結果（2026-09-23）

### 8.1 T-ID → 規則位置 → guard → 測試

規範規則只寫在「規則位置」那一欄，其餘兩欄都指回它。

| T | 規則位置（唯一） | guard（實作） | 測試 | 反證 |
|---|---|---|---|---|
| T-1 | `review_ledger.rb:159` | `build_done` 只組 `{category}` | `T-1 builder 產出的 disposition 只有 category` ＋ 上游放行對照 | M11 RED |
| T-2 | `review_ledger.rb:190` | `base(..., "NO_PROMOTION", ...)` | `T-2 final_status 固定 NO_PROMOTION` ＋ 上游放行對照 | M12 RED |
| T-3 | `review_ledger.rb:174` | `missing = due_refs - given` → `REVIEW_DONE_ITEMS_INCOMPLETE` | `T-3 漏掉待辦項目 → fail closed` ＋ 上游放行對照 | M13 RED |
| T-4 | `review_ledger.rb:212` | `assert_started!`，於 `build_done`／`build_skip`／`base` **最先**呼叫 | `T-4 done/skip 在 anchor 之前拒絕` ＋ 上游放行對照 | M14 RED |
| T-5 | `review_ledger.rb:30` | `phase_of` 半開區間 | 3 邊界 × `b-ε/b/b+ε` ＝ 9 點 ＋ 四輸出命中 | M1/M2/M3 RED |
| T-6 | `installer.rb:497` | `weekly_review_origin_for(previous)` | `origin 跨升級不變`、`installed_at 每次都變`、序列從 origin 當週起算 | M17 RED、installer 變異 RED |
| T-7 | `review_queue.rb:39`（`WEEKDAY_RANGE`） | `period_for` 的 range 檢查 ＋ `schedule.rb:128` | 週四/週五同一 period、`0/6/7/-1` 全拒 | M8/M9/M10 RED |
| T-8 | `review_ledger.rb:197` | `build_skip` 固定 `[]`／`{}`，且僅限 `:late` | 空集合通過 evaluator ＋ 上游放行對照 ＋ 期限前拒絕 | M15b/M16b RED |
| T-9 | `review_ledger.rb:129`／`:233` | `period_from_iso_week` → 兩個 cadence 欄位同綁 | 固定 fixture oracle（W38→09-18、W39→09-25、週四→09-17） | M6/M7b RED |
| T-10 | `review_ledger.rb:70` | `reduce_history` 取最後一筆 `FAILED` | 三個出口逐一命中 ＋ reducer→決策 composition | M4/M5 RED |

### 8.2 §6.0 兩條結構規則的落地

- **R-1**：決策函式的 coverage 由 `current_phase × prior_failed_phase(含 nil)`
  的 Cartesian product 生成（4×5 全格），`has_terminal` 另外對全格斷言；
  reducer 三個出口逐一命中；phase classifier 另加 9 點 boundary coverage。
  測試裡沒有任何手寫故事案例。
- **R-2**：18 個反證，17 個轉紅。唯一沒轉紅的是 **M7（等價變異，非假綠）**：
  `period_from_iso_week` 把 `Date.commercial(y, w, anchor_weekday)` 寫死成
  `5` 時輸出不變——因為 `period_for` 會從給定時刻**往回走**到 anchor 星期，
  而週五是允許範圍 `1..5` 的最大值，往回走不會跨出該 ISO 週。改寫死成 `1`
  就會跨到上一週（**M7b RED**），證明這個位置確實有被測到。

  另外在寫反證的過程中發現我自己的一個假綠：`T-8 catch-up 期限前 skip 仍拒絕`
  原本把比較式當成 `actual`、第三個參數寫死 `true`，恆真。已改為取回錯碼再斷言
  （M16b 因此由 GREEN 轉 RED）。

### 8.3 驗證

- `3a 26/26`、`3b 34/34`、`3c 391/391`（本卡新增 19+14+5 ＝ 38 條）
- 六支 validator 全 PASS
- 端到端：`review history` 由 `x 2026-W38 MISSING` → `review done` →
  `v 2026-W38 NO_PROMOTION`，`attempt_kind` 回報 `CATCH_UP`
- 實作期間發現並修掉一個真 bug：`--period` 指向未來週期時回
  `REVIEW_SKIP_BEFORE_CATCH_UP_EXHAUSTED` 而非 `REVIEW_PERIOD_NOT_STARTED`
  （兩個 builder 各自先跑自己的檢查）→ 抽出 `assert_started!` 並最先呼叫

### 8.4 體積（MINIMUM_SUFFICIENT）

| 檔案 | 產品 | 測試 |
|---|---|---|
| `review_ledger.rb`（新） | +268（實碼 146／註解 90／空白 32） | — |
| `cli.rb` | +117 | — |
| `review_queue.rb` | +40 | — |
| `schedule.rb` | +40 | — |
| `installer.rb` | +17 | — |
| `conformance_3c.rb` | — | +294 |
| **合計** | **約 +482（實碼約 300）** | **+294** |

`why_not_less`：T-1..T-10 每一條都是上游 evaluator **不會擋**的產品收緊，
少一條就少一個 fail-closed 點（8.1 的「上游放行對照」欄逐條證明了這點）。
`why_not_more`：沒有新 table、新 ledger、新 FSM；合法性判定一律回呼既有
`WeeklyCloseoutHistory`，本卡只組 payload 與算期別。
`do_not_absorb`：不做公司端匯總、不做多人視圖、不做提醒推播——那些要 Owner
與契約先裁決，已列在 §5。

---

## 9. repair-01（2026-09-23）

外部 review 在 `e12ab90` 上回 NO_GO，P1×3。三筆根因互不相同（集合方向／
邊界起點／authority 來源），不是同一根因重複出現，因此走 repair 而非 Hard Stop。

| # | 問題 | 修法 | 位置 | 反證 |
|---|---|---|---|---|
| P1-1 | T-3 只算 `due_refs - given`，「少選」被擋、「多塞」沒擋。anchor 之後才建立的 Candidate 可以被寫進本期 terminal closeout | 兩個方向都鎖：另加 `given - due_refs` → `REVIEW_DONE_ITEMS_OUT_OF_SCOPE` | `review_ledger.rb` `build_done` | R1 RED |
| P1-2 | `expected_periods` 用 `period_for(origin)` 取「origin 之前最近一次 anchor」，origin 落在週二時會把安裝前那一週報成 MISSING | 第一期改成 **anchor 落在 origin 當下或之後**的那一期 | `review_ledger.rb` `expected_periods` | R2／R3 RED |
| P1-3 | `review done/history` 的 `anchor_opts` 直接跳到預設 Friday 16:00，排週三 15:00 的人會被拿週五去判階段 | authority 鏈改為 **明示 CLI > 已安裝 plist > 預設**，消費既有 `installed_anchor_*` seam，不新增設定來源 | `cli.rb` `anchor_opts` ＋ `schedule.rb` `installed_cadence` | R4／R5／R6b RED |

### 原測試為什麼沒抓到

- P1-1：`due_refs - given` 對「多塞」恆為空集合，只檢 missing 的版本對原斷言
  永遠是綠的。要暴露它必須送一筆**不在本期 queue** 的 ref。
- P1-2：原 fixture 拿「週五 anchor 本身」當 origin，`period_for(origin)` 回的
  就是同一期（相等即納入），所以「往回走一期」在那個取樣點上看不出來。
  現在改成圍住 anchor 邊界的 `b-ε／b／b+ε` 三點 ＋ 兩個一般點。
- P1-3：`schedule status` 早就從 plist 讀 anchor，但 review 這條路徑沒有消費
  同一個 seam，而原測試只驗了 `status` 那一側。

### repair-01 自己又抓到一個缺口

R6 反證（把 `own?` 歸屬判定拿掉）原本是綠的——別人的 plist 佔在我們路徑上時
會決定我們的 review cadence，而沒有任何測試釘住。已補兩條（`installed_cadence`
回 nil、`anchor_opts` 退回預設），R6b 轉紅。

### P2（另記，本輪不收）

- **P2-1**：`ReviewLedger::TERMINAL_STATUSES` 是 upstream terminal vocabulary
  的第二份抄本，應直接消費 `Contract::CloseoutHistory::TERMINAL_STATUSES`。
- **P2-2**：`schedule status` 判斷「採預設」時只看 `anchor_hour.nil?`，
  weekday 來源不一致時會靜默退回 Friday 而不揭露 drift。

### 驗證

`3a 26/26`、`3b 34/34`、`3c 407/407`（repair-01 新增 16 條）、六支 validator
全 PASS、`git diff --check` 乾淨、launchd 殘留 0。
反證 7 個，6 個直接轉紅，R6 揭露真缺口並在補測後由 R6b 轉紅。

### 體積

| 檔案 | 產品 | 測試 |
|---|---|---|
| `review_ledger.rb` | +29 | — |
| `schedule.rb` | +16 | — |
| `cli.rb` | +14 | — |
| `conformance_3c.rb` | — | +153 |
| **repair-01 合計** | **+59** | **+153** |

---

## 10. repair-02（2026-09-23）

### 判定：改結構，不再逐點補

P1-3 是**同一個 blocker 的第 2 次失敗**，而且如果照上一輪的形狀修
（「再讓一個呼叫點去讀 cadence」），第 3 輪一定會出現下一個呼叫點。
依 `same-root-cause-third-failure-hard-stop` 的判準——看**修法的形狀**而不是
finding 的標題——這一輪必須換形狀。

### 根因

cadence 是**兩個散裝 kwarg**，穿過九個呼叫點，而且**每個呼叫點各自帶預設值**：

```
period_for / due                         review_queue.rb
expected_periods / period_from_iso_week  review_ledger.rb
history / build_done                     review_ledger.rb
anchor_opts / schedule install           cli.rb
status / notify                          schedule.rb
```

忘了往下傳不會有任何錯誤，只會靜默退回週五 16:00。repair-01 的 P1-3 是
`anchor_opts` 讀對了、`build_done` 忘了傳；下一個會是誰只是時間問題。

### 修法：period 自帶 cadence

1. `period_for` 的回傳值加上 `anchor_hour` / `anchor_weekday`——
   **拿到 period 的人就拿到了 cadence**。
2. `ReviewQueue.cadence_of(period)`：缺欄位時 **raise**，不退回預設。
   靜默退回預設正是兩輪 P1-3 的成因。
3. `ReviewQueue.due_for(runtime, period, surface:)`：拿著 period 問 due 的
   唯一入口，**不收 cadence 參數**——結構上沒有傳錯的機會。
   `build_done` 改用它。
4. 機器可驗的防再發：測試掃描 `lib/**/*.rb`，任何 `ReviewQueue.due(` 呼叫點
   若既沒明示 `anchor_hour:` 也沒有 `**` splat，即判 FAIL 並要求改用 `due_for`。

### 反證

| | 變異 | 結果 |
|---|---|---|
| S1c | `build_done` 回到 repair-01 的寫法（**reviewer 的原始重播**） | RED |
| S2e | `period_for` 不再帶 `anchor_hour` | RED |
| S6c | `period_for` 不再帶 `anchor_weekday` | RED |
| S3 | `cadence_of` 缺欄位時靜默退回預設 | RED |
| S4b | `due_for` 忽略 period 的 cadence | RED |
| S5 | `anchor_opts` 跳過已安裝 cadence（repair-01 的 R4 重跑） | RED |
| S7 | 把 cadence 從 `cli.rb` 的 due 呼叫點拿掉（打掃描器本身） | RED |
| S8 | `period_for` 的 cadence 寫死成預設值（假裝有帶） | RED |

8 個全紅。

### 反證過程中修掉的測試缺陷

S1/S2/S4 第一次跑時是**崩潰**而不是轉紅——裸呼叫 `build_done` 的地方沒有
收斂例外，變異一改就讓整支測試中止。崩潰不是測試結果，所以先把 T-1/T-2/T-3/
T-8 與 repair-01 區塊的裸呼叫全部收成值（`rescue StandardError` 回錯誤字串、
後續斷言 nil-safe），再重跑才算數。

### 驗證

`3a 26/26`、`3b 34/34`、`3c 421/421`（repair-02 新增 14 條）、六支 validator
全 PASS、`git diff --check` 乾淨、launchd 殘留 0。

### 體積

| 檔案 | 產品 | 測試 |
|---|---|---|
| `review_queue.rb` | +33 | — |
| `review_ledger.rb` | +7／-4 | — |
| `conformance_3c.rb` | — | +213／-19 |
| **repair-02 合計** | **+36** | **+194** |

測試的淨增量裡有一部分是把既有裸呼叫改成可收斂的形狀（上一段），不是新斷言。
