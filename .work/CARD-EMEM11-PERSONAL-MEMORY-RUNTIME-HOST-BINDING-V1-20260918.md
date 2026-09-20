---
id: EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
status: DOD_MET_20260920_READY_FOR_SSP295
human_acceptance: .work/handoff/EMEM11-HUMAN-ACCEPTANCE-20260920.md（ACCEPTED_GO）
slice3_delivery: fa0959a
slice3_review: GO_20260920（repair-04，P0/P1/P2/P3 全 0）
jira: NOT_CREATED
parent_jira: SSP-286
type: mvp-product-capability
priority: MVP
authority: organizational-memory-os
depends_on:
  - SSP-323_ACCEPTED_GO
parallel_with:
  - SSP-324
blocks:
  - SSP-295_FULL_PRODUCT_PILOT
scope_decision: .work/CARD-EMEM11-SCOPE-FREEZE-20260920.md
supported_hosts_v1:
  - Claude Code
follow_up:
  - CARD-EMEM11B-CODEX-CROSS-HOST-20260920
---

> **Owner 範圍裁決 2026-09-20（FP-1 A／FP-2 C／FP-3 A）**：v1 交付範圍為
> **Claude Code 單一 Host**。Codex 為 known-but-not-delivered
> （`BLOCKED_UPSTREAM_IDENTITY_CHANNEL`）：契約仍認識它、設定面（install／
> uninstall／shadow／health）照常評估，但產不出 HostSessionBinding，
> 一律回 `HBV1_HOST_BLOCKED_UPSTREAM`。Codex 與真正的 cross-host 能力見
> `CARD-EMEM11B-CODEX-CROSS-HOST-20260920`。
> **SSP-295 的進入條件以收斂後的單 Host DoD 為準**，不等 Codex。

> **切片 3 收線（2026-09-20）**：delivery `fa0959a`，定點 review **GO**
> （P0/P1/P2/P3 全 0）。回歸：3a 26/26、3b 33/33、3c 49/49、39 支 validators
> 全過。repair 歷程：repair-02 `756f005`（GO）→ scope correction `263c048`
> （NO_GO）→ repair-03 `6f042d9`（四筆 CLOSED）→ repair-04 `fa0959a`（GO）。
>
> **DoD 已全部成立（2026-09-20）**：最後一項「已交付 Host（Claude Code）有
> 真人實測」已完成並判 **ACCEPTED_GO**。在真的 Claude Code v2.1.278
> session 中實測：SessionStart hook 由真 Host 觸發、hook 與 MCP server 看到
> 同一個 native session id、write→read→closeout 全程經 MCP 進 Store（獨立
> SQLite 連線佐證）、重啟後資料存活且新 session 不沿用舊 identity、缺可信
> binding 時以 `MCP_NO_SESSION_RECORD` fail closed 且未動到任何資料、
> doctor 0 FAIL。證據包：
> `.work/handoff/EMEM11-HUMAN-ACCEPTANCE-20260920.md`。
> **本卡不再阻擋 SSP-295。**
>
> 仍未收治（不在本卡範圍）：產品尚未可獨立安裝（`contract.rb` 的 spec 路徑
> 指向 repo 內）、session state 檔無清理路徑、doctor 的 hook WARN 無法收斂。

# EMEM-11｜Personal Memory Runtime & Host Binding v1

## 定位

這不是 SSP-323 的補丁，也不是第五個 SSP-323 slice。

SSP-323 已封的是 Personal Memory Core：
- historical comparison
- organizational value assessment
- platform-neutral / local-first portability
- weekly review cycle
- batch UX / closeout semantics

EMEM-11 補的是第一版正式產品的 **local runtime + host integration layer**：
把已驗收的 Personal Memory contract 變成 Host 可以在每個受支援專案中穩定使用的本機能力。

v1 正式交付範圍（`supported_hosts_v1`，Owner 裁決 2026-09-20 收斂）：

```text
Anthropic Claude Code
```

已知但**本版不交付**（`blocked_hosts_v1`）：

```text
OpenAI Codex — BLOCKED_UPSTREAM_IDENTITY_CHANNEL
```

