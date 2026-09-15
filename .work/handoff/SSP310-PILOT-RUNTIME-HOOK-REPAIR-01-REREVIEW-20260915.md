# SSP-310 repair-01 — 定點 re-review 交付包

同一條 review line。只收 `fc98c82` 的 P1×2 + P2×1。

## 鎖定

```
base                0b5f7f9
original_review     fc98c82   （NO_GO，P1=2，P2=1）
repair_commit       f04f7b1
branch              cc/ssp310-pilot-runtime-hook
```

定點 diff：`git diff fc98c82..f04f7b1`

## 逐筆收法

### F-01（P1）：`.claude/settings.json` 是 shared project settings

用你引的同一份文件（`code.claude.com/docs/en/settings`）查證屬實。改名
成 `.claude/settings.pilot.json`（Claude Code 不會自動發現的檔名），啟用
方式改成每次明示 `claude --settings .claude/settings.pilot.json`——即使
commit 了這個檔案，也需要人主動打 flag 才會生效，不會自動套用給任何取得
這個 repo 的人。

### F-02（P1）：debug log 透過 `e.message` 洩漏 stdin 內容

所有 debug log 只記穩定值：一般錯誤記 `e.class.name`
（`HOOK_ERROR_JSON_ParserError`），跳過寫入時記穩定 skip reason code
（`SKIPPED_MISSING_NATIVE_CORRELATION_REF` 等），完全移除
`e.message`。用你原本的 `SECRET_SSP310_REVIEW` 案例重放，`grep -c SECRET
debug.log` → `0`。

### F-03（P2）：dry-run 沒有驗證真的符合既有 contract

`classify` 改成只有確定合法（會通過既有 `claude_code_mapping_failure`）
的情況才回傳 record；未分類事件、缺 `native_correlation_ref`、
`Stop`+`stop_hook_active=true` 一律不寫，只記 skip reason。用 Python
正則從 `validate_claude_code_native_adapter_contract.rb` **機械抽取**
（不是手抄）`claude_code_mapping_failure` 本體與相依常數，把修復後寫出
的 3 筆 record 餵進去，全部回傳 `nil`（合法）。

## 請重播

```bash
cd <worktree>
export CLAUDE_PROJECT_DIR="$PWD"

# 你原本的兩個 adversarial case
echo '{"session_id":"s","prompt_id":"p","hook_event_name":"Stop","stop_hook_active":true}' \
  | ruby .claude/hooks/aiwr_pilot_hook.rb
echo '{"prompt":"SECRET_SSP310_REVIEW"' | ruby .claude/hooks/aiwr_pilot_hook.rb

cat .work/evidence/ssp310-pilot-runtime-log.jsonl   # 應該沒有 stop_hook_active=true 那筆
grep -c SECRET .work/evidence/ssp310-pilot-runtime-debug.log  # 應該是 0

rm -f .work/evidence/ssp310-pilot-runtime-log.jsonl .work/evidence/ssp310-pilot-runtime-debug.log
```

`validate_claude_code_native_adapter_contract.rb` 本身逐位元未改動，
`git diff` 可確認。

## Gate

```
ruby scripts/validate_*.rb（全部 24 支既有）  → PASS
git diff --check                              → clean
```

## 請只判斷

這三筆是否已關閉，不擴大範圍（真人 pilot 仍是下一步，不是本卡）。
