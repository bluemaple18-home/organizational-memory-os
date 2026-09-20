---
id: EMEM11-Q7-ACTIVATION-RUNTIME-PROFILE-20260921
status: DECIDED_FROZEN
decided_at: 2026-09-21
type: research
tier: T3
parent_card: CARD-EMEM11-STANDALONE-PACKAGING-RESEARCH-20260920
depends_on_evidence: .work/handoff/EMEM11-Q6-PART1-EVIDENCE-20260921.md
unblocks:
  - CARD-EMEM11-STALE-HOOK-RELOCATION-20260920
  - CARD-EMEM11-RUBY-GUARD-CRITERION-20260921
pinned_product_delivery: fa0959a
authority: organizational-memory-os
---

# Q7｜Activation identity ＋ Runtime profile（合併裁決）

## 0. 裁決（2026-09-21，已凍結）

### 0.1 選 A，且 stable identity ＝**固定 launcher path**（不是 `current` symlink）

```
Host config
  ↓  ← Host identity（永遠只認這一層，且永遠不含版本）
固定 launcher path
  ~/.omos/personal-memory/bin/omos-personal-memory-mcp
  ~/.omos/personal-memory/bin/omos-personal-memory-session-start
  ↓  ← activation pointer
current -> versions/<artifact-id>
  ↓  ← artifact identity
真正的 artifact
```

**三個概念必須分清楚，不得再由單一 `product_root` 同時扮三個角色：**

| 概念 | 是什麼 | 誰會看到它 |
|---|---|---|
| **Host identity** | 固定 launcher path | 寫進 Host 設定；升版**不變** |
| **activation pointer** | `current` symlink | 只在 launcher 背後；切版時改的就是它 |
| **artifact identity** | `versions/<artifact-id>` | artifact 自我識別（`__dir__` 解析後即得） |

> reviewer 獨立重播 §1.2 結果一致：shell 經 `current/exe/…` 呼叫保留
> `current`，Ruby `__dir__` 直接解析成 `versions/v1`。因此**Host 不應直接綁
> `current/exe/…` 當 identity**——那仍是一條會隨佈局改變的路徑。固定 launcher
> 是唯一不受 symlink 解析語意影響的一層。

### 0.2 不接受「升級前必須關閉所有 session」作為架構前提

可以當**操作建議**，但不得靠它讓原地覆蓋成立。理由（reviewer 補充後）：

1. 產品**無法可靠證明**所有 session 都關了；
2. 原地覆蓋仍**沒有乾淨的 rollback target**；
3. copy 中途失敗仍可能半新半舊；
4. 要驗證新 artifact，**必須先污染現行版本**才驗得到。

而若為了解這四點再加 staging directory ＋ backup ＋ atomic rename，
**那就是重新發明了 versioned artifact／current seam**。

因此 §5 的結論成立：**versioned artifact 不是炫技，是目前最小能同時滿足
atomic activation ＋ rollback ＋ running-session safety 的形狀。**

### 0.3 Runtime profile guard —— 四項（定義已收緊）

1. 記錄**實際選中的 Ruby executable**（不是「版本符合就好」）。
2. 對 artifact 宣告的**全部 production native dependencies** 驗 loader
   resolution——**不只 `bigdecimal`**。
3. 用該 Ruby 對**這一份 artifact 自己的 native extensions** 做**真實 load
   probe**；目前至少涵蓋 `bigdecimal` ＋ `sqlite3`。
4. 比對 **qualified runtime profile**。

**qualified profile 不得只是 `Ruby 3.4.x = allowed`**，至少要綁：

```
artifact build identity
+ OS / architecture
+ Ruby implementation
+ Ruby ABI
+ native linkage / profile
```

> **「load probe 成功」≠「qualified」**：前者是「這台機器能跑」，後者是
> 「我們承諾支援這個組合」。兩者不得混為一談——能跑但未 qualified 的組合，
> 應該是明確的、可辨識的狀態，而不是靜默放行。

guard 必須 **fail closed 並給明確錯誤**；**不得**再由
`RUBY_VERSION == "3.4.10"` 決定。

### 0.4 由本裁決衍生的實作約束（供下游兩張卡）

- **installer 不得用 `__dir__` 推導出的路徑去組 Host command**（§1.2）。
  寫進 Host 的必須是固定 launcher path。
- **hook 的 argv authority 注入契約保留**：hook handler 在兩個 Host 的官方
  schema 都沒有 env 欄位，`--host` / `--runtime-scope-mode` 仍只能走 argv
  （repair-01 既有裁決）。固定 launcher 必須原樣轉傳這些參數。
- launcher 位於 `~/.omos/personal-memory/bin/`，與 Personal Store
  （`~/.omos/personal-memory/personal.db`）**同一個父目錄**。因此
  uninstall 移除 launcher 時**不得**整個刪除該父目錄——預設仍須保留 store
  （裁決點 7）。
- `current` 切換要原子：以 `ln -s new tmp && mv -f tmp current`（`rename(2)`）
  達成，**不要用 `ln -sfn` 先刪後建**。