Codex 仍是契約認識的 Host：host profile、設定探索、install／uninstall／shadow／
health 的評估全部保留，但它產不出 `HostSessionBinding`（`HBV1_HOST_BLOCKED_UPSTREAM`）、
Runtime 授權閘也不收它的 binding、installer 預設不交付它。解除條件與原本的
cross-host 驗收見 `CARD-EMEM11B-CODEX-CROSS-HOST-20260920`。

其他 AI Host（ChatGPT app / Gemini / 其他）一律不列 v1 compatibility promise，不建立假抽象。

---

## 已查證的外部能力

### Codex

官方文件已確認：

- 使用者層級設定：`~/.codex/config.toml`
- 使用者層級全域指示：`~/.codex/AGENTS.md`
- 使用者層級 lifecycle hooks：`~/.codex/hooks.json` 或 config 內 `[hooks]`
- `SessionStart` 可取得至少 `session_id` / `cwd` / `source` 等欄位並注入 additional developer context
- 多個 hook source 會合併載入；高優先層不會整組取代低優先層 hook
- MCP 支援 local STDIO server；user config 可配置 `[mcp_servers.<name>]`
- project `.codex/config.toml` 的一般設定優先於 user config，因此 installer / doctor 不得假設 user config 永遠不受 project 影響
- `AGENTS.md` 是 instruction context，不是 permission / memory authority

官方參考：
- https://developers.openai.com/docs/hooks
- https://developers.openai.com/docs/extend/mcp
- https://developers.openai.com/docs/config-file/config-basic
- https://developers.openai.com/docs/agent-configuration/agents-md

### Claude Code

官方文件已確認：

- 使用者層級 settings / hooks 套用所有 projects
- `SessionStart` 可取得 `session_id` / `cwd` 等 session context
- hooks 在 user / project / local scopes 合併
- MCP 支援 user scope 與 local STDIO server
- MCP scope precedence 可能讓 local / project definition shadow user definition，因此需 namespaced identity + doctor / conflict detection
- `CLAUDE.md` / user memory 是 instruction context，不是 Personal Store authority

官方參考：
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/mcp
- https://code.claude.com/docs/en/memory

---

## 既有 repo donor，直接重用、不重做

### Organizational Memory OS

```text
SSP-323 / EMEM-09
→ Personal Memory Core / portability / weekly review

SSP-307
→ Codex native event vocabulary / mapping donor

SSP-308
→ Claude Code native event vocabulary / mapping donor

SSP-309
→ Codex / Claude Code conformance pattern donor

SSP-324
→ Personal → Company export / Minimal Evidence Package boundary
```

SSP-307～309 是 AI Work Record native event adapter，不等於 Personal Memory Host Binding；只吸收 event vocabulary、correlation 與 conformance 模式，不假裝它們已完成 Personal Store、MCP、installer 或 cross-host memory。

### AI Core donor

可吸：

- candidate != canonical
- immutable provenance / source snapshot
- dedup / idempotency
- correction / history preservation
- bounded recall / context discipline
- local-first memory failure cases

不可直接搬：

- `.memory` / `.founder-vault` physical layout
- JSONL 當公司產品正式 store authority
- developer task / branch / worktree / runtime-session semantics
- AI Core 完整 runtime per employee

---

## v1 工程裁決

以下是 **產品工程裁決**，不是 Codex / Claude 官方要求。

### 1. One employee, one Local Personal Store

```text
Codex ─┐
       ├→ same Local Personal Store
Claude ┘
```

禁止：
- per-host store
- per-project store
- vendor memory as truth

### 2. Store implementation baseline：SQLite + WAL

原因：

- 同一台員工電腦上的多個 Host / MCP process 需共享同一份資料
- 需要 transaction、idempotency、unique identity、revision / closeout consistency
- SQLite WAL 適合 local multi-process readers + serialized writes
- 不引入外部 DB service / daemon / server dependency

這是 v1 baseline；若施工前發現 measured blocker，必須回 Owner 做 spec-freeze，不得自行換 storage engine。

SQLite 官方參考：
- https://www.sqlite.org/wal.html
- https://www.sqlite.org/lang_transaction.html

### 3. Host 不可直接碰 DB

唯一合法路徑：

```text
Codex / Claude Code
        ↓
Personal Memory MCP
        ↓
Deterministic Personal Memory Runtime
        ↓
SQLite Personal Store
```

Host instruction / Skill / hook 不得直接改 SQLite。

