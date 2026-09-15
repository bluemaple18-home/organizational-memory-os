# SSP-310 repair-01 — evidence

回應 `fc98c82` 大 review NO_GO（P1×2 + P2×1）。同一條 review line，只收這三筆。

## F-01（P1）：`.claude/settings.json` 是 shared project settings

用 WebFetch 查證 `https://code.claude.com/docs/en/settings`：precedence
表明寫 `.claude/settings.json` = "Shared project... Everyone in the
project"，`claude --settings <file>` = "Command line... You, this
session"。屬實——committed 後會跟著 repo 分享給任何取得這個 repo 的人，
不是只在 pilot worktree 生效。

修法：把 hooks 設定從 `.claude/settings.json`（會被自動載入的檔名）改名
成 `.claude/settings.pilot.json`（Claude Code 不會自動發現的檔名），
啟用方式改成每次明示 `claude --settings .claude/settings.pilot.json`
——即使這個檔案被 commit，也不會自動生效，需要人主動打那個 flag 才會
啟用，真正做到 opt-in、只在這次 pilot session 生效。

## F-02（P1）：debug log 透過 `e.message` 洩漏 stdin 內容

重放 reviewer 給的案例（malformed JSON 內含 `SECRET_SSP310_REVIEW`），
確認修復前 debug log 確實會帶出 parser 吃到一半的原始輸入片段。修法：
所有 debug log 只記穩定、跟輸入內容無關的值——正常錯誤只記
`e.class.name`（如 `HOOK_ERROR_JSON_ParserError`），跳過寫入 record 只記
穩定的 skip reason code（如 `SKIPPED_MISSING_NATIVE_CORRELATION_REF`），
不再有任何路徑會把 `e.message` 或任何 stdin 衍生文字寫進 log。

## F-03（P2）：dry-run 沒有驗證真的符合既有 contract

修法：重新設計 `classify`——只有「一定會通過既有
`claude_code_mapping_failure` 語意」的情況才回傳一個 record 讓
`append_log` 寫入；其餘（未分類事件、缺 `native_correlation_ref`、
`Stop` + `stop_hook_active=true`）一律回傳 `nil`，完全不寫
`mapping_run` record，只記穩定的 skip reason 到 debug log。這是
reviewer 給的兩個選項之一（「讓 invalid/non-terminal cases fail-open
而不產生偽裝成合法 mapping_run 的 evidence」）——選這個而不是把整支既有
validator require 進來，是因為 `validate_claude_code_native_adapter_
contract.rb` 是一支會在載入時就跑完整驗證並可能 `exit 1` 的腳本，不是
單純的 library，直接 require 會有非預期的副作用；重構它成 library 又是
在改動已經 `ACCEPTED_GO` 的 SSP-308 交付物，超出本卡最小 footprint。

## 驗證：真的重放進真實 evaluator（機械抽取，非手抄）

用 Python 正則從 `scripts/validate_claude_code_native_adapter_contract.rb`
機械抽取 `claude_code_mapping_failure` 函式本體與相依常數（逐位元複製
原始碼，不是手動重打——避免這個 session 之前已經被抓過的「兩份手寫清單
互相比對」drift 風險），組成一支獨立驗證腳本，把修復後 hook 實際寫出的
3 筆 record 餵進去：

```
record 0: UserPromptSubmit/start   -> VALID (nil)
record 1: Stop/submit_review       -> VALID (nil)
record 2: Stop/submit_review       -> VALID (nil)
```

三筆全部通過真實 evaluator（回傳 `nil` = 合法）。

## 完整 dry-run（原 6 案例 + reviewer 的 2 個 adversarial case）

```
T1 UserPromptSubmit                  → exit=0 stdout_len=0 → 寫入 MAPPED/start
T2 Stop（stop_hook_active 缺席）      → exit=0 stdout_len=0 → 寫入 MAPPED/submit_review
T3 Stop（stop_hook_active=false）     → exit=0 stdout_len=0 → 寫入 MAPPED/submit_review
T4 Stop（stop_hook_active=true）      → exit=0 stdout_len=0 → 不寫入（SKIPPED_STOP_HOOK_ACTIVE_NOT_TERMINAL）
T5 未知事件                           → exit=0 stdout_len=0 → 不寫入（SKIPPED_UNCLASSIFIED_NATIVE_EVENT）
T6 malformed JSON（含 SECRET 字串）   → exit=0 stdout_len=0 → debug log 0 處出現 "SECRET"
T7 有效 JSON 但缺 prompt_id           → exit=0 stdout_len=0 → 不寫入（SKIPPED_MISSING_NATIVE_CORRELATION_REF）
```

`grep -c SECRET debug.log` → `0`（乾淨，逐字確認過，不是肉眼看）。

## Gate

```
ruby scripts/validate_*.rb（全部 24 支既有，未受影響）  → PASS
git diff --check                                        → clean
git status --short                                       → 只有
  .claude/hooks/aiwr_pilot_hook.rb（改）、
  .claude/settings.json（刪）、.claude/settings.pilot.json（新增）
```

`validate_claude_code_native_adapter_contract.rb` 本身**逐位元未改動**
——本輪修法完全在 hook script 這一側完成。
