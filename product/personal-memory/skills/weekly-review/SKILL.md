---
name: omos-weekly-review
description: 帶使用者完成 Personal Memory 的每週回顧。當 SessionStart 提到「回顧尚未完成」，或使用者說要做每週回顧／週報／整理這週記的東西時使用。
---

# 每週回顧：先消化，再開口

這份 Skill 的工作是**幫使用者完成每週回顧**，不是幫他跳過。

使用者不應該需要看清單、記週次、或知道任何 URN。那些是你的工作。

## 絕對不可以做的事

**你不得自行關帳。**

`personal_memory_closeout` 這個工具你拿得到，技術上你可以自己送一份
closeout 把這週關掉。**不要這樣做。**

週期帳上那個「已完成」的意義是**使用者本人看過並做了判斷**。你自己讀完、
自己標完、自己關帳，那個紀錄就是假的——它會讓 Owner 以為有人回顧過，
而實際上沒有。

所以：**提議分類可以，關帳一定要等使用者明確同意。** 一句「可以」就夠，
但一定要有。使用者沒有回應、或只是沉默，就不要關。

### 這一條目前**沒有程式在擋**

說清楚現況，因為這會影響你怎麼看待這條規則：

- **有稽核**：每一次關帳都記得住是哪個介面提交的。`review history` 的
  `committed_by` 會顯示 `LOCAL_CLI`（使用者自己下指令）或 `LOCAL_STDIO_MCP`
  （你經 MCP 提交）。你自己關的帳**看得出來**。
- **沒有機械性禁止**：產品目前**無法**阻止你呼叫 `personal_memory_closeout`。
  沒有同意關卡，因為任何「使用者已同意」的旗標都是由你自己填的，
  那種關卡等於沒有。真正不可偽造的人類授權接縫還在研究
  （見 `CARD-HUMAN-ONLY-CLOSEOUT-AUTHORITY`）。

也就是說**這條是行為規則，靠你遵守**。遵守它的理由不是「會被擋」，
而是：你自行關的帳在稽核上留著 `LOCAL_STDIO_MCP`，而那筆紀錄聲稱
「有人回顧過」——那是不實的，而且會被看到。

你也**不得**代替使用者判斷哪些東西該讓公司知道（`NEEDS_ORG_FOLLOWUP`）。
那牽涉到他對公司、對同事、對時機的理解，你沒有那些資訊。

## 步驟

### 1. 先全部讀完

```
omos-personal-memory review due
```

拿到本期待回顧的清單。**接著把每一筆的內容真的讀出來**——內容在
`~/.omos/personal-memory/evidence/<sha256>/raw.bin`，`review due` 給的
前 8 碼就是那個資料夾名的開頭。

有欠著的舊週期就一起處理：

```
omos-personal-memory review history
```

### 2. 自己完成比對

這四個分類**是比對結論，你自己判斷**，不要問使用者：

| 分類 | 什麼時候用 |
|---|---|
| `UNSEEN` | 真的沒有可比對的對象，也看不出跟既有知識的關係 |
| `UNCHANGED` | 跟既有的說法一致，沒有新東西 |
| `NEW_EVIDENCE` | 同一個結論，但多了支持它的證據 |
| `MATERIALLY_CHANGED` | 結論變了、範圍變了、或前提變了 |
| `CONTRADICTED` | 跟既有的某一筆直接衝突 |

要判斷這些，你得先去查既有的知識（`personal_memory_read`），不是只看這週的。

### 3. 用人話講出這週的樣子

不要逐筆報告。**分組、找主題、找矛盾、找重複。** 例如：

> 這週你記了 7 件事。
>
> 其中 3 件是同一個主題的演進（後台篩選的取捨），我標成
> `MATERIALLY_CHANGED`。
>
> 有 1 件**跟你三週前的決定矛盾**：那時寫「匯出用 JSON」，這週寫「改用 CSV」。
> 我標成 `CONTRADICTED`。
>
> 剩下 3 件跟既有的沒衝突，標 `UNCHANGED`。

### 4. 只問需要人判斷的

通常只有兩種：

- **矛盾要確認**：「那個 CSV 的決定，是真的改了主意，還是當時記錯？」
- **哪些該讓公司知道**：「這 2 件我覺得其他人會需要，要標成需要跟進嗎？」

**沒有需要問的就不要硬問。** 直接說「這週沒有需要你判斷的，確認一下就可以關帳」。

### 5. 等使用者同意，才關帳

```
omos-personal-memory review done --period <YYYY-Www> \
  --item <完整 candidate URN>=<分類> ...
```

**每一筆都要有分類，漏一筆會被擋下來**（`REVIEW_DONE_ITEMS_INCOMPLETE`，
它會列出漏掉哪些）。完整 URN 要從 `personal_memory_read` 或
`review due` 的輸出取得，不要用前 8 碼。

補做舊週期時 `--period` 指向那一週，`attempt_kind` 會自動記成 `CATCH_UP`。
真的整週沒做又過了補做期限，才用 `review skip --period <YYYY-Www>`。

關完告訴使用者結果，並說一句週期帳現在的狀態。

## 關於「上傳」

**目前沒有上傳。** `review done` 的 `final_status` 一律是 `NO_PROMOTION`，
標了 `NEEDS_ORG_FOLLOWUP` 也不會自動送給公司——那只是一個候補標記。

所以不要告訴使用者「我幫你送出去了」或「這些會進公司知識庫」。
正確的說法是「標好了，等上傳機制接通後會處理這一格」。

## 你拿得到什麼、拿不到什麼

這份 Skill **不授予任何新權限**。你能做的事跟沒有這份 Skill 時完全一樣：
`personal_memory_read`、`personal_memory_write`、`personal_memory_closeout`，
以及使用者允許你跑的 shell 指令。

這份 Skill 只定義**方法**，不擴張權限。所有寫入仍然經 Runtime 治理層，
被拒的不會落地。
