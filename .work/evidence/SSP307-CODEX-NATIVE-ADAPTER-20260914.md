# SSP-307 AIWR-09 Codex Native Adapter — 實作 evidence

日期：2026-09-14　branch：`cc/ssp307-codex-native-adapter`　base：`e73488d`

## Measured gap（實測，非推測）

實作前：`ai-task-card-record.yaml` 的 `lifecycle_event_to_status` 要
`start / block / unblock / submit_review / complete / cancel`；Codex 原生
session log 從沒有任何機制被驗證過會不會發出這些事件、或發出什麼別的事件。

實作方式：對本機 `~/.codex/sessions/**/*.jsonl` **全量掃描**（818 個檔，非抽樣），
只讀 `event_msg.payload.type`（受控 discriminator，非自由文字內容）：

```
task_started            9529      task_complete            9392
turn_aborted              104      thread_goal_updated        95
thread_settings_applied  4001      item_completed           60008
token_count              41642     user_message                18
agent_message               18      agent_reasoning              2
```

**先做過 15-session 抽樣，再補全量掃描才發現的落差**：抽樣完全沒看到
`thread_goal_updated`（全量僅 95 次觀測，在 818 個 session 中屬稀有事件）。
這是我在本卡實作過程中主動糾正自己的地方——如果只憑抽樣就寫契約，
分類會漏掉一個真實會發生的原生事件。

Owner 明確授權後才讀取 `~/.codex/sessions/`；只萃取事件類型名稱與出現次數，
不讀取、不轉述、不儲存任何訊息內容、工具輸出或檔案內容。

## 交付

| 檔 | 行數 | 說明 |
| --- | --- | --- |
| `規格/v0.1/codex-native-adapter.yaml` | 215 | 分類契約 |
| `scripts/validate_codex_native_adapter_contract.rb` | 288 | 薄 validator（< 400 行硬上限） |
| `規格/v0.1/fixtures/codex-native-adapter-runtime-sample.json` | — | 凍結、不含內容的真實觀測值萃取 |
| `規格/v0.1/fixtures/codex-native-adapter-{positive,negative}-fixtures.json` | 12 正例 / 23 負例 | |

## 設計要點

1. **兩邊語彙對不上，這正是本卡要解的 gap**。`task_started→start`、
   `task_complete→complete` 是乾淨 1:1；`block`／`unblock`／`submit_review`
   在 Codex 原生完全沒有對應，刻意留空不猜。`turn_aborted→cancel` 是判斷，
   不是強制對應，寫進契約的 `design_note` 供 reviewer 挑戰。
2. **Runtime probe 用凍結的內容無關萃取，不要求 reviewer 有本機 session 檔**。
   `codex-native-adapter-runtime-sample.json` 只存事件類型名稱與出現次數，
   validator 斷言這個真實觀測樣本裡的每一個事件類型都被契約分類涵蓋。
3. **仿 Hermes Adapter 的治理形狀**：optional dependency、no-org-wide-install、
   disable/rollback with side effects、`error_behavior: FAIL_LOUD`、
   同一組 forbidden authority 欄位。三個 evaluator（mapping／rollback／runtime
   sample）都是純函式。
4. **error_contract 由宣告集合機器綁定**，不是兩張手寫清單互比（SSP-302 教訓）。

## 過程中自己抓到並修正的問題（誠實記錄，非事後包裝）

1. **抽樣不夠，改全量掃描**：見上方 Measured gap，抓到 `thread_goal_updated`。
2. **兩處 YAML 結構錯誤**：`lifecycle_event_map` 與 `non_lifecycle_event_types`
   一開始把「清單/映射本體」與「rule／design_note 說明文字」放在同一層，
   YAML 解析直接報錯（"did not find expected '-' indicator"）。改成
   `{map: {...}, rule: ...}` / `{events: [...], rule: ...}` 兩層結構修正。
3. **`CODEX_MAP_TARGET_UNKNOWN` 是死碼**：設計時以為它是「run 帶了一個指向
   不存在 lifecycle key 的 mapped_to」該回傳的碼，但 `declared_target` 一律
   從已通過結構斷言的 `spec` 讀出（不是從 run 讀），所以 run 層級的輸入
   永遠無法讓這條 guard 觸發。寫負例去踩它，結果得到
   `CODEX_MAPPING_TARGET_MISMATCH` 而非預期碼——證明它不可達。
   依 SSP-291 對 `EPROFILE_ADAPTER_MAPPING_NOT_BOUND` 的同一取捨：刪除死碼，
   改由既有的結構斷言（`assert(target_lifecycle_keys.include?(target), ...)`）
   承擔，不留一個永遠踩不到的分支。
