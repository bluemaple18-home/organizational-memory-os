# EMEM-11｜Claude Code 真人驗收 — Evidence Packet

**判定：ACCEPTED_GO（2026-09-20）**

依 `.work/CARD-EMEM11-HUMAN-ACCEPTANCE-CLAUDE-CODE-20260920.md` 執行。
三段證據分開記錄：A＝Host 真實觀測、B＝DB 實物證據、C＝產品回應。
C 若無 A 或 B 佐證一律不採信。

## 釘死的版本

| 項目 | 值 |
|---|---|
| repo SHA | `6a33d12`（卡片後續修訂見本檔末） |
| 產品交付 SHA | `fa0959a` |
| Claude Code 版本 | **v2.1.278**（Sonnet 5 · Claude Pro） |
| 實測時間 | 2026-09-20 19:04 – 20:33（+0800） |
| 實測機器 | guojiaweideMacBook-Air（macOS, arm64） |
| 執行環境 | 隔離 HOME `/Users/matt/omos-acceptance-home`（真實 Claude Code binary，非 harness） |

---

## A. Host 真實觀測

### A-1 Step 0：MCP server 與 hook 看到同一個 native session（熔斷探針）

同一個 session 內，兩個獨立子程序各自回報：

```
SessionStart hook 收到的 stdin.session_id   9e58993a-d008-412d-ac7f-c45b7c064f60
MCP server 子程序的 CLAUDE_CODE_SESSION_ID  9e58993a-d008-412d-ac7f-c45b7c064f60
```

**相同。** repair-02 的核心假設在真實 Host 上成立——這正是 Codex 失敗、
Claude Code 通過的那一點。hook 收到的 stdin 欄位亦與契約
`host_native_stdin_fields` 一致：`session_id` / `cwd` / `hook_event_name` /
`source`（`source=startup`）。

原始檔：`/Users/matt/omos-acceptance-home/step0-evidence/`

### A-2 Step 3：hook 由真 Claude Code 觸發並落地可信 identity

```
host        = Claude Code
session_id  = 5fe17a02-6a50-4627-873f-8da554cb0776
cwd         = /Users/matt/Documents/ChatGPT/知識庫
source      = startup
recorded_at = 2026-09-20T11:26:09Z
```

檔名 `38ff419e...4000.json` 經獨立計算等於
`SHA256("Claude Code" + NUL + session_id)`，與 repair-02 的鍵設計吻合。

**這是本卡存在的理由**：在此之前，所有 hook 都是自動化測試自己叫起來的。

### A-3 Step 6：換 session 後 identity 不串、舊記錄不被覆蓋

```
session 1   5fe17a02-6a50-4627-873f-8da554cb0776   11:26:09Z
session 2   3ee833d8-28eb-41a9-9a12-8344ac413c8b   11:53:10Z
session 3   291b27ac-1b25-4cee-a9fc-13a76242c8d9   12:29:46Z
```

三份並存，每一份的檔名鍵都獨立驗算正確。**沒有任何一份被覆蓋**——這正是
repair-02 P1-1 修掉的缺陷（原以 cwd 為鍵，第二個 session 會蓋掉第一個），
在真實環境確認修復。

---

## B. DB 實物證據（獨立 SQLite 連線，不經產品）

### B-1 資料真的落地，且是走 MCP 進來的

```sql
SELECT kind, row_id FROM memory_rows;
-- MemorySupportLink | urn:omos:personal-memory:support-link:...aa01

SELECT COUNT(*) FROM closeouts WHERE is_terminal=1;
-- 1
```

### B-2 operation journal 的完整樣貌

| # | kind | executor_session_ref | 對應 |
|---|---|---|---|
| 1 | STORE_WRITE | `5fe17a02…` | session 1 |
| 2 | STORE_READ | `5fe17a02…` | session 1 |
| 3 | CLOSEOUT_COMMIT | `5fe17a02…` | session 1 |
| 4 | STORE_READ | `3ee833d8…` | session 2（重啟後仍讀得到） |
| 5 | STORE_READ | `291b27ac…` | session 3 |

所有 surface 皆為 `LOCAL_STDIO_MCP`，`executor_ref` 皆為 `Claude Code`。
**每一筆操作都綁在當時那個真 session 的 identity 上**，沒有一筆用了別人的。

### B-3 被拒的操作沒有留下任何痕跡

Step 7 的 REFUSED 之後：`operation_journal` 仍 5 筆、`memory_rows` 仍 1 筆，
最後一筆仍是先前那次合法 read。fail closed 不只是「回錯誤」，是**真的沒動到
任何東西**。

---

## C. 產品回應

### C-1 Step 4：write → read → closeout（真 Claude Code 呼叫 MCP）

```
personal_memory_write
  {"status":"WROTE","row_id":"urn:omos:personal-memory:support-link:01900000-0000-7000-8000-00000000aa01"}

personal_memory_read
  [{"kind":"MemorySupportLink","row_id":"urn:omos:personal-memory:support-link:01900000-0000-7000-8000-00000000aa01"}]

personal_memory_closeout
  {"status":"COMMITTED","review_period_id":"urn:omos:personal-memory:review-period:2026-W38","terminal":true}
```

### C-2 Step 6：重啟後新 session 讀回

```
[{"kind":"MemorySupportLink","row_id":"urn:omos:personal-memory:support-link:01900000-0000-7000-8000-00000000aa01"}]
```

### C-3 Step 7：fail-closed 負例

