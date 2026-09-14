# Owner 派工公版

每次「送 review」「送 re-review」「轉 spec-freeze」結束時，照這裡的格式填。
不要每次重新發明格式；新增流程就在這個檔案加一節。

**路徑一律填真實絕對路徑，不用佔位符。交付包連結一律用 SHA 釘死的
`raw.githubusercontent.com` URL，不要用 branch ref**——branch 在 merge 後會被刪除，
raw URL 對已刪除 branch 仍會回傳殘影，實際造成過 reviewer 誤判。

---

## 1. 送大 review / 定點 re-review

貼給 reviewer：

```
<一句話：這是誰的第幾輪 review，只審什麼／不必重開什麼>

https://raw.githubusercontent.com/<org>/<repo>/<SHA>/.work/handoff/<FILE>.md

base             <SHA>
original_review  <SHA>（若非第一輪，註明 immutable／NO_GO）
repair_NN        <SHA>（若有多輪，逐輪列出）
delivery         <SHA>（docs-only 交付包 commit）
branch           <branch 名>

定點 diff：git diff <SHA_A>..<SHA_B>

請就 <finding id 或整體> 給 GO 或 NO_GO。
```

自己要驗（貼終端機）：

```
cd <worktree 絕對路徑> && ruby scripts/validate_<contract>.rb && git diff <SHA_A>..<SHA_B> --stat
```

## 2. 轉 Owner spec-freeze（T2，hard stop 觸發後）

```
cd <worktree 絕對路徑> && cat .work/CARD-<NAME>-SPEC-FREEZE-<date>.md
```

回覆只需給每個 Freeze Point 的選項字母，例如「B A A A」，
或「DEFER」表示不繼續、卡在目前版本、改跑下一張卡。

## 3. Jira 換手（轉給 Codex 或其他 lane）

```
cd <repo 根目錄> && cat .work/handoff/JIRA-SYNC-<date>.md
```

把整份檔案內容轉貼或轉發給 Codex，不要摘要——裡面每筆都附驗收 SHA。

## 4. 開下一張卡前的狀態確認

```
cd <repo 根目錄> && for f in .work/CARD-*.md; do st=$(grep -m1 '^status:' "$f" | sed 's/status: *//'); printf "%-40s %s\n" "$st" "$(basename "$f")"; done | sort
```
