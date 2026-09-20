---
id: EMEM11-HUMAN-ACCEPTANCE-CLAUDE-CODE-20260920
status: READY
type: human-acceptance
tier: T2
parent_card: CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
scope_decision: .work/CARD-EMEM11-SCOPE-FREEZE-20260920.md
pinned_repo_sha: 6a33d12
pinned_product_delivery: fa0959a
authority: organizational-memory-os
---

# EMEM-11｜Claude Code 真人驗收步驟卡

這是 EMEM-11 目前**唯一剩下的 DoD**。切片 3 的 synthetic conformance 全綠
（3a 26/26、3b 33/33、3c 49/49、39 支 validators），但那些全部是自動化測試
自己造出來的 session；**SessionStart hook 從來沒有被真的 Claude Code 觸發過**。
這張卡就是要把那一段補上，而且刻意與 conformance 分開，不混算。

## 範圍鎖死

- **只驗已交付 Host：Claude Code。**
- **不碰 Codex、不碰 EMEM-11b**（Codex 是 known-but-not-delivered，依裁決
  不安裝、產不出 binding，那已由 conformance 與 review 涵蓋）。
- **不重開 repair-02～04、不改產品行為。** 這張卡只**觀測與記錄**。
  唯一例外是 Step 0 的臨時探針，它不動本產品的任何設定。
- 驗收過程發現的產品缺陷 → 記進 evidence packet 並判 NO_GO，**不要就地改碼**。

## 執行環境：隔離 HOME（Owner 裁決 2026-09-20）

**不碰你正在用的設定。** 整場驗收跑在一個獨立的 HOME 底下：

```
隔離 HOME   /Users/matt/omos-acceptance-home
```

這仍然是**真的 Claude Code**（同一個 binary、真的 session id），只是設定、
store、session state 全部落在隔離目錄，因此：

- `~/.claude.json`、`~/.claude/settings.json`、`~/.codex/config.toml`
  **完全不會被動到**，不需要備份它們；
- 該 HOME 的 MCP 清單是乾淨的，不會有其他 server 干擾判讀；
- 驗完直接刪掉那個目錄就還原了。

### 開一個驗收用的終端機 session

```sh
export HOME=/Users/matt/omos-acceptance-home
mkdir -p "$HOME"
cd /Users/matt/Documents/ChatGPT/知識庫
cc
```

**注意事項（都是實測過的）**：

- **第一次會要求登入**：實測換 HOME 後會顯示 `Not logged in · Please run /login`
  ——憑證雖在 macOS Keychain，但不會自動接上。在該 session 裡跑一次 `/login`
  即可，這不影響你正式 HOME 的登入狀態。
- `cc` 是你 shell 的 function。若在改了 `HOME` 之後 `cc` 行為異常，直接用
  binary：`/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe`
  （**不要**用 `which claude` 查到的路徑——那是每個 session 專屬的暫時 shim，
  換個終端機就不存在了）。
- 本卡之後所有 `~/...` 路徑，都是指**隔離 HOME 底下**的
  `/Users/matt/omos-acceptance-home/...`。
- 從**一般終端機**（沒 export HOME）操作本產品 CLI 時，要自己補
  `--home /Users/matt/omos-acceptance-home`，否則會動到正式設定。

## 釘死的版本（evidence packet 必須逐項填實際值）

| 項目 | 值 |
|---|---|
| repo SHA | `6a33d12` |
| 產品交付 SHA | `fa0959a` |
| 產品根目錄 | `/Users/matt/Documents/ChatGPT/知識庫/product/personal-memory` |
| Claude Code 版本 | ＿＿＿（`claude --version`） |
| 實測時間（起／訖） | ＿＿＿ |
| 實測機器 | ＿＿＿ |

預設路徑（安裝後才會出現）：

```
store          ~/.omos/personal-memory/personal.db
session state  ~/.omos/personal-memory/sessions/
install receipt ~/.omos/personal-memory/install-receipt.json
```

---

## Step 0｜熔斷探針（硬停點，**在安裝之前**）

**要回答的問題**：Claude Code 生給 **MCP server 子程序**的環境裡，有沒有
`CLAUDE_CODE_SESSION_ID`，而且與 **SessionStart hook** 看到的 session id
**是同一個值**。