4. **guard parity 抓到 8 個真缺口**（不是誤判，是同一個 code 被多條 guard
   共用，只有其中一條被 fixture 踩到）：
   - `codex_mapping_failure`：`grants_permission`／`grants_canonical_writer`／
     forbidden-field-present 三條（都回傳 `CODEX_EXCEEDS_AUTHORITY`）、
     `core_flow_blocked_without_adapter` 一條（回傳 `CODEX_ADAPTER_MANDATORY`）。
   - `codex_rollback_failure`：`disable_switch != true`／
     `fallback != CORE_FLOW_DIRECT`／`side_effects` 非陣列或空陣列三條
     （都回傳 `CODEX_ROLLBACK_MISSING_FIELD`）。
   全部補上對應負例後轉全紅。
5. **`is_a?(Hash)` 的型別 guard 一開始用字串當反例測不出來**：
   `"not-an-object"["disable_switch"]` 在 Ruby 是 substring 查詢會回傳 `nil`，
   不會拋例外，所以下一條 guard（`disable_switch == true` 的檢查）會用同一個
   code 兜底，parity 顯示 GREEN(bad)——但這不是漏洞，是兩條 guard 剛好對同一
   輸入給出相同結論。換成 `nil` 當反例（`nil["disable_switch"]` 會拋
   `NoMethodError`）才讓型別 guard 本身變成不可或缺，parity 轉紅（exception 型）。

## 驗證

### Runtime probe（本卡核心主張）

`codex_runtime_sample_failure` 對真實觀測樣本的每個事件類型求值，
全部落在 `lifecycle_event_map` 或 `non_lifecycle_event_types` 其中之一。
guard parity：中和該函式唯一的 guard → **1 RED / 0 GREEN**。

### Enforcement parity（三個 evaluator，逐 guard）

| evaluator | 結果 |
| --- | --- |
| `codex_mapping_failure`（15 條 guard） | **15 RED / 0 GREEN**（assertion 14 / exception 1） |
| `codex_rollback_failure`（6 條 guard） | **6 RED / 0 GREEN**（assertion 5 / exception 1） |
| `codex_runtime_sample_failure`（1 條 guard） | **1 RED / 0 GREEN** |

備份還原一律用 `cp`，未使用 `git checkout --`。

### 結構／跨契約 probe（6 條）

| # | 動作 | 結果 |
| --- | --- | --- |
| P1 | `lifecycle_event_map` 指向不存在的 lifecycle key | RED（結構斷言，死碼移除後改由此攔） |
| P2 | `error_contract` 改名一個 code，evaluator 未同步 | RED |
| P3 | `non_lifecycle_event_types` 與 `lifecycle_event_map` 重疊 | RED |
| P4 | 上游 `lifecycle_event_to_status` 移除 `cancel` | RED |
| P5 | runtime sample 多一個真實觀測到但契約未分類的事件類型 | RED |

**5 RED / 0 GREEN。** 所有 probe 後，`git diff --name-only` 對
`ai-task-card-record.yaml`／`codex-native-adapter-runtime-sample.json` 皆為空。

### Fixture 覆蓋

- 正例：`lifecycle_event_map` 三個條目、`non_lifecycle_event_types` 七個條目、
  `DISABLED` 一例、rollback 一例、runtime_sample 一例，共 12 例。
- 負例：mapping 16 例、rollback 6 例、runtime_sample 1 例，共 23 例；
  逐案對應唯一 `expected_failure_code`，且每個可回傳 code 至少一例（見上方
  guard parity 全紅）。

### Gate

```
ruby scripts/validate_*.rb                     → 22 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
```

檔案大小：validator 288 行、契約 215 行。

## 已知取捨（請 reviewer 特別看）

1. **`turn_aborted → cancel` 是判斷，不是強制對應。** 見 Root question
   段落與契約 `lifecycle_event_map.design_note`。若 reviewer 認為
   aborted 更接近 `block`（可恢復）而非 `cancel`（終態），這是可討論的
   設計點，不是缺陷。
2. **`block`／`unblock`／`submit_review` 永久缺席於 `lifecycle_event_map`。**
   這不是遺漏——Codex 原生 session 事件裡沒有任何東西對應這三個 AIWR 構造。
   若未來 Codex 產品面新增對應能力，契約需要新增條目，屆時
   `measured_native_vocabulary` 的全量掃描會重新抓到新事件類型並強制分類。
3. **Runtime probe 的證據是凍結快照，不是即時連線。** `codex-native-adapter-
   runtime-sample.json` 是 2026-09-14 對當下 818 個 session 的一次性掃描結果，
   不會隨本機新 session 自動更新。這符合本卡範圍（不做 event bus／監聽器），
   但代表這份 evidence 有時效性——若要長期維護，需要一個刷新流程，
   本卡不處理（屬 `SSP-309`／`SSP-310` 範疇）。
