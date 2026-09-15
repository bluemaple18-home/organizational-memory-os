# SSP-310／AIWR-12 最小 runtime hook — evidence

日期：2026-09-15　branch：`cc/ssp310-pilot-runtime-hook`　base：`0b5f7f9`

## Owner 核准

`FORBIDDEN_BY_DEFAULT` 的 `new writer/runtime` 需要明示核准。對話中提出
最小 footprint 提案後，Owner 回：「可以啊 你隔離一個環境 做這件事 不要
跟其他的規則打架」。核准範圍＝本卡定義的 7 條最小 footprint 約束（見卡片
「最小 footprint 設計」段），全部逐條落實，未擴大。

## 為什麼需要這支腳本

`SSP-307`／`SSP-308`／`SSP-309` 與更早的 Hook 契約全部是紙上契約 +
validator；`claude-code-native-adapter.yaml` 的 `hard_stops` 自己明寫
「no live hook registration / listener implementation here」。`SSP-310`
（PM pilot）需要真的有東西可以啟用，這支腳本是第一個真的會被 Claude
Code 執行的實作。

## 實作

- `.claude/hooks/aiwr_pilot_hook.rb`（Ruby，跟本 repo 其他腳本語言一致）：
  讀 stdin JSON，依 `claude-code-native-adapter.yaml` 的
  `lifecycle_event_map.map` 分類，append 一行 JSON 到本地 evidence log。
- `.claude/settings.json`：project-level hook 註冊，只接
  `UserPromptSubmit`／`Stop`，用 `${CLAUDE_PROJECT_DIR}` 組路徑（不寫死
  絕對路徑，不影響其他 worktree／專案）。

分類邏輯精確對齊契約語意：
- 不在 `lifecycle_event_map` 裡的事件 → `NOT_LIFECYCLE`。
- `Stop` 且 `stop_hook_active == true` → **不**標記 `MAPPED`／
  `submit_review`（SPEC_FREEZE FP-2-A：同一 turn 內的延續訊號不是真的
  終態），改記 `NOT_LIFECYCLE` 並附註原因。
- 其餘 → `MAPPED`，`mapped_to` 取自契約的 `lifecycle_event_map.map`。
- `native_correlation_ref` 一律用 `prompt_id`（官方文件確認的 per-turn
  correlation id）。
- 不記錄 `prompt`／`last_assistant_message` 的實際內容，只用其存在與否
  （事實上連存在與否都沒記，只記分類 metadata）。

## 協定層 dry-run（真實 stdin JSON 格式，逐案驗證）

用 Claude Code 官方文件（`https://code.claude.com/docs/en/hooks.md`）
verbatim 的 JSON schema 直接 pipe 給腳本，6 個案例：

```
T1 UserPromptSubmit                          → MAPPED / start           ✓
T2 Stop，stop_hook_active 缺席                → MAPPED / submit_review   ✓
T3 Stop，stop_hook_active=false               → MAPPED / submit_review   ✓
T4 Stop，stop_hook_active=true                → NOT_LIFECYCLE（正確不終態）✓
T5 未知事件名稱                                → NOT_LIFECYCLE            ✓
T6 損毀的 JSON（非法語法）                     → fail-open，無 crash      ✓
```

全部 6 案例：`stdout` 皆為 0 bytes（額外用 `${#raw_out}` 精確量測確認一次，
不是只憑肉眼看空白）、`exit code` 皆為 `0`。T6 的錯誤只進本地
`ssp310-pilot-runtime-debug.log`，不進 `stdout`、不影響 exit code。

## 一鍵停用驗證

把 `.claude/settings.json` 移走（模擬「拿掉 hooks 設定」），確認
`.claude/` 底下沒有任何 hooks 註冊殘留、沒有背景 process、沒有其他狀態；
還原後恢復正常。

## 測試產生的 log 已清除

Dry-run 用的是假造的 `session_id`／`prompt_id`（非真實使用者資料），
測完即刪除 `.work/evidence/ssp310-pilot-runtime-log.jsonl` 與
`-debug.log`，不把測試噪音留在 evidence 目錄裡、也不當成本卡的正式
pilot 證據。**真正的 pilot 資料**要等這支腳本合併、你在這個目錄下開一個
真實 Claude Code session、做一個真實小任務之後才會產生——那是下一步，
不是本卡範圍。

## Gate

```
ruby scripts/validate_*.rb（全部 24 支既有）  → PASS（未受影響，本卡沒改任何契約／validator）
git diff --check                              → clean
git status --short                            → 只有新增的 .claude/ 與卡片檔案
```

## 本卡明確排除（下一步，不是現在做）

- 真人真實 pilot（你在這個 worktree 下實際開一個 Claude Code session，
  做一件真的要做的小任務，讓這支腳本真的攔到真實事件）——這步驟需要你
  親自操作一次 Claude Code，我沒有辦法代你觸發。
- 把這支腳本或它的輸出接回任何 canonical store／AIWR `complete`——依然
  明確排除，跟兩份 Adapter 契約邊界一致。