```
{"status":"REFUSED","code":"MCP_NO_SESSION_RECORD",
 "detail":"此 session 沒有可信的 HostSessionBinding；請確認 installer 已註冊且 SessionStart hook 已執行。"}
```

明確的契約錯誤碼——不是逾時、不是空陣列、不是「照常回答但沒有資料」。

### C-4 Step 2：安裝範圍

```
INSTALLED
  store:   /Users/matt/omos-acceptance-home/.omos/personal-memory/personal.db (schema 0.1.0)
  hosts:   Claude Code
  receipt: /Users/matt/omos-acceptance-home/.omos/personal-memory/install-receipt.json
```

獨立驗證：receipt 的 `hosts` = `["Claude Code"]`；隔離 HOME 下**不存在**
`.codex/config.toml`；`.claude/settings.json` 的 SessionStart 恰為 1 組且指向
本產品 exe；`.claude.json` 的 `mcpServers` = `["omos.personal-memory"]`。
repair-03 P2「不交付 blocked host」在真實安裝中生效。

### C-5 Step 8：doctor

**18 OK / 2 WARN / 0 FAIL。** 兩個 WARN 與卡片預先列出的已知項完全一致：

| id | 分類 |
|---|---|
| `claude_code_session_start_hook_present` | 已知顯示限制（見下） |
| `codex_not_delivered` | 已知，依 Owner 裁決不交付，附解除條件 |

**已知顯示限制實際命中**：該 WARN 的文字是「已依官方 schema 寫入；尚未由真
Host 實際觸發過」，但 A-2 已證明它**確實被真 Host 觸發過**。doctor 只檢查
hook 有沒有寫進設定、不檢查它是否燒過，所以驗收成功也不會變。依 Owner 裁決
（2026-09-20），本卡只記錄，不改產品。要收斂這條 WARN 需另開產品變更卡。

---

## D. 隔離完整性

全程在隔離 HOME 執行。收尾時對正式設定的定向檢查：

```
正式 ~/.claude.json  mcpServers = ["agent-relay"]        → 無 omos.personal-memory
正式 ~/.claude/settings.json  SessionStart 組數 = 0       → 與基準相同
~/.codex/config.toml  shasum = f0b440b25e55aeb6fe3d42c0804187428b61faac  → 與基準相同
```

**正式設定全程零污染。**

> 方法學修正（實測踩到）：原卡片要求用整份 `~/.claude.json` 的 shasum 當基準，
> 實際上 Claude Code 正常運作時就會持續改寫該檔（`projects` 鍵存對話歷史），
> hash 每隔數秒即不同，會一直誤報污染。已改為上述定向檢查。

---

## E. 過程中修正的一個測試設計錯誤（誠實記錄）

Step 7 第一次執行**沒有失敗**——read 正常回了資料。經查證**不是產品缺陷**：

原設計是「把 `sessions/` 目錄搬走 → 重開 session → 期望 MCP 找不到記錄」。
但重開 session 的瞬間 **SessionStart hook 會先執行**，立刻替新 session 寫下
一份屬於它自己的記錄（實測：`291b27ac…`，`recorded_at=12:29:46Z`），MCP
server 讀到的是那份新記錄，因此正常建立 binding——產品行為完全正確。

有效的負例必須**讓 hook 不執行**：清空隔離 HOME 的
`.claude/settings.json` 的 `hooks.SessionStart`，再開新 session。改用此法後
得到 C-3 的 `MCP_NO_SESSION_RECORD`。卡片 Step 7 已同步修正。

（卡片原本已警告過一個相關陷阱：binding 在 MCP server 啟動時只建立一次，
所以 session 進行中刪記錄不會失敗。這次踩到的是**另一個**、更前面的陷阱：
hook 會把記錄重新寫回來。）

---

## F. 判定

卡片要求的成功判準是整條鏈**每一環都有 A 或 B 佐證**：

```
真 Claude Code session      A-1, A-2
  → trusted native session identity   A-1（hook 與 MCP 同 id）、A-2（落地記錄）
  → MCP                     C-1 + B-2（surface=LOCAL_STDIO_MCP）
  → Runtime governance      C-3 + B-3（fail closed 且未動到任何東西）
  → Local Store             B-1（獨立連線查得）
  → restart / readback / closeout   A-3 + B-2 #4 + C-2、B-1 terminal=1
```

- doctor FAIL：**0**
- silent fallback：**無**（唯一的失敗情境回明確契約錯誤碼）
- 僅有 C 而無 A/B 佐證的環節：**無**

**判定：ACCEPTED_GO。**

EMEM-11 收斂後的 DoD 至此全部成立——「已交付 Host（Claude Code）有真人實測」
這一項完成。本卡不再阻擋 SSP-295。

## G. 仍然未收治（不在本卡範圍，但不要忘記）

1. **產品尚未可獨立安裝**：`lib/omos/contract.rb:21` 的 spec 路徑寫死指向
   repo 內的 `規格/v0.1/`。因此目前只能在這個 repo 內執行；給同事或別台機器
   測試會在 install 階段就失敗。
2. **session state 檔沒有清理路徑**：以 `(host, native_session_id)` 為鍵，
   舊 session 的檔案會一直累積（本次即留下 3 份）。不會造成串用，但會長大。
3. **doctor 的 hook WARN 無法收斂**：見 C-5。
4. **Codex / cross-host**：`CARD-EMEM11B-CODEX-CROSS-HOST-20260920`，BLOCKED，
   等上游提供可信 native session identity channel。