為什麼必須先做：`CLAUDE_CODE_SESSION_ID` 目前只在 **Bash tool 的子程序**
確認存在（36 字元 UUID，2026-09-20 實測）。Bash tool 子程序 ≠ MCP server
子程序。repair-01 在 Codex 上犯過一模一樣的錯——觀察到一個就推論全部，被
reviewer 抓。這一步花幾分鐘，但它決定「整條交付路徑到底成不成立」。

探針本身不安裝本產品、不寫 `~/.omos`，只在正式設定裡暫時加一個會自己移除的
MCP server 條目。

**比對對象說明**：Step 0 時本產品**還沒安裝**，所以沒有 hook 可比。這一步
比的是「**MCP server 子程序**看到的 session id」與「**同一個 session 的
Bash 子程序**看到的 session id」。hook 與 MCP 的比對留到 Step 3／4 自然發生。

### 0-1 建立探針（一般終端機即可）

```sh
mkdir -p /tmp/omos-probe && cat > /tmp/omos-probe/probe.sh <<'SH'
#!/bin/sh
# 只把自己看到的環境倒進檔案。不實作 MCP，握手失敗是預期的——
# 我們只要證明「這個子程序拿不拿得到 session id」。
env | grep -E '^CLAUDE|SESSION' > /tmp/omos-probe/mcp-env.txt 2>/dev/null
sleep 30
SH
chmod +x /tmp/omos-probe/probe.sh
```

### 0-2 註冊到隔離 HOME 並開 session

```sh
export HOME=/Users/matt/omos-acceptance-home
mkdir -p "$HOME"
/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe \
  mcp add -s user omos-probe -- /tmp/omos-probe/probe.sh

cd /Users/matt/Documents/ChatGPT/知識庫 && cc      # 首次需 /login
```

Claude Code 在 **session 啟動時**就會去連 MCP server（不需要你呼叫任何
tool），所以進去等十幾秒即可。在**該 session 裡**執行並記下：

```sh
echo "BASH_SEES=$CLAUDE_CODE_SESSION_ID"
echo "CHILD=$CLAUDE_CODE_CHILD_SESSION"
```

然後結束該 session。

### 0-3 判定

```sh
cat /tmp/omos-probe/mcp-env.txt
```

| 觀察 | 判定 |
|---|---|
| 有 `CLAUDE_CODE_SESSION_ID=<UUID>`，且**等於** 0-2 記下的 `BASH_SEES` | **通過**，進 Step 1 |
| 檔案不存在，或沒有該變數 | **整張卡 NO_GO，立刻停止、不要安裝** |
| 有該變數但**與 `BASH_SEES` 不同** | **NO_GO**，並把兩個值都記進 packet |

NO_GO 的意義要講清楚：那代表 Claude Code 與 Codex 一樣，MCP server 無法獨立
取得可信的 native session identity。v1 將沒有任何可交付 Host，必須回 Owner
重開範圍裁決——這不是修一修就能過的事，**不要繼續往下做**。

順帶記下 `CLAUDE_CODE_CHILD_SESSION`：它暗示 subagent／child session 可能有
自己的 id，Step 6 判讀「新 session 是否誤用舊 identity」時會用到。

### 0-4 收掉探針

```sh
/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe \
  mcp remove -s user omos-probe
rm -rf /tmp/omos-probe
```

（`HOME` 仍須是隔離路徑才移得對。最後整個隔離 HOME 會被刪掉，所以這一步
漏掉也不致命，但留著會干擾 Step 2 之後的判讀。）

---

## Step 1｜確認隔離生效（取代備份）

因為跑在隔離 HOME，**不需要備份正式設定**。改為確認隔離真的生效——這一步
沒做，後面所有「Codex 沒被動到」之類的斷言都會失去意義。

在驗收 session 裡：

```sh
echo "HOME=$HOME"                 # 必須是 /Users/matt/omos-acceptance-home
ls -a "$HOME" | head
```

同時在**另一個一般終端機**（沒有 export HOME）記錄正式設定的 hash，
作為「全程沒被動過」的對照基準：

```sh
shasum ~/.claude.json ~/.claude/settings.json ~/.codex/config.toml 2>/dev/null
```

把這三個 hash 記進 evidence packet；**Step 9 收尾時要再跑一次，必須完全相同**。

---

## Step 2｜實際安裝，確認交付範圍

```sh
cd /Users/matt/Documents/ChatGPT/知識庫/product/personal-memory
./exe/omos-personal-memory install
```

必須全部成立：

