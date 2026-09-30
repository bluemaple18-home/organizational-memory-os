# OMOS Personal Memory — 安裝說明

> **如果你是 AI 助理（Claude Code／Codex）**：使用者把這包交給你了，請照下面
> 六步做完，不用一步步問。
>
> - **前置需求（Homebrew／Ruby）你做不了**：它要輸入 Mac 密碼，你的 shell
>   不是 TTY，`!` 前綴也一樣不是。請直接請使用者打開「終端機」App 自己跑。
> - **第 2 步的解除隔離一定要做**，否則第 3 步會當場以
>   `INSTALL_SOURCE_QUARANTINED` 失敗（不會卡住，會告訴你怎麼修）。
> - **第 5 步的 Codex hook trust 不能代勞**，只能由使用者本人在 Codex 裡確認。
> - 做完務必產生第 6 步那一段回報，交給使用者傳回給提供這包的人。
> - **如果是升級**（`~/OMOS-Personal-Memory` 已存在）：跳過前置需求，
>   照〈升級到新版〉做，別重裝 Ruby、別重設身分。

---

## 前置需求（只有第一次要做）

需要 Ruby 3.4。先確認：

    brew --version

**有 Homebrew**，跑這行就好，不需要密碼：

    brew install ruby@3.4

**沒有 Homebrew**，要先裝。這一步**必須你本人在「終端機」App 裡做**。

> 不要在 Claude Code／Codex 的對話框裡跑，`!` 前綴也不行。Homebrew 的安裝
> 程式需要 sudo 輸入密碼，那個環境不是 TTY，會直接失敗並印出
> `Running in non-interactive mode… Insufficient permissions`。（實測回報）

打開「終端機」App（Spotlight 搜尋「終端機」或 Terminal），貼上：

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

裝完照它的提示跑 `eval "$(/opt/homebrew/bin/brew shellenv)"` 之類的設定指令，
然後回頭跑 `brew install ruby@3.4`。

**版本不必完全一致。** 判準是 ABI 相容，所以 3.4 系列任何 patch 版本都可以
（3.4.10、3.4.11 都行）。

---

## 安裝（一段貼完）

把 `OMOS-Personal-Memory.zip` 存到家目錄，然後整段貼給你的 AI 助理，
**只改 `你的英文名` 那一格**：

```
rm -rf ~/OMOS-Personal-Memory
unzip -q ~/OMOS-Personal-Memory.zip -d ~
xattr -dr com.apple.quarantine ~/OMOS-Personal-Memory
~/OMOS-Personal-Memory/exe/omos-personal-memory setup --owner urn:omos:employee:你的英文名 --tenant t-clickforce
```

`setup` 會依序做完安裝、每週提醒、檢查與回報。跑完**完全結束 AI 工具再重開**
（Codex 會問要不要信任 hook，請選同意），然後**再跑一次**：

```
~/OMOS-Personal-Memory/exe/omos-personal-memory doctor --report
```

**這一份才是要貼回去的。** `setup` 那次的 doctor 發生在重開與批准之前，
所以第一次安裝時會顯示 Codex hook 還沒 trusted。（升級時如果你之前已經批准過，
它可能就已經是 `OK` —— 那也正常，還是要以重開後那一份為準。）

不要每週提醒就加 `--no-schedule`。

> **名字打錯會當場失敗**並告訴你正確形狀，不會安靜收下。

以下是同一件事拆開來的說明，出問題時對照用。

## 安裝（拆開來看）

### 1. 解壓到家目錄

把 `OMOS-Personal-Memory.zip` 放到家目錄（Finder 側邊欄你名字那個資料夾）
再解壓，得到 `~/OMOS-Personal-Memory`。

### 2. 解除 macOS 隔離

這包是透過網路或通訊軟體傳過來的，macOS 會替裡面的檔案加上「隔離」標記。
裡面有 10 個資料庫用的原生模組沒有 Apple 簽章，不先解除就載入不了。

    xattr -dr com.apple.quarantine ~/OMOS-Personal-Memory

過程中可能出現幾行 `Permission denied`，那是唯讀的說明文件，**可以忽略**。

> **只需要這一行。** 安裝時複製到 `~/.omos` 的那一份由 install 自己清掉。
>
> 忘了做也不會卡住——第 3 步會當場失敗並印出這一行叫你補。

### 3. 安裝

把 `你的英文名` 換成給你這包的人指定的名字，`--tenant` 不要改：

    ~/OMOS-Personal-Memory/exe/omos-personal-memory install --owner urn:omos:employee:你的英文名 --tenant t-clickforce

看到 `INSTALLED` 就成功了。輸出的 `hosts:` 那行會列出實際接上的 AI 工具：

    INSTALLED
      hosts:   Codex, Claude Code