### 4. Local STDIO MCP 是 v1 Host access surface

共用一個 namespaced Personal Memory MCP contract，至少承載：

- resolve / create host-session binding
- permission-aware bounded recall
- capture Evidence / WorkRecord input
- create / update PersonalMemoryCandidate path
- correction / supersession proposal path
- weekly review due / closeout operations
- health / version / capability query

MCP server 不取得 Company Canonical writer authority。

### 5. SessionStart bootstrap

Codex / Claude Code 的 user-level `SessionStart` 只做 deterministic bootstrap：

```text
host
+ host_session_id
+ cwd
        ↓
resolve employee
resolve project/workspace context
resolve effective permission scope
resolve current weekly review period
check runtime / store / MCP health
        ↓
HostSessionBinding
        ↓
small additionalContext / status
```

不要在 hook 裡做完整 recall、LLM summarization 或 weekly distillation。

### 6. Project context 只能限縮、不能擴權

正式 invariant：

```text
GLOBAL_HARNESS_NE_GLOBAL_MEMORY_VISIBILITY
PROJECT_CONTEXT_MAY_NARROW_BUT_NOT_WIDEN_MEMORY_ACCESS
HOST_INSTRUCTION_NE_MEMORY_AUTHORITY
HOST_NATIVE_MEMORY_NE_PERSONAL_TRUTH
MISSING_OR_CONFLICTED_HOST_BINDING_FAILS_CLOSED
```

### 7. Weekly Grill 不新增 background AI daemon

SSP-323 已有 review-period / cadence contract。

v1 由 SessionStart / explicit command 檢查：
- current review period
- due state
- closeout state

若本週 review 已 due 且未 close，Host 顯示 due / catch-up；不用另造常駐思考型 Agent。

---

## Design Freeze（Slice 1 開工前置條件，Owner 已裁決 2026-09-18）

以下六點為 Owner 對 CC 評估的逐點裁決，**全部是 EMEM-11 本身的施工約束，
不是新 capability，不另開卡**。Slice 1 開工前須全部成立。

### A｜Local MCP 只服務本機已綁定的 Host（P0 邊界）

EMEM-11 的 local MCP 必須明寫成「只服務本機已綁定 HostSessionBinding 的
Personal Host」。`stdio` 本身沒有網路 listener，這正好適合作為 v1 的 hard
boundary。**不得因 support／doctor／debug 加 HTTP tunnel、remote query 或
company-side forwarding**，否則會直接繞過 SSP-324 的 reverse-access 禁令。
這一條必須有負例。

### B｜`supported_hosts_v1 ⊂ runtime_policy.optional_executors`

`optional_executors` 是 core contract 的「可當 executor 的 vocabulary」，
v1 supported hosts 是 delivery scope，兩者不同層。正式寫成子集關係，
**不修改既有六個 executor**，因此不重開 SSP-323 切片 3。

### C｜HostSessionBinding 不得另造第二套 provenance vocabulary

`HostSessionBinding.host` / `host_session_id` 的正式 mapping 直接是既有的
`executor_ref` / `executor_session_ref`。HostSessionBinding 可以額外保存
`cwd` / `project_ref` / `effective_scope`，但 **executor identity 必須引用
既有欄位**。這正是先前 review 已抓過的「第二份語意清單」問題。

### D｜SQLite constraint 是 enforcement，不是 authority

`review_period_id`、terminal closeout 唯一性、promotion idempotency 都要
**從 `weekly_review_cycle` contract derive**。不得在 DB migration 裡另寫
一套「一週唯一」語意。資料庫只能 enforce 已存在的 identity / uniqueness。

### E｜Owner 對 `FORBIDDEN_BY_DEFAULT` 的授權範圍（限定寫法）

不是「Owner 允許跨過所有 `FORBIDDEN_BY_DEFAULT`」，而是：

> Owner 對 EMEM-11 這個 bounded capability 明確授權新增一個 **local
> embedded store、deterministic runtime writer、local host binding**；
> 權限僅限 Personal scope，**不取得 Company Canonical / Promotion /
> Acceptance authority**。

這樣 review 不會每輪重問，也不會變成未來別人拿來當總豁免。

### F｜CLI 可無 Host 使用，但不得成為 DB bypass

```text
Codex / Claude → MCP ─┐
                      ├→ same Personal Memory Runtime → SQLite
CLI / doctor ─────────┘
```

