---
id: SSP307-CODEX-NATIVE-ADAPTER-20260914
status: NO_GO_REPAIRED_01_AWAITING_TARGETED_REREVIEW
type: implementation
jira: SSP-307（AIWR-09 Codex Native Adapter／Runtime Probe）
lane: B
tier: T1
---

# AIWR-09 Codex Native Adapter／Runtime Probe（SSP-307）

👉 [假設與目標確認]
- 目標：把 Codex CLI／app-server 真實會發出的 session 事件類型，分類成
  「對應既有 Hook 契約接受的一個 lifecycle_events 項目」或「明確的非生命週期事件」，
  並用**真實觀測到的 runtime evidence**（不只是人造 fixture）證明這個分類窮盡。
- 邊界：不做 connector、不做 event bus、不做 always-on 監聽器、不取得 AIWR
  `complete`／Personal Memory acceptance／canonical writer authority；只讀
  Codex session log 的 `event_msg.payload.type`（受控詞彙），不讀取／不儲存
  任何訊息內容、工具輸出或檔案內容。
- 驗收：見 Acceptance。

## Root question

Codex 自己真實會發出的原生事件，與既有 AIWR seam（`ai-task-card-record.yaml`
的 `lifecycle_event_to_status`）要的事件，語彙對不上；這個落差要怎麼變成
可證偽、且以真實 runtime 資料驗證過的契約？

## Measured facts（實測，非推測）

對本機 `~/.codex/sessions/**/*.jsonl` **全量掃描**（818 個 session，不是抽樣），
只讀 `event_msg.payload.type` 這個受控 discriminator 欄位，未讀取／未儲存任何
訊息內容、工具輸出或檔案內容：

```
task_started            9529
task_complete            9392
turn_aborted               104
thread_goal_updated         95
thread_settings_applied   4001
item_completed           60008
token_count              41642
user_message                18
agent_message                18
agent_reasoning               2
```

`ai-task-card-record.yaml` 的 `lifecycle_event_to_status`：
`start / block / unblock / submit_review / complete / cancel`。

兩邊對不上：Codex 原生完全沒有 `block`／`unblock`／`submit_review` 的對應事件
（那些是 AIWR／task-card 的構造，不是 Codex session 會發的東西）。

## 設計決策（請 reviewer 挑戰）

- `task_started → start`、`task_complete → complete`：乾淨 1:1，高頻觀測（各 9000+ 次）。
- `turn_aborted → cancel`：**判斷，非強制對應**。一個未完成就結束的 turn，
  語意上比較接近「取消」而非「封鎖」（block 隱含仍待處理／可恢復；
  aborted 是終態但未完成）。104 次觀測，非零但稀有。
- `block`／`unblock`／`submit_review` 在 `lifecycle_event_map` 中刻意留空，
  不猜測任何對應。
- 其餘 7 種真實高頻事件（`item_completed` 60008 次、`token_count` 41642 次等）
  明確列為 `non_lifecycle_event_types`——「已知且刻意排除」與「未知」的差別，
  正是這張契約要建立的東西。

## Traces to

- `文件/待辦重整.md` §十「AIWR 平台落地 Lane」
- `文件/未決問題與已定裁決.md`（Owner 2026-09-10 重排）
- Requirement ID：`AIWR09-S01`

## Dependencies / Blockers / Current frontier

- Dependencies：`SSP-301`（Hook）／`SSP-304`（Hermes Adapter 模式）已完成。
- Blockers：無。
- Current frontier：`AIWR09-S01`。

## Scope

- 新 `規格/v0.1/codex-native-adapter.yaml`：分類契約，仿 Hermes Adapter 的
  optional-dependency／no-org-wide-install／disable-rollback／error-contract 模式。
- 新 `scripts/validate_codex_native_adapter_contract.rb`：三個純函式 evaluator
  （mapping run、rollback、runtime sample 完整性）+ 結構斷言。
- 新 `規格/v0.1/fixtures/codex-native-adapter-runtime-sample.json`：**凍結的、
  不含內容的**真實觀測值萃取（事件類型名稱 + 出現次數，無訊息文字／無工具輸出／
  無檔案路徑）——這是「runtime probe」的可重現證據，reviewer 不需要本機
  `~/.codex/sessions` 就能驗證分類完整性。
- 新正負例 fixtures。

## Constraints

- 不新增 connector／event bus／always-on 監聽器／registry／FSM／DB。
- 不取得 acceptance／permission／canonical writer 權威（同 Hermes Adapter 邊界）。
- 不重定義 `ai-task-card-record.yaml` 或 `ai-work-record-hook.yaml`。
- validator `< 400` 行。
- 不讀取／不儲存任何 session 訊息內容、工具輸出或檔案內容——只讀
  `event_msg.payload.type` 這個受控欄位。

## Product fit

- Measured gap：Codex 原生事件與既有 Hook 契約要的 lifecycle_events 語彙完全對不上，
  且過去沒有任何機制驗證過這件事——這是全量掃描才發現的（15-session 抽樣漏掉了
  `thread_goal_updated`）。
- Why not less：沒有這張契約，Codex 原生事件永遠無法安全餵進既有 AIWR seam；
  任何整合都是憑空猜測映射，且無法對真實行為證偽。
- Why not more：不做 event bus、不做即時監聽器、不取得任何超出「lifecycle
  evidence」的權威——`SSP-309`（跨平台一致性）與 `SSP-310`（PM pilot）才會
  真正接上 runtime，本卡只建立分類契約。
- Do not absorb：Codex CLI／app-server 本身、任何 connector SDK、Job Engine。
- Rollback：新 yaml + validator + fixtures，不連任何 runtime，可單獨 revert。

## Acceptance

1. `lifecycle_event_map` 與 `non_lifecycle_event_types` 合起來剛好等於
   `measured_native_vocabulary.observed_event_types` 的 keys；兩者不重疊。
2. runtime sample fixture（真實觀測、凍結、不含內容）中的每個事件類型都被
   分類契約涵蓋；缺一即 `CODEX_RUNTIME_SAMPLE_UNCLASSIFIED`。
3. `mapping_run` 三個 evaluator（mapping／rollback／runtime sample）皆為純函式，
   guard-level enforcement parity 全紅（中和任一 guard → gate 轉紅）。
4. `error_contract` 與 evaluator 實際可回傳集合機器綁定（沿用 SSP-302 的教訓，
   不用兩張手寫清單互比）。
5. 每個 lifecycle_event_map 條目、每個 non_lifecycle_event_types 條目至少一個正例。
6. 全部既有 validator + schema engine + cross-layer + `git diff --check` 全 PASS。

## Stop conditions

- 若需要實際訂閱 Codex 原生事件（而非分類靜態記錄的事件類型）才能完成驗收，停，
  回 Owner——那是 `SSP-309`／`SSP-310` 的範疇，不是本卡。
- 若上游 `lifecycle_event_to_status` 需要新增 key 才能表達 Codex 原生行為，停，
  回 Owner——本卡不重定義既有 seam。

## Likely files

- `規格/v0.1/codex-native-adapter.yaml`（新）
- `scripts/validate_codex_native_adapter_contract.rb`（新）
- `規格/v0.1/fixtures/codex-native-adapter-{positive,negative,runtime-sample}.json`（新）
- `文件/待辦重整.md`
- `.work/evidence/SSP307-CODEX-NATIVE-ADAPTER-20260914.md`

## Evidence

`.work/evidence/SSP307-CODEX-NATIVE-ADAPTER-20260914.md`
