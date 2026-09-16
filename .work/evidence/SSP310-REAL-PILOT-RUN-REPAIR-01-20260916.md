# SSP-310 真人 pilot repair-01 — evidence

回應 `9640514` 大 review NO_GO（P1×1）。同一條 review line，只收這一筆。

## F-01（P1）：worktree 隔離被絕對路徑打破

屬實，而且根因是我自己造成的。`997df68` 當時為了繞開「從 `~/Documents`
底下啟動 Claude Code 會失敗」的問題，把 `settings.pilot.json` 的 command
改成指向 main 的絕對路徑——等於**用 worktree 隔離換取啟動目錄自由**。

而那個啟動問題後來查明是 macOS TCC 擋住終端機讀取「文件」資料夾
（`EPERM`，被錯誤訊息包裝成 "low max file descriptors"），Owner 授予
終端機「完全取用磁碟」後已解決。**換取的理由消失了，但那個交換還留著**，
我沒有回頭撤掉，違反卡片凍結的「只在這個 worktree 生效」。

## 修法

`settings.pilot.json` 的 command 改回 `${CLAUDE_PROJECT_DIR}`——每個
worktree 呼叫自己那份 hook。

hook 內的 `PROJECT_DIR` **保留** `__dir__`（腳本自身位置往上兩層），不改
回 `ENV["CLAUDE_PROJECT_DIR"]`。理由：這讓「記錄一定寫在被呼叫的那份腳本
旁邊」成為結構性保證。就算日後有人再把 command 寫成別的路徑，記錄也只會
跟著腳本走，不會因為環境變數被設成別的目錄而寫到不相干的 repo。

## 驗證：重放 reviewer 的隔離測試（真實 worktree，非模擬）

建立真的 `git worktree`，用它自己那份 `settings.pilot.json` 展開 command
後呼叫：

```
展開後 command: ruby "/tmp/ssp310-iso2/.claude/hooks/aiwr_pilot_hook.rb"
                      ^^^^^^^^^^^^^^^^ 指向該 worktree 自己，不是 main

假 worktree 自己的 log → 出現 iso-test 那筆
main 的 log            → 測試前 2 筆、測試後 2 筆（未被寫入）
```

對照修正前：reviewer 量到的是 main `2→3`、假 worktree 沒有 log；修正後
完全相反，符合預期。

### 額外驗證：spec 也確實讀自己 worktree 的

reviewer 另外指出「甚至讀 main 的 spec」。單獨證明這一點：只改假
worktree 自己的 `claude-code-native-adapter.yaml`，把
`UserPromptSubmit` 從 `lifecycle_event_map` 拿掉，再送同一筆事件：

```
假 worktree → 不產生記錄，debug log 寫 SKIPPED_UNCLASSIFIED_NATIVE_EVENT
main 的契約  → 未被改動（grep 仍有 UserPromptSubmit: start）
main 的 log  → 仍 2 筆
```

行為跟著該 worktree 自己的契約走，證明 spec 讀取也已隔離。

## 真實 pilot 記錄的完整性

測試過程中第一次嘗試時（假 worktree 從尚未提交修正的 `HEAD` 建立，拿到
舊設定）曾讓 main 的 log 多出一筆測試記錄。已用
`git checkout -- .work/evidence/ssp310-pilot-runtime-log.jsonl` 還原，
確認回到真實 pilot 的 2 筆（皆為 session `f8b7146e-...`），未混入任何
測試資料。最終 gate 時再次確認為 2 筆。

## 措辭收斂（reviewer 的非阻塞意見）

reviewer 表示 FP-1-A 的證據可以成立，但措辭應理解為「一個真人 turn 已
觀測成立」，不能外推成多 turn／併發的一般性證明。已依此收斂
`SSP310-REAL-PILOT-RUN-20260915.md` 的相關段落，明確標註觀測範圍與未涵蓋
的情境。

## Gate

```
ruby scripts/validate_*.rb（24 支）  → PASS
git diff --check                     → clean
真實 pilot log                       → 2 筆，內容未變
測試 worktree／branch                → 已清除
```