CLI 可無 Host 使用（`doctor` / `inspect` / `export` / `weekly-review` /
local maintenance），但**同樣走 Runtime 的 policy / transaction 層，不可
direct SQL**。這樣 vendor 消失時 Personal Store 仍是可用產品，而不是寄生
在 Codex / CC 上。

### 總 invariant（一次釘死 A 與 F）

```text
HOST_BINDING_IS_AN_ADAPTER_NOT_THE_RUNTIME
LOCAL_CLI_AND_HOST_MCP_SHARE_THE_SAME_RUNTIME_AUTHORITY
NO_REMOTE_PERSONAL_STORE_ACCESS_SURFACE
```

---

## Slice 1｜Local Personal Store Runtime

### Scope

- SQLite schema
- WAL mode / connection policy
- schema version / migration receipt
- transaction boundaries
- unique IDs / idempotency
- immutable revision / supersession linkage
- review-period / closeout uniqueness
- HostSessionBinding storage
- deterministic permission check seam
- MCP server base interface

### 必須重用

- PersonalMemoryCandidate / Record 的既有 machine-readable contract
- SSP-323 historical comparison / org-value / portability / weekly review
- existing correction / supersession
- existing permission-before-retrieval / ownership modes

### Hard stops

- 不建立第二套 Personal Memory lifecycle
- 不讓 DB schema 反過來成 domain authority
- 不先做 vector DB / graph DB
- 不做 always-on AI worker
- 不把 SQLite 暴露給 Host direct SQL

---

## Slice 2｜Codex + Claude Code Host Binding

### Codex

- safe merge user MCP entry
- safe merge user SessionStart hook
- stable namespaced server / hook identity
- bootstrap with host session id + cwd
- project config / hook conflict detection
- trust / disabled-hook detection
- uninstall 只移除本產品 own entries

### Claude Code

- safe merge user-scope MCP
- safe merge user SessionStart hook
- stable namespaced server / hook identity
- bootstrap with host session id + cwd
- detect local / project MCP shadowing
- uninstall 只移除本產品 own entries

### Common

- Host Adapter 不能取得 Personal Memory governance authority
- project-specific instruction file 只能提供 context / narrowing
- Host binding broken / shadowed / incompatible → fail closed or explicit degraded state；不得 silent fallback 到 vendor memory

---

## Slice 3｜Cross-Host Conformance / Installer / Doctor

### Installer

一個產品 installer：

```text
omos-personal-memory install
```

負責：
- initialize local store
- install runtime / MCP executable
- merge Codex user binding
- merge Claude Code user binding
- preserve existing user config
- emit installation receipt

### Doctor

```text
omos-personal-memory doctor
```

至少驗：

- store exists / writable
- SQLite schema version
- migration state
- MCP executable/version
- Codex MCP visible
- Codex SessionStart hook active
- Claude MCP visible
- Claude SessionStart hook active
- MCP shadow / conflicting names
- binding bootstrap
- project narrowing
- weekly review period continuity
- uninstall / rollback metadata

### Same-store acceptance（v1 範圍：Claude Code）

> **Owner 範圍裁決 2026-09-20**（`.work/CARD-EMEM11-SCOPE-FREEZE-20260920.md`，簽
> FP-1 A／FP-2 C／FP-3 A）：v1 交付範圍收斂為 Claude Code。原本的第 1、2 項
> **Codex ↔ Claude Code cross-host 實測整條搬到
> `CARD-EMEM11B-CODEX-CROSS-HOST-20260920`**（狀態 BLOCKED，等上游提供可信
> native session identity channel），**不是改寫成別的能力**——並行 session
> 共用同一 store 值得驗，但那不是 cross-host。

必須實測：

1. 同一 Host 的兩個並行 session（同 cwd、不同 native session id）使用同一
   Local Personal Store，不互相覆蓋 identity、不做 memory migration。
2. （原 Codex ↔ Claude Code 雙向 cross-host 實測 → 移至 EMEM-11b，此處不再列為
   v1 驗收項。）
3. Project A → Project B 不重新建 store、不重新定義 lifecycle。
4. Project B 比 A 權限小時，只能少看，不能擴權。
5. Host restart / resume / compact 不產生 duplicate weekly closeout / Promotion。
6. 同一 review period 在同一 Host 的並行 session 間切換仍維持同一 identity。
   （原為「在兩 Host 間切換」——跨 Host 部分隨 Codex 一併移至 EMEM-11b。）