### 0.5 下游解鎖

- `CARD-EMEM11-STALE-HOOK-RELOCATION-20260920` —— 根因（Host 綁版本路徑）
  由 0.1 消除，可按此最終形狀實作。
- `CARD-EMEM11-RUBY-GUARD-CRITERION-20260921` —— 判準由 0.3 定義，
  `blocked_by: RUNTIME_PROFILE_DECISION` 解除。

---

👉 [假設與目標確認]
- **目標**：一次裁掉 activation identity 與 runtime profile。兩者綁在一起——
  activation 決定 Host 指向什麼，runtime profile 決定 guard 驗什麼；任一未定，
  下游兩張缺陷卡就不知道最終形狀。
- **邊界**：**本卡不寫實作、不改產品**。不選配送格式（gem／tarball／brew）、
  不建 build pipeline。
- **驗收**：Owner／reviewer 對 §3 的 A／B 擇一，並回答 §4 的七個裁決點與
  §5 的 why-not-simpler。

---

## 1. 現況（實測，非描述）

### 1.1 Host 設定裡目前存的東西

```
MCP entry     id = "omos.personal-memory"（穩定）
              command = <product_root>/exe/omos-personal-memory-mcp
SessionStart  command = <product_root>/exe/omos-personal-memory-session-start
                        --host "Claude Code" --runtime-scope-mode EMPLOYEE_PRIVATE
```

**兩者的識別方式不對稱**，這正是 stale-hook 的根因：

| 註冊 | 靠什麼辨識「這是我的」 | product_root 改變後 |
|---|---|---|
| MCP entry | **穩定 id** `omos.personal-memory` | 正確被取代 |
| SessionStart hook | **含絕對路徑的整條 command 字串** | 認不出舊的 → 併存；uninstall 也只刪自己那條 |

> hook 的那兩個參數不是裝飾：Host 不提供 `host` 與 `runtime_scope_mode`，
> 而 hook handler 在兩個 Host 的官方 schema 裡**都沒有 env 欄位**，所以
> installer 只能用 argv 注入這份 authority（repair-01 的既有裁決）。
> **任何 activation 方案都必須保留這條 argv 注入契約。**

### 1.2 `__dir__` 與 shell 對「根」的認知不一致（新發現）

以 `current -> versions/v1` 的佈局實測，同一次呼叫裡：

| 層 | 取得的根 | 說明 |
|---|---|---|
| Shell（現有 exe bootstrap：`$0` ＋ `cd`／`pwd`） | `…/current` | **保留穩定路徑**；實測現有 bootstrap 在 symlink 下可正常運作 |
| Ruby（`__dir__`） | `…/versions/v1` | **`__dir__` 會解析 symlink**（等同 `realpath`） |

而 `Installer#product_root` 的預設值正是由 Ruby 的 `__dir__` 推導
（`File.expand_path("../../..", __dir__)`），`mcp_command` / `hook_command`
再由它組出來。

> **因此：即使做了 A 案，只要 installer 仍沿用 `__dir__` 推導的
> product_root，寫進 Host 的仍會是 versioned 路徑，stale-hook 會原封不動
> 回來。** A 案要成立，必須把兩種「根」明確分開：
>
> - **stable path**（寫進 Host 的 command）：不得經過 `realpath`；
> - **artifact self-identity**（我是哪一個 build）：應該用解析後的
>   versioned 路徑。
>
> 目前兩者被同一個 `product_root` 混用，這是 A 案的第一個必要修改。

另一個實測到的陷阱：`$(dirname "$0")/../lib` 這種**純字串路徑運算**在
symlink 下會走到錯的地方（`current/../lib` → `<parent>/lib`）。現有 exe 因為
用了 `cd … && pwd` 而倖免，但任何新寫的 launcher 都可能踩到。

### 1.3 已經與 artifact 分離的東西（不必動）

Personal Store、session state、install receipt 全部在 `~/.omos/…`（HOME 相對），
**與 artifact 路徑無關**，因此換版本不影響使用者資料。這一層的分離已經成立。

---

## 2. Q6 帶進來的約束（已定案，不重開）

- 支援判準 ＝ **runtime profile：native linkage 可解析 ＋ ABI 相容**，
  不以 `RUBY_VERSION` 字串為準。
- artifact 內**必然**含至少一個本機編譯的原生擴充（`bigdecimal`），其
  linkage 指向編譯當下的 Ruby。
- 缺 linkage path 時是**明確 LoadError、exit 非零**，不是靜默失敗。
- Homebrew patch 相容 ＝ `EXPECTED_COMPATIBLE / NOT_YET_VERIFIED`。

---

## 3. 兩個方案

### A｜Stable Host identity → versioned artifact（reviewer 初始傾向）

```
Host 設定       只含 stable command identity（永遠不含版本）
                      ↓
stable launcher / current pointer
                      ↓
versions/<artifact-id>/…   ← 真正的產品
```

**能解掉的**：

- Host 的 hook command 不再隨 product_root 改動 → **stale-hook 根因消失**
  （前提是 §1.2 的兩種「根」被分開）。
