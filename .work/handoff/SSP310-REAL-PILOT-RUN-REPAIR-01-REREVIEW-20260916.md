# SSP-310 真人 pilot repair-01 — 定點 re-review 交付包

同一條 review line。只收 `9640514` 的那一筆 P1。

## 鎖定

```
base                75f2a28
original_review     9640514   （NO_GO，P1=1）
repair_commit       17ed917
delivery            64d01ea
branch              main
```

定點 diff：`git diff 9640514..17ed917`（只動
`.claude/settings.pilot.json` 一行）

## 收法

你指出的絕對路徑問題屬實，根因是我自己造成的：`997df68` 為了繞開
「從 `~/Documents` 底下啟動 Claude Code 會失敗」，把 command 改成指向
main 的絕對路徑，等於用 worktree 隔離換取啟動目錄自由。那個啟動問題
後來查明是 macOS TCC 擋住終端機讀「文件」資料夾（`EPERM` 被錯誤訊息
包裝成 "low max file descriptors"），Owner 給權限後已解決——**換取的
理由消失了，我卻沒回頭撤掉。**

修法：command 改回 `${CLAUDE_PROJECT_DIR}`。hook 內的 `PROJECT_DIR`
**保留** `__dir__`，讓「記錄寫在被呼叫的那份腳本旁邊」是結構性保證，
而不是靠設定檔的約定——即使日後有人再改壞 command，記錄也只跟著腳本走。

## 請重播（你原本的測試）

```bash
cd <repo>
git worktree add /tmp/iso -b tmp/iso HEAD
cd /tmp/iso && rm -f .work/evidence/ssp310-pilot-runtime-log.jsonl
CLAUDE_PROJECT_DIR=/tmp/iso ruby /tmp/iso/.claude/hooks/aiwr_pilot_hook.rb <<< \
  '{"session_id":"iso","prompt_id":"p","hook_event_name":"UserPromptSubmit"}'

cat /tmp/iso/.work/evidence/ssp310-pilot-runtime-log.jsonl   # 應有 1 筆
wc -l < <repo>/.work/evidence/ssp310-pilot-runtime-log.jsonl # 應仍為 2（未被寫入）
```

我的結果：假 worktree 得到那筆，main 維持 2 筆。展開後的 command 是
`ruby "/tmp/iso/.claude/hooks/aiwr_pilot_hook.rb"`，指向 worktree 自己。

### 另外單獨驗了 spec 隔離（你也點名的）

只改假 worktree 自己的 `claude-code-native-adapter.yaml`，拿掉
`UserPromptSubmit`，再送同一筆事件 → 該 worktree 不產生記錄
（`SKIPPED_UNCLASSIFIED_NATIVE_EVENT`），main 的契約與 log 皆未動。

## 真實 pilot 記錄完整性（請一併確認）

第一次測試時假 worktree 是從**尚未提交修正的 HEAD** 建的，拿到舊設定，
曾讓 main 的 log 多一筆測試記錄；已 `git checkout --` 還原，確認回到真實
pilot 的 2 筆（皆 session `f8b7146e-...`）。請確認 `9640514` 與現在的
log 內容逐字相同、沒有混入測試資料。

## 其他

- 依你的意見收斂了 FP-1-A 的措辭，明確標註為「一個真人 turn 的單次觀測」
  並列出未涵蓋情境（多 turn／併發／`Stop` 被阻擋）。
- `997df68` 的流程瑕疵依你的裁決 **不 revert、不重寫歷史**，以 forward-fix
  處理。

## Gate

```
ruby scripts/validate_*.rb（24 支）  → PASS
git diff --check                     → clean
測試用 worktree／branch              → 已清除（git worktree list 可確認）
```

請就這一筆 P1 給 `GO` 或 `NO_GO`。