7. MCP / hook broken 或 shadowed 時明確失敗，不 silent fallback。
8. install → upgrade → uninstall → reinstall 不破壞 Personal Store truth。
9. vendor-native memory on/off 不改 Personal Store canonical semantics。

---

## Slice 3 開工規劃（2026-09-20）

### 0. 假設與目標確認

- **目標**：把 EMEM-11 從「契約層」推到**可安裝、可診斷、可實際使用的實物**。
  這一片要交出真的會開啟 SQLite、真的被 Host 以 stdio 呼叫、真的讀寫使用者
  設定檔的程式。
  （原文為「可跨 Codex／Claude Code 實際使用」「真的被兩個 Host 呼叫」——
  Owner 裁決 2026-09-20 後 v1 交付 Host 只有 Claude Code。）
- **邊界**：v1 交付 **Claude Code 單一 Host**；Codex 保留 profile 與設定面
  評估但不交付（見 EMEM-11b）；不新增 Jira 卡；不推翻切片 1／2 的
  契約與已接受裁決；不碰同事的正式設定（安裝／卸載測試一律在隔離的 HOME）。
- **驗收**：契約測資與實際操作證據**分欄計算**，不混算 PASS；三組驗收（安裝與復原／
  Doctor 與失敗診斷／並行 session、同一 Store 與跨專案）各自要有實物證據。
- **前置決策**：產品實作語言與 runtime（見 §5），需 Owner 裁決後才動手。

### 1. 實體交付對照（開工前盤點，2026-09-20 實測）

全庫掃描結果：**無 `bin/`、無 `src/`、無任何套件宣告檔**
（`package.json` / `pyproject.toml` / `Gemfile` / `Cargo.toml` 皆不存在）。
`scripts/` 底下 39 支全部是 validator，加一支 `build_aiwr_capture_batch.rb`
（屬 AI work record 線，與 Personal Store 無關）。

| 必須存在的能力 | 開工前要回答的問題 | 現況 |
|---|---|---|
| 本機 Store 與讀寫入口 | 哪個程式真的開啟資料庫、提交交易、重啟後讀回？ | **NOT_IMPLEMENTED**。全庫唯一出現 `sqlite` 的位置是 `scripts/validate_personal_memory_runtime_contract.rb` 裡的契約**字串值** `SQLITE` / `WAL`。沒有任何程式開啟過資料庫，也沒有任何 schema DDL。 |
| 本機 MCP 與 CLI | 哪個 executable 被兩個 Host 呼叫？CLI 是否走同一套治理與寫入邏輯？ | **NOT_IMPLEMENTED**。`command_ref: OMOS_PERSONAL_MEMORY_MCP` 只是 spec 與 fixture 裡的**符號 token**，repo 內沒有任何地方把它解析成命令列或 binary。卡片指名的 `omos-personal-memory` CLI 不存在。無 MCP／JSON-RPC 實作。 |
| Host 啟動與設定整合 | 哪些已是可執行程式，哪些仍只是 normalized fixture？ | **全部是 fixture**。切片 2 驗的是一段 normalized 的 install / uninstall / effective config **三段式快照**，由測資直接提供；沒有任何程式讀寫 `~/.codex/` 或 `~/.claude/` 的實際設定檔，也沒有設定探索邏輯。 |
| Installer／doctor | 實際要安裝、檢查哪些檔案與程序？各自重用哪個既有 evaluator？ | **NOT_IMPLEMENTED**。無安裝腳本、無安裝 receipt 產生器。卡片列的 doctor 13 項檢查目前**對實物的覆蓋率為 0**。 |

**結論**：切片 1／2 交付的是契約、共用 evaluator、fixtures 與常設驗證器，全部成立；
但 **SQLite、MCP、本機安裝目前一行可執行程式都沒有**。缺口對回主卡原有責任，
在本卡內排實作順序，不改稱 conformance，也不推給 SSP-295。

### 2. 可重用資產（要接線，不要重寫）

這一片的核心設計原則：**實作產出的東西，要能直接餵進切片 1／2 既有的 evaluator
受審**，而不是另寫一套「自報成功」的檢查。