- upgrade 可以 stage 新 artifact → 驗證 → **atomic switch**。
- rollback 只切回上一個 artifact，**不必重寫 Host config**。
- code／spec／evaluator 維持同一 artifact identity。
- runtime profile preflight 可放在 stable entrypoint，**Host 完全不需要知道
  Ruby 細節**。
- hook 與 MCP 的識別方式變**對稱**（兩者都靠穩定 identity）。

**代價／新風險**：

- 多一層間接（launcher／pointer），需要定義它由誰安裝、誰升級。
- §1.2 的 root 語意必須明確拆開，否則 A 案會靜默退化成 B 案。
- stable path 本身成為新的相容性承諾（一旦寫進使用者的 Host 設定就很難改）。

### B｜Host 直接指 versioned artifact path ＋ receipt migration

upgrade 時讀前一份 receipt 取得舊 command，先遷移／清除舊註冊再寫新的。

**代價**：

- 每次升版都要**改寫使用者的 Host 設定**（`~/.claude.json` 與
  `~/.claude/settings.json`）——那是使用者的檔案，動得越少越好。
- 遷移失敗、receipt 遺失或損壞時，**沒有可靠的收斂路徑**：Host 設定裡會留下
  指向已不存在版本的註冊，而我們又失去了辨識它的依據。
- rollback 要再改一次 Host 設定。
- 仍須回答「同一時間有 session 正在跑」時改寫設定的後果。

**CC 評估**：A 明顯較優，且 B 的核心弱點不是麻煩而是**可靠性**——它把
「Host 設定的正確性」綁在「每次遷移都成功且 receipt never lost」這個前提上。

---

## 4. 裁決點

1. **Stable identity 是什麼**：固定 launcher 路徑，還是 `current` symlink？
   **硬性要求：Host 設定裡永遠不得含 versioned artifact path。**
   （見 §1.2——這一條不是自動成立的，必須在 installer 明確保證。）
2. **Artifact layout**：至少要能表達 `versions/<artifact-id>/…` 與
   `current → versions/<artifact-id>`。**不先決定 gem／tarball／brew。**
3. **Upgrade atomicity**：新 artifact 未完整驗證前不得成為 current；
   切換失敗時舊版本必須仍可用。
4. **Rollback**：receipt 要能知道 current／previous 的 artifact identity；
   rollback **不得**靠重新下載或猜 SHA。
5. **Runtime profile guard 驗什麼**（取代現行的版本字串比對）：
   - 實際選到哪一個 Ruby executable；
   - native dependency 能否被 loader 解析；
   - **實際做一次 native load probe** 並成功；
   - 該組合是否屬已 qualification 的 profile。
6. **Artifact identity**：code ＋ 2 份 spec ＋ 7 支 evaluator ＋ dependency
   layout 必須同屬一個 build identity；**store `schema_version` 完全分開**。
7. **Uninstall 語意**：移除 stable registration／launcher／artifacts 時，
   Personal Store **預設保留**；歷史版本的清理策略另外明確定義。

---

## 5. Why not simpler：為什麼不能單一目錄、upgrade 原地覆蓋？

必須正面回答，否則 versioned artifact ＋ current seam 就是過度設計。

原地覆蓋的具體問題（依嚴重度）：

1. **升級中途的混版載入**：Ruby 是**惰性 require**——MCP server 是 per-session
   長駐進程，hook 也可能正在執行。覆蓋進行中，既有進程可能載入到「舊檔 ＋
   新檔」的混合。這不是理論風險，是本產品的實際執行形態。
2. **沒有 rollback 標的**：舊的位元組已被覆蓋，rollback 只能重新下載／重建，
   違反裁決點 4。
3. **沒有原子切換點**：複製到一半失敗就是半套安裝，而 Host 設定早已指向它。
4. **驗證時機顛倒**：artifact integrity 只能在**覆蓋之後**驗，發現不對時
   已經沒有乾淨狀態可退。

> 若要主張原地覆蓋可行，等價於要能保證「升級期間沒有任何 session 在跑」——
> 產品**無法強制**這件事（使用者隨時可能開著 Claude Code）。
>
> 反過來說：如果 Owner 接受「升級前必須關閉所有 session」這個使用限制，
> 原地覆蓋確實變得可行，複雜度也低得多。**這是一個真實的取捨，不是修辭**，
> 應由 Owner 明確裁決，而不是由實作預設。

---

## 6. Minimum Sufficient

- **why_not_less**：少於「stable identity ＋ 可切換的 artifact」就無法同時
  滿足裁決點 3（atomicity）與 4（rollback）；而不定義 runtime profile guard
  就無法收掉 `pinned-ruby.sh` 的判定錯誤。
- **why_not_more**：不決定配送格式、不建 release pipeline、不做多平台、
  不處理自動更新／版本檢查服務、不新造版本治理系統（裁決點 6 只要求一個能
  綁住 code＋spec＋evaluator 的 build identity）。
- **do_not_absorb**：不把 artifact 版本與 store `schema_version` 混為一談；
  不因為要做 activation 就順手改 installer 以外的東西。
