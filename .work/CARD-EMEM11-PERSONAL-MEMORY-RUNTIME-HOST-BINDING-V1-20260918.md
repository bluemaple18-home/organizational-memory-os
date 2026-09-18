---
id: EMEM11-PERSONAL-MEMORY-RUNTIME-HOST-BINDING-V1-20260918
status: BACKLOG_READY_NOT_IMPLEMENTED
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
---

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
把已驗收的 Personal Memory contract 變成 Codex / Claude Code 可以在每個受支援專案中穩定使用的本機能力。

v1 正式支援範圍只包含：

```text
OpenAI Codex
Anthropic Claude Code
```

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

### Cross-host acceptance

必須實測：

1. Codex → Claude Code 使用同一 Local Personal Store，不做 memory migration。
2. Claude Code → Codex 同理。
3. Project A → Project B 不重新建 store、不重新定義 lifecycle。
4. Project B 比 A 權限小時，只能少看，不能擴權。
5. Host restart / resume / compact 不產生 duplicate weekly closeout / Promotion。
6. 同一 review period 在兩 Host 間切換仍維持同一 identity。
7. MCP / hook broken 或 shadowed 時明確失敗，不 silent fallback。
8. install → upgrade → uninstall → reinstall 不破壞 Personal Store truth。
9. vendor-native memory on/off 不改 Personal Store canonical semantics。

---

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

- Slice 1/2/3 全部 machine-readable contract / fixtures / validators 或等價可重播驗證完成
- installer / doctor 有 deterministic acceptance
- Codex 與 Claude Code 兩個 Host 都有真人實測
- cross-host same-store / permission-narrowing / review-period idempotency 實證通過
- no direct DB access path
- no second lifecycle / second Personal authority
- repo regression 全綠
- independent review GO