| 既有資產 | 在切片 3 的角色 |
|---|---|
| `personal_memory_runtime` 契約 | 實作的規格來源（WAL / migration 鏈 / 交易 / id / revision / closeout） |
| `validate_personal_memory_runtime_contract.rb` 的 `runtime_log_failure` | **runtime oracle**：真實 store 每次操作寫一筆 operation journal，conformance 把整段 journal 丟進去判定 |
| `scripts/lib/personal_memory_resource_evaluator.rb` | 落地列的本體判定（support／verification／acceptance／lifecycle） |
| `scripts/lib/weekly_closeout_history.rb` | closeout 唯一性與 promotion idempotency |
| `scripts/lib/host_session_binding_shape.rb` | SessionStart 產出的 binding 形狀 |
| `scripts/lib/personal_memory_host_binding.rb` | **installer oracle**：實際安裝前後的設定快照丟進 `scenario_failure` 判定 safe-merge、shadow、health |
| `personal_memory_host_binding_v1.host_profiles` | 安裝目標、registration id、`required_health` 詞彙 |

**Owner 更正（2026-09-20）：治理必須發生在落地之前，operation journal 是證據、
不是事後的替代保護。** 我原本的寫法（「產出 journal 交給 evaluator 判定」）會讓
該拒絕的寫入先落地、事後才被評分，方向是錯的。正確做法是：

- **正式寫入前**，runtime 直接呼叫既有共用治理 evaluator；被拒絕的寫入**不進交易**，
  或在同一交易內 rollback，資料庫裡不會出現該筆。
- operation journal 仍然產出，但它的角色是**可重播的證據**，供事後審計與 conformance
  比對，不是保護機制本身。
- **驗收不得只驗自己產出的 journal**：必須以**實際資料庫讀回**、**rollback 實測**、
  **重啟後持久化**三者確認。

installer 同理：safe-merge 判定在寫入使用者設定**之前**完成，失敗就不落地；
before/after 快照是證據。

### 3. 三組驗收（不增加新卡，契約測資與實物證據分欄）

| 驗收組 | 必須取得的證據 |
|---|---|
| **A 安裝與復原** | 在隔離 HOME 實際 install → reinstall → upgrade → uninstall；保留非本產品設定與個人資料；中途失敗必須停止或復原，不得留下半套卻回報成功（以注入失敗點實測）。 |
| **B Doctor 與失敗診斷** | 讀實際設定檔、解析實際啟動目標、實際執行健康檢查。「設定存在」「程序能啟動」「Store 能使用」必須是三種不同結果；缺 executable／被同名設定遮蔽／hook 未啟用各自要有實測失敗案例，不得靠 caller 自報。 |
| **C 並行 session、同一 Store 與跨專案** | 同一 Host 的兩個並行 session（同 cwd、不同 native session id）對同一個 Store 雙向往返，各自 binding 不被對方覆蓋；切換專案不得擴權；retry／重啟不得產生第二筆相同提交或第二次 terminal closeout。記錄實際測試的 Host 版本與使用入口。**這一組不叫 cross-host**——Codex ↔ Claude Code 的 cross-host same-store 驗收在 EMEM-11b。 |

v1 只驗 Claude Code（Owner 裁決 2026-09-20；Codex 為 known-but-not-delivered，
見 `personal_memory_runtime.blocked_hosts_v1`）。**沒實測過的入口不得因品牌相同
一併宣稱支援；被標為 blocked 的 Host 也不得因為設定寫得進去就算交付。**

### 4. 實作順序（同一張卡內分三階段，非三張卡）

- **3a｜Store + Runtime + CLI**：schema DDL、migration receipt、WAL/連線政策、
  交易邊界、id/idempotency、revision/supersession、closeout 寫入；CLI 走同一套
  治理層（`no direct DB access path`）。產出 operation journal。
- **3b｜MCP server + Host 啟動整合**：stdio MCP server 暴露同一 runtime；
  SessionStart 產生 HostSessionBinding；實際讀寫 Codex／Claude Code 設定探索。
- **3c｜Installer / Doctor / 並行 session conformance**：三組驗收與證據收集。

### 5. 實作語言與 runtime — Owner 已裁決（2026-09-20）