```sh
# (a) receipt 只有 Claude Code
ruby -rjson -e 'puts JSON.parse(File.read(File.expand_path("~/.omos/personal-memory/install-receipt.json")))["hosts"].keys.inspect'
# 期望：["Claude Code"]

# (b) 隔離 HOME 裡根本不該出現 Codex 設定（install 不交付 blocked host）
ls -l "$HOME/.codex/config.toml" 2>/dev/null || echo "不存在 → 正確"

# (c) SessionStart hook 恰為 1 組，且是本產品的（隔離 HOME 原本 0 組）
ruby -rjson -e 'j=JSON.parse(File.read(File.expand_path("~/.claude/settings.json"))); g=j.dig("hooks","SessionStart")||[]; puts "groups=#{g.size}"; puts g.flat_map{|x|(x["hooks"]||[]).map{|h|h["command"]}}'
# 期望：groups=1，且 command 指向 exe/omos-personal-memory-session-start
```

---

## Step 3｜真 Host 觸發 SessionStart（本卡的核心）

**開一個全新的 Claude Code session**（`cc`），然後在**該 session 裡**：

```sh
ls -l ~/.omos/personal-memory/sessions/
cat ~/.omos/personal-memory/sessions/*.json
echo "本 session 的 id：$CLAUDE_CODE_SESSION_ID"
```

必須成立：

- `sessions/` 下至少有一個 `.json`；
- 其中一筆的 `session_id` **等於本 session 的 `CLAUDE_CODE_SESSION_ID`**；
- `host` 為 `Claude Code`，`cwd` 為啟動目錄的 realpath。

這一項成立，才代表 hook 真的被 Host 叫起來過——這是整張卡存在的理由。
把該 JSON 全文貼進 evidence packet 的「Host 真實觀測」。

---

## Step 4｜從真 Claude Code session 走 MCP：write → read → closeout

在 Step 3 那個 session 裡，用 Personal Memory MCP 的三個 tool 各做一次。
**payload 已預先備好且驗過**（不要臨場生，closeout 的契約欄位很容易寫錯，
被 REJECTED 會被誤判成產品有問題）：

先寫出兩個檔案：

```sh
mkdir -p /tmp/omos-ha && cat > /tmp/omos-ha/link.json <<'JSON'
{
  "link_id": "urn:omos:personal-memory:support-link:01900000-0000-7000-8000-00000000aa01",
  "tenant_id": "t-acme",
  "employee_owner_ref": "urn:omos:employee:emp-001",
  "target_ref": "urn:omos:personal-memory:record:01900000-0000-7000-8000-00000000aa02",
  "evidence_ref": "urn:omos:evidence:ev-001",
  "source_anchor_ref": "urn:omos:source-anchor:sa-001",
  "source_anchor_profile": "MARKDOWN_TEXT_V1",
  "relation": "SUPPORTS",
  "anchor_resolution": "EXACT_MATCH",
  "provenance": {
    "created_by": "urn:omos:employee:emp-001",
    "created_at": "2026-09-20T09:00:00Z"
  }
}
JSON
cat > /tmp/omos-ha/closeout.json <<'JSON'
{
  "review_period_id": "urn:omos:personal-memory:review-period:2026-W38",
  "scheduled_review_period_start": "2026-09-18",
  "scheduled_anchor_at": "2026-09-18T15:00:00Z",
  "actual_closeout_at": "2026-09-18T17:30:00Z",
  "attempt_kind": "SCHEDULED",
  "final_status": "COMPLETE",
  "catch_up_deadline_passed": true,
  "selected_item_refs": [
    "urn:omos:personal-memory:candidate:01900000-0000-7000-8000-00000000aa03"
  ],
  "item_dispositions": {
    "urn:omos:personal-memory:candidate:01900000-0000-7000-8000-00000000aa03": {
      "category": "MATERIALLY_CHANGED",
      "promotion_ref": "urn:omos:promotion:pr-001",
      "promotion_idempotency_key": "pk-001"
    }
  }
}
JSON
```

然後請該 session 依序呼叫：

1. `personal_memory_write`：`kind=MemorySupportLink`、`resource` 用
   `link.json` 的內容、`idempotency_key=ha-k1`
   → 期望 `{"status":"WROTE", "row_id":"...aa01"}`
2. `personal_memory_read` → 期望陣列且含 `...aa01`
3. `personal_memory_closeout`：`closeout` 用 `closeout.json` 的內容
   → 期望 `{"status":"COMMITTED", "terminal":true}`

