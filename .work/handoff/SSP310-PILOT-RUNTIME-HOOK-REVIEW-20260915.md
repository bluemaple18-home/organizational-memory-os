# SSP-310／AIWR-12 最小 runtime hook — 大 review 交付包

## 鎖定

```
base    0b5f7f9
review  <此次 push 的 HEAD，見下方 commit>
branch  cc/ssp310-pilot-runtime-hook
```

`git diff 0b5f7f9..<review>` 只新增：`.claude/hooks/aiwr_pilot_hook.rb`、
`.claude/settings.json`、卡片、evidence、本交付包。沒有修改任何既有契約
或 validator。

## 這張卡在做什麼、為什麼

`SSP-307/308/309` 全是紙上契約 + validator，這條線目前**沒有任何真的會
被 Claude Code 執行的程式**（`claude-code-native-adapter.yaml` 自己的
`hard_stops` 明寫這點）。`SSP-310`（PM pilot）需要真的有東西可以啟用，
所以先建這支最小的真實 hook。

**這支腳本踩到 `FORBIDDEN_BY_DEFAULT` 的 `new writer/runtime`**，已在
互動對話中取得 Owner 明示核准（見卡片 `owner_authorization`），核准範圍
＝卡片「最小 footprint 設計」段列的 7 條約束。**請把這 7 條當作本次
review 的驗收基準之一**，不是只看程式碼品質。

## 請重播

協定層 dry-run（用 Claude Code 官方文件 verbatim 的 JSON schema）：

```bash
cd <worktree>
export CLAUDE_PROJECT_DIR="$PWD"

# T1 UserPromptSubmit → 應該 append 一行 outcome=MAPPED mapped_to=start
echo '{"session_id":"s","prompt_id":"p1","hook_event_name":"UserPromptSubmit","prompt":"x"}' \
  | ruby .claude/hooks/aiwr_pilot_hook.rb

# T4 Stop + stop_hook_active=true → 不應該出現 mapped_to=submit_review
echo '{"session_id":"s","prompt_id":"p1","hook_event_name":"Stop","stop_hook_active":true}' \
  | ruby .claude/hooks/aiwr_pilot_hook.rb

# T6 壞掉的 JSON → 必須 exit 0、stdout 必須是空字串
raw=$(echo 'not json {{{' | ruby .claude/hooks/aiwr_pilot_hook.rb); echo "exit=$? stdout_len=${#raw}"

cat .work/evidence/ssp310-pilot-runtime-log.jsonl
rm -f .work/evidence/ssp310-pilot-runtime-log.jsonl .work/evidence/ssp310-pilot-runtime-debug.log  # 清掉測試噪音
```

完整 6 案例清單、每案例預期結果見
`.work/evidence/SSP310-PILOT-RUNTIME-HOOK-20260915.md`。

## 請特別檢查（安全關鍵，不是一般程式碼審查項目）

1. **stdout 是否真的永遠是空字串**——`UserPromptSubmit` 的 stdout 會被
   Claude Code 當成 context 插入真實對話，印任何東西都是污染使用者的
   真實使用經驗，這是 P0 等級的問題，不是 style 問題。
2. **exit code 是否真的在所有分支（含例外）都是 0**——非 0 會阻擋使用者
   正常操作。
3. **有沒有任何路徑會記錄 `prompt`／`last_assistant_message` 的實際
   內容**——契約只需要分類 metadata，不應該有任何內容落地。
4. **有沒有任何網路呼叫、任何寫到 `.work/evidence/` 以外路徑的行為。**
5. **`stop_hook_active=true` 時是否真的不會被標記
   `MAPPED`／`submit_review`**（FP-2-A 語意，對應既有契約的
   `CLAUDE_CODE_STOP_HOOK_ACTIVE_NOT_TERMINAL`）。
6. **移除 `.claude/settings.json` 後是否真的沒有殘留狀態／背景
   process。**

## Gate

```
ruby scripts/validate_*.rb（全部 24 支既有，未受影響）  → PASS
git diff --check                                        → clean
```

## 請只判斷

上述最小 footprint 的 7 條約束是否真的每一條都做到、有沒有安全關鍵的洞
（尤其是 stdout／exit code／內容落地三項）。不擴大範圍去要求做真人
pilot（那是下一步，需要 Owner 親自操作 Claude Code，不是本卡範圍）。最後
以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
