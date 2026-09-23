---
id: WEEKLY-UPLOAD-ACCOUNTABILITY-PREP-20260923
status: SPEC_FROZEN_AWAITING_FREEZE_C_REVIEW
freeze_c_review_round_1: NO_GO（2026-09-23，P1×2：驗收 14 誤稱 evaluator 會擋合法 ref 欄位／attempt_kind 只看歷史會標錯；P2×2：C-2 應消費既有 seam／C-3 的 COMPLETE 語意是新政策非契約）→ 已補
freeze_c_review_round_2: NO_GO（2026-09-23，P1×1：C-7 四格與自身散文衝突且未列未到期週期；P2×1：§3.3 開頭過度宣稱「全部來自既有契約」）→ 已補
freeze_c_review_round_3: NO_GO（2026-09-23，P1×1：驗收 14 未鎖 LATE 分叉；P2×1：C-7 整個 phase classifier 未標為產品推導）→ 已補
freeze_c_review_round_4: NO_GO（2026-09-23，P1×2：attempt 矩陣仍是人工列舉／§3.4 清單本身漏 T-8、T-9；P2×1：索引規則不可機器自驗）
  → **不做第五輪 patch**。四輪同一根因（手工列舉的第二份 authority），依
  「同一 blocker 第 3 次失敗即停」重構 Freeze C 為
  Rule → Generated Coverage → Builder → Existing Evaluator
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
- `[T-9 PRODUCT]` `scheduled_anchor_at` 必須由 `--period` 的 anchor 推導。
  上游只要求它是非空字串；跨 attempt 真正比對一致性的只有
  `scheduled_review_period_start`。

#### 3.3.2 `attempt_kind` 的唯一決策函式

**這是 canonical，不得再有第二份描述。** 矩陣與 Acceptance 都由它導出。

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

| phase | 範圍 |
|---|---|
| `BEFORE` | `now < scheduled_anchor_at` |
| `SCHEDULED` | anchor 起，至該 anchor **當日結束** |
| `CATCH_UP` | 當日之後，至 `catch_up_deadline_at` 前（週六日屬此段） |
| `LATE` | `now >= catch_up_deadline_at` |

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

      這樣日後新增一個 phase，矩陣會**立刻**指出有格子沒定義——而不是等
      reviewer 找出第 21 個故事。前四輪就是敗在「取樣」而不是「窮舉」。
    - **`[T-n]` 每一條都必須有 guard 與 test**，並在實作 review 附上
      §3.4 的 `T-ID → rule location → guard → test` 對照表。
      T-1～T-9 一條都不能少。
    - **`[UPSTREAM]` 的條目不得被複製成產品自己的判斷**——
      分類詞彙必須消費 `Contract.disposition_categories`；改動 upstream 的
      集合後產品接受的集合必須跟著變（此為證明沒有第二份詞彙的反證）。
    - `review done` 漏掉任一待辦項目 → fail closed（T-3）。
    - `review skip` 的空 selected／dispositions 能通過 evaluator（T-8）。
    - 跨週補做時 `scheduled_review_period_start` 與 `scheduled_anchor_at`
      取自 `--period` 的 anchor（T-9），不得觸發
      `WRC_PERIOD_START_INCONSISTENT`。
    - `LATE` 階段仍可 `review done`（Owner 裁決），不得自動判成 `SKIPPED`。
15. 每項附鑑別力反證。

## 7. Minimum Sufficient

- **why_not_less**：少了預期序列就算不出差集，漏掉的週仍是空白；少了
  `review skip`／`review done`，實務上不會有人留紀錄，可管理性是空談。
- **why_not_more**：不做跨人、不做公司端、不做 dashboard、不建第二個 DB、
  不改 SSP-323 的 catch-up 語意。
- **do_not_absorb**：不吸收 SSP-324 的提交面與隱私裁決；不吸收國定假日
  行事曆（每個人放假不同，產品不該內建一份）。