三個回應原文貼進 evidence packet 的「產品回應」。

> 這三個 payload 已於 2026-09-20 以 CLI 實跑驗過（`WROTE` / `COMMITTED` /
> read 讀得回），所以在這裡失敗代表 **MCP 路徑**有問題，不是 payload 有問題。

---

## Step 5｜獨立確認資料真的落到同一個 SQLite store

**不要只信 MCP 的回覆。** 用獨立連線讀（store 是 WAL，用真的 SQLite 連線，
不要用 `strings`／直接讀檔那種方式判斷）：

```sh
sqlite3 ~/.omos/personal-memory/personal.db \
  "SELECT row_id FROM memory_rows ORDER BY rowid;
   SELECT DISTINCT surface FROM operation_journal;
   SELECT COUNT(*) FROM closeouts WHERE is_terminal = 1;"
```

必須成立：

- `memory_rows` 含 `...aa01`；
- `operation_journal` 的 surface 含 `LOCAL_STDIO_MCP`（證明是走 MCP 進來的，
  不是 CLI）；
- terminal closeout 計數為 1。

再用產品自己的 CLI 從**另一個進程**讀一次，證明 CLI 與 MCP 共用同一個 store：

```sh
cd /Users/matt/Documents/ChatGPT/知識庫/product/personal-memory
./exe/omos-personal-memory read
```

---

## Step 6｜關閉／重開 session：資料仍在，identity 不串

1. **結束** Step 3 那個 session。
2. 開一個**新的** Claude Code session（`cc`），在新 session 裡：

```sh
echo "新 session id：$CLAUDE_CODE_SESSION_ID"
ls -l ~/.omos/personal-memory/sessions/
```

必須成立：

- 新 session 的 id 與舊的**不同**；
- `sessions/` 下**多出**一個對應新 id 的檔案（不是覆蓋舊的）；
- 在新 session 呼叫 `personal_memory_read`，**仍讀得到** `...aa01`
  （資料跨 session 存活）；
- 新 session 的 binding 用的是自己的 id——可由 `journal` 佐證：

```sh
cd /Users/matt/Documents/ChatGPT/知識庫/product/personal-memory
./exe/omos-personal-memory journal | ruby -rjson -e 'JSON.parse($stdin.read)["operations"].each{|o| b=o["host_session_binding"]; puts "#{o["kind"]}\t#{b && b["executor_session_ref"]}" }'
```

新 session 產生的操作，其 `executor_session_ref` 必須是**新**的 session id。

> **已知限制（要寫進 packet，不是缺陷）**：session state 檔以
> `(host, native_session_id)` 為鍵，**目前沒有清理路徑**（repair-02 移除了
> 未接線的 `clear!`）。所以舊 session 的檔案會一直留著。這不會造成串用
> ——鍵不同就讀不到彼此——但檔案會累積。

---

## Step 7｜fail-closed 真人負例

**先讀這段再做**：`establish_binding!` 是在 **MCP server 啟動時跑一次**，
binding 之後就固定在該進程裡。所以「在 session 進行中把 session 記錄刪掉，
再呼叫 tool」**不會失敗**——server 早就拿到 binding 了。那樣做會得到一個
**假的 PASS**。

正確做法（兩者擇一，做一條即可，兩條都做更好）：

**7a｜刪記錄後重開 session**

```sh
mv ~/.omos/personal-memory/sessions ~/.omos/personal-memory/sessions.bak
```

然後開一個新的 Claude Code session，呼叫 `personal_memory_read`。
期望：**被拒**，`code` 為 `MCP_NO_SESSION_RECORD`。
驗完還原：`mv ~/.omos/personal-memory/sessions.bak ~/.omos/personal-memory/sessions`

**7b｜拔掉 hook 後重開 session**

暫時把**隔離 HOME 的** `$HOME/.claude/settings.json` 的 `hooks.SessionStart`
清空，開新 session，呼叫 `personal_memory_read`。期望同樣 fail closed
（hook 沒跑 → 沒有記錄）。驗完重跑一次 `install` 即可還原。

**判定重點**：失敗必須是**明確的契約錯誤碼**，不是逾時、不是空陣列、
更不是「照常回答但沒有資料」。任何一種 silent fallback 都是 NO_GO。

---

## Step 8｜doctor

```sh
cd /Users/matt/Documents/ChatGPT/知識庫/product/personal-memory
./exe/omos-personal-memory doctor
```