**裁決：選 Ruby，但採受維護的 Ruby 3.4 系列 + Bundler 鎖版 + 官方 MCP Ruby SDK
+ 新版 sqlite3 gem；不使用系統 Ruby 2.6／sqlite3 gem 1.3.13。**

選 Ruby 的主要理由是**直接重用既有共用治理 evaluator**，避免新增 Python 版治理
邏輯或跨語言橋接。

**更正我先前規劃表中的錯誤**：原表寫「Ruby 無官方 MCP SDK，須自寫 JSON-RPC
stdio」——**這是錯的**。官方 `mcp` gem 存在，本次已實際安裝並載入（1.5.1），
`MCP::Server::Transports::StdioTransport` 可用。該錯誤曾是我把選項推向 Python
的主要理由，特此更正。

#### 鎖定的環境（產品自帶設定與 lockfile，不依賴全域）

| 項目 | 值 |
|---|---|
| Ruby | 3.4.10（Homebrew `ruby@3.4`，**keg-only 不連結**，系統 `/usr/bin/ruby` 2.6 未受影響） |
| Bundler | 4.0.21，`bundle config set --local path vendor/bundle` |
| MCP SDK | `mcp` 1.5.1（官方） |
| SQLite driver | `sqlite3` 2.9.6（arm64-darwin 預編譯） |
| 產品路徑 | `product/personal-memory/`（`Gemfile` / `Gemfile.lock` / `.ruby-version`） |

#### 3a 前置預檢結果（隔離環境，`product/personal-memory/preflight.rb`）

**12/12 PASS**：Ruby 版本、sqlite3 gem、mcp gem 載入、SQLite 實際版本、
`journal_mode=WAL` 生效、`busy_timeout` 可設、`BEGIN IMMEDIATE`+COMMIT 落地、
ROLLBACK 真的丟棄、UNIQUE 違反會拋出、關閉後重開讀得回、WAL 隨檔案持久、
MCP stdio transport 類別存在。

**既有 39 支 validator 在 Ruby 3.4.10 下 0 失敗**（對照系統 Ruby 2.6 亦 0 失敗），
無相容性阻礙。

#### SQLite 版本檢查（Owner 指定項，實測結果值得單獨記錄）

WAL-reset 在多連線同時寫入／checkpoint 的罕見情況下可能造成資料庫損毀，
修復於 **3.51.3**。同一台機器三個來源：

| 來源 | 版本 |
|---|---|
| 系統 `sqlite3` CLI | 3.51.0 ← **低於修復版本** |
| Python stdlib `sqlite3` | 3.51.0 ← **低於修復版本** |
| Ruby `sqlite3` gem 2.9.6（產品實際連線） | **3.53.2** |

三者不同，證實「不能只看系統指令或套件名稱」。**必須由產品實際開啟的連線
查 `SELECT sqlite_version()`**——此項已進 `preflight.rb`，並將納入
installer 與 doctor 的常設檢查。

**誠實代價**：預編譯 gem 在本機可用，不代表**目標電腦的安裝已驗過**。
installer 不得假設每位同事都已有合適版本的 Ruby；取得與鎖定 Ruby 3.4 的方式
本身是 3c installer 的交付項，必須實測。

### 6. `transaction.mode` 實作前置（不升級既有 P2）

切片 1 的 P2「契約未限制 `transaction.mode`」維持 defer，不重審。但實作層必須明確
定義競寫／失敗／重試行為，採**既有機制**：

- 寫入一律 `BEGIN IMMEDIATE`（避免 upgrade deadlock）
- `PRAGMA journal_mode=WAL`、`PRAGMA busy_timeout=<ms>`
- `SQLITE_BUSY` 時**有上限的重試**，且重試沿用**同一把 idempotency key**——
  切片 1 既有契約已保證「重放必須落回同一列」，因此不需要、也不會新造交易管理器
  （`FORBIDDEN_BY_DEFAULT: new ledger/registry/FSM/DB/writer/runtime`）。

### 7. Minimum Sufficient

**why_not_less** — DoD 明文要求 installer / doctor deterministic acceptance、
**Claude Code 真人實測**（Owner 裁決 2026-09-20 前為「兩個 Host 真人實測」，
Codex 部分連同 cross-host same-store 實證一併移至 EMEM-11b）、同一 Store 在
並行 session 下的實證。少於「一支三個介面（CLI／MCP／installer）
共用的 runtime」就交不出這些。

