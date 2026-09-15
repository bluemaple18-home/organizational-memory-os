---
id: SSP310-PILOT-RUNTIME-HOOK-20260915
status: NO_GO_REPAIRED_01_AWAITING_TARGETED_REREVIEW
type: implementation
tier: T2
jira: SSP-310 (AIWR-12) — 既有票，非新開
depends_on: SSP-307/308/309 (ACCEPTED_GO) / NATIVE-ADAPTERS-CORRELATION-CLOSEOUT (ACCEPTED_GO)
owner_authorization: >-
  2026-09-15，互動對話中明示核准跨越 FORBIDDEN_BY_DEFAULT 的
  new writer/runtime：「可以啊 你隔離一個環境 做這件事 不要跟其他的規則
  打架」。核准範圍＝本卡定義的最小 footprint（見下）。
---

# SSP-310／AIWR-12 — 最小真實 runtime hook（PM pilot 前置）

👉 [假設與目標確認]
- 目標：`SSP-307/308/309` 全是紙上契約 + validator，這條線目前沒有任何
  真的會被 Claude Code 執行的程式。發現這件事後（`claude-code-native-
  adapter.yaml` 自己的 `hard_stops` 明寫 "no live hook registration /
  listener implementation here"），Owner 決定：PM pilot 前先建一支最小
  的真實 hook script，且要隔離環境、不跟其他規則打架。
- 邊界：**只在本 worktree／branch 範圍內**做這件事，不動使用者的全域
  `~/.claude/settings.json`，只用 Claude Code 的 project-level
  `.claude/settings.json`（跟著這個 repo 的路徑走，不影響其他專案／其他
  worktree）。
- 驗收：見 Acceptance。

## 為什麼這是 T2、需要 Owner 明示核准

`~/.claude/CLAUDE.md` 的 `FORBIDDEN_BY_DEFAULT` 明寫
`new ledger/registry/FSM/DB/writer/runtime` 預設禁止；`PRODUCT_FIT_
TRIGGER` 明列 `runtime` 這一項——這支腳本是本專案第一支真的會被 Claude
Code 呼叫、真的會寫東西的程式，不是延伸既有 runtime。已在對話中明確提案
最小 footprint（見下）並取得 Owner 核准，見上方 `owner_authorization`。

## 最小 footprint 設計（核准的範圍，不可自行擴大）

1. **只在這個 worktree 生效**：`.claude/settings.json` 是 project-level
   （用 `${CLAUDE_PROJECT_DIR}` 組路徑），不動全域設定。
2. **只接兩個事件**：`UserPromptSubmit`／`Stop`（跟契約範圍一致，兩個
   都是「per turn」、有 `no matcher support`）。
3. **不建新的儲存系統**：分類結果 append 進本 repo 既有慣例下的一個
   JSONL 檔（`.work/evidence/ssp310-pilot-runtime-log.jsonl`），純
   append-only，不是資料庫／registry／FSM。
4. **不寫任何權威來源**：不碰 canonical store，不做
   publish/transaction/tag/push（跟兩份 Adapter 契約
   `grants_canonical_writer: false` 一致）。`adapter_output_ref` 是自我
   指向本地 evidence 行的 pilot-only URN，不是真的 canonical 參照。
5. **不記錄任何 prompt／回覆內容**：只記分類 metadata
   （`native_event_type / mapped_to / native_correlation_ref
   (=prompt_id) / stop_hook_active / outcome / occurred_at`），不觸碰
   `transcript_path` 的內容、不讀 `prompt`／`last_assistant_message`
   欄位的值本身（只用其存在與否判斷，不落地文字）。
6. **絕不阻擋使用者的正常對話**：exit code 永遠 0，stdout 永遠空
   （Claude Code 文件明寫 `UserPromptSubmit` 的 stdout 會被當成 context
   插入對話——絕對不能印任何東西），任何內部錯誤 fail-open（不影響
   session）但寫進本地 debug log fail-loud（自己看得到，不影響使用者）。
7. **一鍵可關**：拿掉 `.claude/settings.json` 裡的 hooks 區塊即完全停用，
   沒有殘留狀態、沒有背景 process。

## Stop condition

如果驗證過程發現任一步無法在不擴大 footprint 的情況下做到（例如 Claude
Code 版本行為與文件不符），停下回報 Owner，不擅自擴大範圍去湊合。

## Acceptance

1. 協定層 dry-run（模擬真實 stdin JSON，逐一驗證，見 evidence）：
   - `UserPromptSubmit` → 正確寫出 `outcome=MAPPED, mapped_to=start`。
   - `Stop`（`stop_hook_active` 缺席／`false`）→
     `outcome=MAPPED, mapped_to=submit_review`。
   - `Stop`（`stop_hook_active=true`）→ **不** `MAPPED` 到
     `submit_review`（FP-2-A 語意，不可誤判為終態）。
   - 未知／格式錯誤 stdin → fail-open（exit 0、stdout 空），debug log
     記下原因。
2. stdout 在所有情況下都是空字串（避免污染真實對話 context）。
3. exit code 在所有情況下都是 0。
4. 只 append 到指定的本地 JSONL 檔，沒有任何網路呼叫、沒有寫入本 repo
   `.work/evidence/` 以外的任何路徑。
5. 移除 `.claude/settings.json` 的 hooks 區塊後，後續事件不再產生任何
   log——驗證「一鍵可關」。
6. `git diff --check` clean；新增檔案都在本 worktree 範圍內。

## Evidence

`.work/evidence/SSP310-PILOT-RUNTIME-HOOK-20260915.md`
`.work/evidence/SSP310-PILOT-RUNTIME-HOOK-REPAIR-01-20260915.md`

## 大 review 記錄

- `fc98c82`：NO_GO，P1×2（committed `.claude/settings.json` 其實是
  shared project settings，不是 worktree-only；debug log 透過
  `e.message` 洩漏 stdin 內容） + P2×1（dry-run 沒有驗證真的符合既有
  contract，reviewer 重放發現兩個假陽性）。
- repair-01：`.claude/settings.json` 改名 `.claude/settings.pilot.json`，
  改用 `claude --settings` 明示啟用；debug log 只記穩定 class/reason
  code，不再有任何 stdin 衍生文字；`classify` 改成只有確定合法的情況才
  寫 record，其餘一律不寫。用機械抽取的真實 evaluator 函式重放修復後
  寫出的 3 筆 record，全部 `VALID (nil)`。