把**完整輸出**貼進 evidence packet，並逐項分類：

- **FAIL** → 任何一條 FAIL 都是 NO_GO。不得把 FAIL 當 PASS，也不得因為
  「知道原因」就降級成 WARN。
- **WARN** → 逐條對照下表；表上沒有的 WARN 一律當作新發現，要在 packet
  裡單獨列出並說明。

目前**已知且可接受**的 WARN：

| id | 意義 | 這張卡驗完後會變嗎 |
|---|---|---|
| `claude_code_session_start_hook_present` | 形狀已對齊官方 schema，但 doctor 不檢查 hook 是否真的被觸發過 | **不會**。見下方說明 |
| `codex_not_delivered` | Codex 依裁決不交付，附解除條件 | 不會，且不在本卡範圍 |

> **已知顯示限制（Owner 已裁決：本卡只記錄，不改產品）**：
> `claude_code_session_start_hook_present` 目前是**無條件回 WARN**——doctor
> 只看 hook 有沒有寫進設定，不看它有沒有真的燒過。因此就算 Step 3 成功，
> doctor 仍會顯示 WARN。**本卡的證據是 Step 3 的 session state 檔，不是
> doctor 這一行。** 若日後要讓 doctor 讀 session state 來收斂這條 WARN，
> 那是一次獨立的產品變更，需配套測試與 review，不在本卡。

---

## Step 9｜Evidence packet 與判定

產出 `.work/handoff/EMEM11-HUMAN-ACCEPTANCE-<日期>.md`，**三段分開，不混寫**：

### A. Host 真實觀測（只放「Host 自己給的事實」）
- Claude Code 版本、實測時間、機器
- Step 0 探針結果：MCP server 子程序看到的 `CLAUDE_CODE_SESSION_ID`
- Step 3 的 session state JSON 全文，與該 session 的 `CLAUDE_CODE_SESSION_ID`
- Step 6 的新舊 session id 對照

### B. DB 實物證據（只放「獨立連線查到的東西」）
- Step 5 的 SQLite 查詢輸出原文
- Step 6 的 journal 輸出（`executor_session_ref` 對照）
- 不要放任何 MCP 的回覆

### C. 產品回應（只放「產品自己說了什麼」）
- Step 4 三個 tool 的回應原文
- Step 7 的拒絕碼
- Step 8 的 doctor 完整輸出與 WARN 分類

### 判定

**ACCEPTED_GO** 的條件不是「指令都跑完」，而是這條鏈**每一環都有 A／B 兩類
證據支撐**：

```
真 Claude Code session
  → trusted native session identity（A：Step 0 + Step 3）
  → MCP（C：Step 4）
  → Runtime governance（C：Step 7 的 fail closed）
  → Local Store（B：Step 5）
  → restart / readback / closeout（A+B：Step 6）
```

任一環只有 C（產品自己說）而沒有 A 或 B 佐證 → **NO_GO**。
任何 doctor FAIL、任何 silent fallback → **NO_GO**。

通過後：把本卡 status 改為 `ACCEPTED_GO_<日期>`，並更新主卡
`CARD-EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918` 的 status 與
DoD 未結項；**EMEM-11 至此才正式滿足收斂後的 DoD，才可進 SSP-295。**

---

## 中止與還原（任何一步出事都走這裡）

因為全程在隔離 HOME，還原就是**刪掉那個目錄**：

```sh
rm -rf /Users/matt/omos-acceptance-home
rm -rf /tmp/omos-probe /tmp/omos-ha
```

然後確認正式設定全程未被動過——與 Step 1 記下的 hash 比對：

```sh
shasum ~/.claude.json ~/.claude/settings.json ~/.codex/config.toml 2>/dev/null
```

三個 hash 必須與 Step 1 完全相同。**若有任何一個不同，那本身就是一個必須
記錄的發現**（代表有路徑繞過了 HOME 隔離），要寫進 evidence packet 並判
NO_GO，不要默默還原了事。

> 想在刪掉前保留證據：先把 `/Users/matt/omos-acceptance-home/.omos/` 整個
> 複製出來（裡面有 store、session state 與 receipt），那是 packet 的 B 段
> 實物證據來源。
>
> 若只想卸載產品但保留隔離環境繼續看：
> `./exe/omos-personal-memory uninstall --home /Users/matt/omos-acceptance-home`
> （預設保留 Personal Store；加 `--remove-store` 會連 Step 4 寫的資料一起刪）