**why_not_more** — 明確不做：常駐 daemon、background reasoning agent、vector DB、
per-project／per-host store、central Personal DB、新的交易管理器、Codex 與
Claude Code 以外的 Host、GUI、自動更新。

**do_not_absorb** — 不吸收：SSP-295 真人工作情境驗收、vendor-native memory 自身行為、
公司端 promotion 路徑、EMEM-10 的 evidence package 產生。

### 8. 逐檔預估行數（分類報，超出既有規範的理由先講）

| 類別 | 檔案 | 預估 |
|---|---|---|
| 產品程式 | store（schema/migration/連線/交易） | 350–450 |
| 產品程式 | runtime 治理層（權限 seam／scope 推導／binding） | 150–200 |
| 產品程式 | CLI（init/write/read/closeout/doctor/install） | 200–250 |
| 產品程式 | MCP stdio server | 200–250 |
| 產品程式 | installer（設定探索／safe merge／rollback／uninstall） | 250–300 |
| 產品程式 | doctor（13 項對實物的檢查） | 200–250 |
| conformance | 把實際操作轉成既有 evaluator 吃的形狀 + 三組驗收 | 250–350 |
| 規格增修 | executable 解析、安裝路徑、doctor 結果詞彙 | 80–150 |
| 測資 | 隔離 HOME 的設定樣本、失敗注入案例 | 150–250 |
| 共用程式搬移 | **0**（重用既有四支 lib，不搬移） | 0 |
| **合計** | | **2,030–2,550** |

**超出既有規範的說明（依指示先講，不完工才補）**：切片 1 約 913 行手寫、切片 2 約
775 行，兩片都是**只交契約不交程式**才那麼小。切片 3 是 EMEM-11 第一片要交出可執行
產品的切片，主卡本來就要求 installer、doctor、MCP executable 與實機實測（原文為「跨 Host 實測」，
Owner 裁決 2026-09-20 後收斂為已交付 Host），
這些責任在原卡、不是新增需求。切片 1「不按 store／surface 人工二分、只按真正共用接點
抽取」的裁決保留——因此**不會**為了行數把這片拆成人工邊界，而是按 §4 的
3a／3b／3c 實作順序推進，每階段可獨立回報與檢查。

## 與其他 MVP 卡的關係

```text
SSP-323 / EMEM-09 Personal Core        ACCEPTED_GO
        │
        ├───────────────┐
        ▼               ▼
SSP-324 / EMEM-10   EMEM-11
Evidence Package    Runtime & Host Binding v1
        │               │
        └───────┬───────┘
                ▼
SSP-295 / EMEM-06 真人產品部 Pilot
                ▼
SSP-286 MVP closure
```

EMEM-10 與 EMEM-11 可平行施工；SSP-295 full product pilot 必須等兩者都到可驗收狀態。

---

## v1 不做

- ChatGPT app
- Gemini
- 其他 AI host
- central Personal DB
- remote Personal Store
- vector DB
- knowledge graph runtime
- background reasoning agent
- per-project store
- per-host store
- direct Host SQL
- vendor memory migration
- 重開 SSP-323

---

## DoD

EMEM-11 只有在以下全部成立才可進 SSP-295 full pilot：

> **Owner 範圍裁決 2026-09-20（FP-1 A／FP-2 C／FP-3 A）後的 normative DoD。**
> 原文要求「兩個 Host 都有真人實測」與「cross-host same-store 實證」；Codex
> 已收斂為 known-but-not-delivered，該兩項連同 Codex 一併移至
> `CARD-EMEM11B-CODEX-CROSS-HOST-20260920`，**不再是本卡進 SSP-295 的條件**。

- Slice 1/2/3 全部 machine-readable contract / fixtures / validators 或等價可重播驗證完成
- installer / doctor 有 deterministic acceptance
- **已交付 Host（Claude Code）有真人實測**
- **同一 Store 在並行 session 下** / permission-narrowing / review-period idempotency 實證通過
- blocked host（Codex）在三個層級都真的擋得住：bootstrap 產不出 binding、
  Runtime 授權閘拒收繞過 bootstrap 的 binding、installer 預設不交付
- no direct DB access path
- no second lifecycle / second Personal authority
- repo regression 全綠
- independent review GO