> > **不要照抄別人的名字。** `--owner` 是你在這套系統裡的身分，抄成別人的，
> 你匯入的東西會掛在別人名下。只要設一次，之後升級會自動沿用。
>
> **兩個 host 一定都會列出來**，即使你只用其中一個。本產品目前不偵測你裝了
> 哪些工具，而是照契約把兩邊的設定都寫好；沒用到的那份就放著不動，不影響
> 你任何東西。

### 4. 每週提醒（選用，但建議做）

install 成功後會提示這一行，照著跑就好：

    ~/OMOS-Personal-Memory/exe/omos-personal-memory schedule install

之後每週五 16:00 macOS 會自動叫醒它、算出本週待 review 的筆數並跳通知。

想改成別的星期（`1` 是週一到 `5` 是週五，週末不行）：

    ~/OMOS-Personal-Memory/exe/omos-personal-memory schedule remove
    ~/OMOS-Personal-Memory/exe/omos-personal-memory schedule install --anchor-weekday 3 --anchor-hour 15

改了之後 `review` 相關指令會自動跟著用新設定。不想要了就 `schedule remove`。

### 5. 重開 AI 工具

完全結束 Claude Code（以及 Codex，如果你有用）再打開。**「完全結束」是整個
App 結束，不是關掉視窗**——綁定是在 session 啟動時建立的。

**Codex 使用者還要同意一次。** Codex 對 SessionStart hook 有信任關卡，
下次啟動時它會問你要不要信任這兩個 hook，**選同意**。

> 這一步**不能由安裝程式代勞**——Codex 要求由你本人確認一次。這是好事：
> 任何程式都能在你的設定裡寫 hook，但只有你能批准它跑。
>
> 不同意也不會壞，Claude Code 那邊照常運作，只是 Codex 不會自動綁定。

### 6. 回報（請一定要做）

    ~/OMOS-Personal-Memory/exe/omos-personal-memory doctor --report

**`setup` 已經跑過一次了，但那是重開之前的。**

`setup` 的 doctor 發生在你重開 AI 工具、批准 Codex hook **之前**，所以它一定
會顯示 `codex_session_hook_trust` 還沒 trusted。**做完第 5 步之後再跑一次
上面這行**，那一份才是最終回報。

把 `----- 以下整段複製回傳 -----` 到 `----- 到這裡為止 -----` 之間整段貼回去：

    ----- 以下整段複製回傳 -----
    macOS:   26.6.2 (arm64)
    ruby:    /opt/homebrew/opt/ruby@3.4/bin/ruby (3.4.10, ABI 3.4.0)
    hosts:   Codex, Claude Code
    doctor:  23 OK / 4 WARN / 0 FAIL
      WARN codex_session_hook_trust  尚未 trusted：command=untrusted, mcp_tool=untrusted
    ----- 到這裡為止 -----

**判準只有一個：`0 FAIL`。**

`OK`／`WARN` 的數字會依你裝了哪些 AI 工具而不同，**不要拿數字跟別人比**。
`WARN` 代表那一項在這台機器上無法觀測，不等於健康也不等於故障。

**另外請一併說明**：過程有沒有卡住、卡在第幾步、畫面出現什麼訊息。
順利也請說一聲「順利」。

---

## 開始使用

    ~/OMOS-Personal-Memory/exe/omos-personal-memory import 某個筆記.md --memory-kind DECISION

`--memory-kind` 可用：`DECISION`／`LESSON`／`RULE`／`PROCEDURE`／
`DOMAIN_FACT`／`DEFINITION`／`WORK_PREFERENCE`／`WORKING_STYLE`／
`PROJECT_CONTEXT`／`RELATIONSHIP_CONTEXT`／`LONG_LIVED_CONSTRAINT`。

看匯入了什麼、本週要 review 什麼：

    ~/OMOS-Personal-Memory/exe/omos-personal-memory inbox list
    ~/OMOS-Personal-Memory/exe/omos-personal-memory review due

### 想親眼確認東西真的存在你的電腦上

    open ~/.omos/personal-memory/evidence

Finder 會打開，裡面每個資料夾的名字就是那份內容的指紋。點進去有 `raw.bin`
（你那篇筆記的原文，文字編輯器打得開）和 `envelope.json`（誰的、何時、何種）。

紀錄本身存在資料庫裡，不是可以點開的檔案；但**原文一定落在這裡**。

### 週期帳：看自己有沒有跟上

    ~/OMOS-Personal-Memory/exe/omos-personal-memory review history

    週期帳（自 2026-09-25T16:00:00+08:00 起）
      v 2026-W39  NO_PROMOTION  起 2026-09-25  attempts=1
      x 2026-W40  MISSING       起 2026-10-02  attempts=0

    共 2 週，其中 1 週未完成。

