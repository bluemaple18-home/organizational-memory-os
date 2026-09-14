# SSP-308 AIWR-10 Claude Code Native Adapter — 實作 evidence

日期：2026-09-14　branch：`cc/ssp308-claude-code-native-adapter`　base：`9a6fd1c`

## 研究：兩種 native event 來源，選擇有 Owner 裁決記錄

先讀了 Claude Code 自己的 session transcript（`~/.claude/projects/**/*.jsonl`，
Owner 授權後、9 個檔、只讀頂層 `type` 與 `system.subtype`，不讀內容）：

```
頂層 type：assistant/user/system/attachment/mode/... （UI 訊息粒度，非任務生命週期）
system.subtype：turn_duration(183) stop_hook_summary(156) away_summary(87)
                informational(3) compact_boundary(3)
```

沒有乾淨的「start」訊號——這條路會重演 SSP-307 F-01 那種「設計時就先天缺一半」
的問題。改用 Claude Code 公開文件記載的 9 個 hook 事件名稱（封閉集合），
並經 `AskUserQuestion` 由 Owner 明確選定「先寫靜態分類契約，不做 runtime
probe」。

## 交付

| 檔 | 行數 | 說明 |
| --- | --- | --- |
| `規格/v0.1/claude-code-native-adapter.yaml` | 224 | 分類契約 |
| `scripts/validate_claude_code_native_adapter_contract.rb` | 263 | 薄 validator（< 400 行硬上限） |
| `規格/v0.1/fixtures/claude-code-native-adapter-{positive,negative}-fixtures.json` | 11 正例 / 22 負例 | |
| `.work/CARD-SSP308-RUNTIME-PROBE-BACKLOG-20260914.md` | — | 後續 runtime probe 延後卡 |

## 設計：SSP-307 三個 finding 的教訓，一開始就避開

repo #307 走了大 review NO_GO → repair-01 → repair-02 三輪才收斂。這張卡
從設計階段就直接套用那三個教訓，不是事後修：

1. **`Stop → submit_review`，不是 `complete`。** SSP307-F-01 已經證明
   `ai-task-card-record.yaml` 沒有 `OPEN → DONE` 邊。`Stop`（agent 完成
   回應）映射到 `complete` 會一律產生 `HOOK_ILLEGAL_TRANSITION`；映射到
   `submit_review`（`OPEN → IN_REVIEW`）合法。
2. **`SessionEnd` 留在 non-lifecycle，不猜終態。** SSP307-F-02 已經證明
   把可能可恢復的事件映射到 `cancel`（終態）會永久關死 Work Record。
   `SessionEnd` 有多種觸發原因，可恢復性不明，靜態契約無法區分，故不猜。
3. **`error_contract` 從第一版就綁 AST 模組。** SSP307-F-03 的手寫清單
   互比問題完全沒有重演的機會——`scripts/lib/loop_return_contract.rb`
   （SSP-302 建立、SSP-307 repair-01 沿用）從一開始就是兩個 evaluator
   的完整性來源。

（SSP307-F-04 的「雙向相等」教訓本卡沒有對應場景——本輪沒有
`runtime_sample` 這個第二份 evidence 來源需要互相綁定，那是延後卡的範疇；
`documented_native_vocabulary.hook_events` 與 `classified` 的比對本身
用的是 `sorted_set(...) == sorted_set(...)`，天生就是雙向的。）

## 驗證

### 首次執行即 PASS

`ruby scripts/validate_claude_code_native_adapter_contract.rb` 第一次跑就綠——
因為 fixture 覆蓋是照著 SSP-307 guard parity 最終版本的模式先寫好的，
不是先寫最小 fixture 再被 probe 逼著補。

### Guard parity（兩個 evaluator，逐 guard）

| evaluator | 結果 |
| --- | --- |
| `claude_code_mapping_failure`（15 條） | **15 RED / 0 GREEN**（assertion 14 / exception 1） |
| `claude_code_rollback_failure`（6 條） | **6 RED / 0 GREEN**（assertion 5 / exception 1） |

**21/21，第一輪 probe 就全紅，沒有任何 GREEN(bad)。**

### 結構／跨契約 probe（5 條）

| # | 動作 | 結果 |
| --- | --- | --- |
| P1 | `lifecycle_event_map` 指向不存在的 lifecycle key | RED |
| P2 | `error_contract` 改名一個 code，evaluator 未同步 | RED |
| P3 | `non_lifecycle_event_types` 與 `lifecycle_event_map` 重疊 | RED |
| P4 | 上游 `lifecycle_event_to_status` 移除 `submit_review` | RED |
| P5 | `hook_events` 文件清單多一個未分類的事件（完整性斷言） | RED |

**5 RED / 0 GREEN。** 所有 probe 後上游檔案 `git diff --name-only` 為空。

### Gate

```
ruby scripts/validate_*.rb                     → 23 PASS / 0 FAIL
validate_cc_cross_layer_contract.py            → PASS
validate_document_adapter_mapping_instances.py → PASS
validate_jira_adapter_mapping_instances.py     → PASS
validate_std_schema_engine.py                  → PASS
git diff --check                               → clean
```

檔案大小：validator 263 行、契約 224 行。

## 已知取捨（請 reviewer 特別看）

1. **本輪沒有 runtime probe。** 完整性驗證對照公開文件的封閉集合，不是
   即時掃描的真實語料。契約 `scope_reduction_from_ssp307` 區塊記錄了
   Owner 的裁決與理由。若 reviewer 認為文件本身可能與實際行為不一致
   （例如未來新增第 10 個 hook 而文件未同步更新），這是本卡承認的殘餘
   風險，由延後卡的 runtime probe 補上。
2. **`SessionEnd` 的 `reason` 欄位分布完全未知。** 若之後 runtime probe
   發現某些 `reason` 值確實不可恢復，`lifecycle_event_map` 可能需要拆分
   `SessionEnd` 成更細的 native_event_type，那是延後卡的範疇，本卡不猜。
3. **模組名稱 `loop_return_contract` 現在有三個消費者**（`ai-work-record-loop`
   validator、`codex-native-adapter` validator、本卡），名稱仍然承襲最初
   SSP-302 的命名。這是累積的技術債，不在本卡處理（跨越三條已驗收／
   本卡的 review line，rename 需要一次單獨的 housekeeping 卡）。