`v` 做完了，`x` 還沒。**原則是一週一次，哪一天做都可以**；漏掉的那週之後
補做一樣算數，不會一直欠著。

    ~/OMOS-Personal-Memory/exe/omos-personal-memory review done --period 2026-W40

真的整週沒空、決定跳過（要等補做期限過了才能宣告）：

    ~/OMOS-Personal-Memory/exe/omos-personal-memory review skip --period 2026-W40

> **剛裝完會顯示「共 0 週」，那是正常的。** 你安裝之前的週期不會算到你頭上，
> 本週的提醒時間還沒到之前也不會列出來。等第一個週五過了就會開始有東西。

### 之後每週的回報

**你不需要主動找問題回報。** 每週跑這一行，把輸出整段貼回來：

    ~/OMOS-Personal-Memory/exe/omos-personal-memory review receipt --period $(date +%G-W%V)

    {
      "employee_ref": "urn:omos:employee:lettie",
      "review_period_id": "urn:omos:personal-memory:review-period:2026-W40",
      "review_status": "NO_PROMOTION",
      "attempt_count": 1,
      "schedule_observed": true,
      "schedule_observed_at": "2026-10-02T16:00:03+08:00",
      "terminal_closeout": true,
      "observed_at": "2026-10-03T09:12:44+08:00"
    }

> **這裡面沒有你的任何筆記內容。** 只有「哪一週、提醒有沒有響、你有沒有
> 關帳」這幾個狀態。你匯入的東西一律留在你自己的電腦上，我們讀不到，
> 也不會自動上傳——這段是你手動複製貼上的。

這份東西是用來看**流程有沒有斷掉**的：提醒沒響、或整週沒有紀錄，
我們這邊會主動去查，不用等你發現不對勁。

---

## 可能會看到的訊息

**`INSTALL_SOURCE_QUARANTINED`**
第 2 步沒做，或做完又重新解壓了一份。照它印出的那一行跑一次再重試。

**「未打開 sqlite3_native.bundle」/「Apple 無法驗證」**
同上。按「**完成**」，**千萬不要按「丟到垃圾桶」**——按了會把檔案刪掉，
整包就壞了。然後回去做第 2 步。

**`WARN codex_session_hook_trust`**
第 5 步的 Codex 同意還沒做。同意後再跑一次 `doctor` 就會變 `OK`。

**`WARN codex_no_shadow`**
這一項在 Codex 目前的設定結構下**沒有辦法觀測**，我們不假裝它是健康的。
會一直在，不用理它。

**`UNQUALIFIED_RUNTIME_PROFILE`**
你的 macOS 版本還沒被正式列入驗證矩陣。**不影響使用**，把你的 macOS 版本
告訴我們就能消掉。

**`找不到 ABI 相容的 Ruby` / exit 78**
前置需求沒做完，或 Ruby 裝在非預設位置。重跑前置需求；仍然不行就執行
`brew --prefix ruby@3.4` 把結果回報。

---

## 升級到新版

**先把舊資料夾整個刪掉，再解壓新版**——不要直接解壓覆蓋，也不要用
`cp -R`／`rsync`。

**升級和新裝用同一段指令**，`setup` 會處理兩種情況：

    rm -rf ~/OMOS-Personal-Memory
    unzip -q ~/OMOS-Personal-Memory.zip -d ~
    xattr -dr com.apple.quarantine ~/OMOS-Personal-Memory
    ~/OMOS-Personal-Memory/exe/omos-personal-memory setup --owner urn:omos:employee:你的英文名 --tenant t-clickforce

填**同一個**名字，資料不會動（實測：store 逐位元組不變、匯入的東西還在）。
排程也會重裝一次，確保指到新版。

然後完全結束 Claude Code（以及 Codex）再重開。

> **為什麼不能直接覆蓋**：解壓覆蓋不會刪掉新版已經沒有的舊檔案，而本產品的
> 版本識別是由資料夾內容算出來的。殘留舊檔會讓同一個版本在不同人的機器上
> 算出不同的版本編號，每次升級還會多累積一份版本目錄。實測：種一個殘留檔，
> artifact id 就從 `44d977dc…` 變成 `fabb0b30…`；先刪再解壓則與乾淨安裝
> 完全一致。
>
> `cp -R` 覆蓋還會在 `vendor` 的唯讀 gem 檔上大量 `Permission denied`。

**你的資料不會受影響**：Personal Store、匯入過的內容、身分設定與 AI 工具的
設定都在 `~/.omos/` 與 `~/.claude/`、`~/.codex/`，刪 `~/OMOS-Personal-Memory`
不會動到它們。實測升級前後 store 檔案逐位元組相同。

---

## 移除

    ~/OMOS-Personal-Memory/exe/omos-personal-memory uninstall

會把 AI 工具設定裡本產品的項目清乾淨，不動你其他的設定。
