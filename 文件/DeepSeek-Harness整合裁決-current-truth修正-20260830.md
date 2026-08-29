# DeepSeek Harness 整合裁決｜Current Truth 修正

日期：2026-08-30

狀態：

```text
CURRENT_TRUTH_AMENDMENT
SUPERSEDES_SEAM_ONLY
DRAFT_COMPLETE
REVIEW_REQUIRED
NOT_CANONICAL
NO_IMPLEMENTATION_AUTHORIZATION
NO_INSTALL_AUTHORIZATION
NO_RUNTIME_EXECUTION_AUTHORIZATION
```

被修正文件：

```text
文件/DeepSeek-Harness整合裁決與施工切片.md
```

Cross-repo基準：

```text
Organizational Memory OS
HEAD: 4926265e983ebd968dbaa827685c33000a47bc80

AI Core
reviewed HEAD: 87f6a16cf22642513730ea56530a8b5b1ce4ee99
```

本文件只修正一件事：

> 舊 DSH 整合文件引用的 AI Core `Execution Provider Extension` seam 已被正式移除；未來 DSH若獲准，只能透過 runtime-native thin adapter＋immutable request／receipt接入。

它不推翻 DSH 的 donor價值，也不授權重新啟動 DSH施工。

---

## 1. 仍然有效的裁決

以下全部維持：

```text
DeepSeek Harness
= Optional Runtime Executor
!= Knowledge Authority
!= Permission Authority
!= Canonical Writer
!= AI Core Work Authority
```

第一個候選 profile仍必須至少：

```text
HEADLESS / ONE_SHOT
ASSIGNED_WORKTREE_ONLY
TELEMETRY_DISABLED
NO_WEB_UI
NO_EXTERNAL_MCP
NO_AGENT_TEAMS
NO_CREATOR_AUTO_MOUNT
NO_DYNAMIC_WORKFLOW
NO_NESTED_CODEX_OR_CLAUDE_SUBAGENTS
```

第一階段仍採：

```text
process receipt first
sanitized event bridge only if proven necessary
```

仍禁止：

- DSH Session DB作AI Core或OMOS truth。
- Trajectory存在就推導Verification PASS。
- Agent Teams作預設query／execution topology。
- Creator Mode自動production enable。
- model-generated JavaScript無真實sandbox執行。
- DSH telemetry raw transcript預設外送。
- DSH plugin擴張Managed Policy Floor。
- DSH exit 0直接關閉AI Core工作或promote Knowledge。

---

## 2. 已失效的 seam

AI Core曾有：

```text
scripts/execution_provider_extension.py
config/execution_provider_extensions.json
docs/execution-provider-extension.md
tests/test_execution_provider_extension.py
```

這四檔已由 accepted removal commit：

```text
38f7f7e6d95d4e77fbd426a458d7aa83a82dddb5
```

移除，且移除已進目前AI Core HEAD ancestry。

所以舊文件中任何將下列視為 current integration seam 的敘述：

```text
execution_provider_extensions.json
execution_provider_extension.py
execution-provider-extension.md
provider extension registry
```

一律改讀為：

```text
SUPERSEDED_BY_AI_CORE_RUNTIME_NATIVE_BOUNDARY
```

禁止按舊文件重新建立同名或等價：

```text
provider registry
provider metadata DB
universal runtime API
formal dispatcher platform
provider lifecycle FSM
```

---

## 3. 新 current seam

唯一合法的候選方向：

```text
AI Core Markdown Task Card
        ↓
AI Core existing authorization
        ↓
Immutable ExecutionRequest
        ↓
DSH runtime-native one-shot adapter
        ↓
dsh / DeepSeek Harness native process
        ↓
Process result + optional sanitized native events
        ↓
Immutable ExecutionReceipt
        ↓
AI Core existing Work lifecycle
        ↓
Review / Verification / Acceptance
        ↓
Optional OMOS AGENT_RUNTIME RawEvidence Adapter
```

每一層責任：

| Layer | Owns | Does not own |
|---|---|---|
| AI Core Task Card | intent、scope、authorization、acceptance path | runtime-native session |
| ExecutionRequest | one invocation的bounded parameters | Work state、Knowledge authority |
| DSH adapter | preflight、invoke、collect、interrupt | routing priority、review、merge |
| DSH | native agent execution | AI Core Work、OMOS Knowledge |
| ExecutionReceipt | what executed / produced | correctness / acceptance |
| AI Core Work lifecycle | delivery/review/acceptance/integration | OMOS canonical knowledge |
| OMOS adapter | execution evidence admission | direct promotion |

---

## 4. Thin adapter contract

不再使用 provider extension platform。

DSH adapter最多只實作：

```text
preflight(request) -> PreflightReceipt
invoke(request) -> ProcessRef
collect(process_ref) -> ExecutionReceipt
interrupt(process_ref) -> InterruptReceipt
```

### Preflight必須檢查

```text
dsh executable
exact DSH version
Node version
effective profile
profile / patch digest
assigned worktree
main checkout rejection
tool/bundle allowlist
credential route
telemetry disabled
network policy
timeout / process tree strategy
```

任一不符：

```text
BLOCKED
```

不得：

- 自動安裝。
- 自動 `npx`／`pnpm add`。
- 自動登入。
- 自動改credentials。
- 自動改 `$DSH_HOME`。
- DSH不可用時fallback Codex／Claude。
- 在DSH內再nested route到Codex／Claude。

---

## 5. ExecutionRequest

DSH不取得自己的task truth。

Request至少引用：

```text
AI Core task card
Work ID
repository / worktree
base commit
root question
bounded context
allowed write paths
denied capabilities
profile digest
timeout / cost / token budget
credential route
sandbox policy
expected artifacts
verification commands
```

Request不得包含：

```text
acceptance_status
canonical_write_authorized
knowledge canonicality
```

---

## 6. ExecutionReceipt

第一階段只收：

```text
request ref
provider / runtime version
profile digest
start / end
exit code
terminal reason
stdout artifact
stderr artifact
result artifacts
changed paths
candidate commit
environment digest
errors
```

Formal invariant：

```text
DSH_EXIT_0
!=
WORK_VERIFIED
!=
WORK_ACCEPTED
!=
KNOWLEDGE_VERIFIED
!=
KNOWLEDGE_ACCEPTED
```

若verification未跑：

```text
verification = NOT_RUN
```

---

## 7. Sanitized event bridge

只有process receipt不能回答以下問題時，才可另開Stage B：

- tool provenance。
- nested child relation。
- token／usage attribution。
- failure reconstruction。
- interruption原因。

Stage B只能用out-of-tree、可卸載bridge，白名單輸出：

```text
native session id
sequence / time
event type
turn / step
provider / model
usage
tool name / outcome
terminal reason
parent / child relation
payload digest / artifact ref
```

預設禁止：

```text
full system prompt
raw user / assistant transcript
raw reasoning
full tool arguments / results
file contents
credentials
host absolute paths
```

Native event仍是execution evidence，不是Work state。

---

## 8. DSH current backlog disposition

| Slice | Current status |
|---|---|
| donor pin | COMPLETE |
| authority diff | COMPLETE |
| RawEvidence AGENT_RUNTIME fixture | MERGE_INTO_EXISTING_CONTRACT |
| Capability Admission fixture | MERGE_INTO_EXISTING_CONTRACT |
| AI Core provider adapter | BLOCKED / NOT_CURRENT_FRONTIER |
| Process receipt spike | BLOCKED_BY_EXECUTION_REQUEST_RECEIPT |
| Sanitized event bridge | DEFER |
| Dynamic Workflow | DEFER / TRIGGER |
| Agent Teams | REFERENCE_ONLY |
| Creator Mode | CANDIDATE_PRODUCER_ONLY |
| Nested Codex／Claude | BLOCKED |

存在本文件不代表任何卡已授權施工。

---

## 9. Cross-runtime consistency

DSH、Codex、Claude Code、Hermes共用的不是provider registry，而是：

```text
ExecutionRequest vocabulary
ExecutionReceipt vocabulary
RuntimeNativeEventReceipt vocabulary
```

各runtime保持native contract：

```text
Codex    → Thread / Turn / Item
Claude   → Session / Hook / Tool / Task signal
Hermes   → Session / Tool / LLM / optional Kanban signals
DSH      → SessionEvent / process / workflow / subagent native records
```

禁止強迫所有runtime假裝有相同：

```text
session
task
turn
worker
team
```

---

## 10. Required amendments in future AI Core work

本輪不修改AI Core。

未來若Owner明示授權，AI Core DSH相關文件只需做bounded amendment：

1. 將舊provider-extension refs標為superseded。
2. 指向Task Card→ExecutionRequest→runtime-native adapter→ExecutionReceipt。
3. 保留BLOCKED／no-install／no-runtime boundary。
4. 不復活已刪四檔。
5. 不新增provider registry／DB／platform。
6. 加入negative tests：
   - silent fallback。
   - profile drift。
   - main checkout execution。
   - nested runtime。
   - exit 0 but verification NOT_RUN。
   - telemetry unexpectedly enabled。

---

## 11. Hard stops

發現下列任一需求即停止：

- 需要重建provider extension。
- 需要第二套Work lifecycle。
- 需要DSH Session作persistent task identity。
- 需要Agent Teams共用checkout寫入。
- 需要Creator Mode自動mount production plugin。
- 需要raw trajectory無redaction保存。
- 需要DSH hook作唯一security gate。
- 需要DSH event直接驅動ACCEPTED／CLOSED。
- 需要AI Core或OMOS secret交給未admitted plugin。
- 需要改production或安裝runtime。

---

## 12. Final interpretation rule

閱讀舊文件時：

```text
保留：
DSH optional executor
headless one-shot
receipt first
no teams/workflow/creator/nested runtime
no Knowledge authority

替換：
provider extension seam
→ runtime-native thin adapter + request / receipt

維持：
BLOCKED
NOT_CURRENT_FRONTIER
NO_INSTALL
NO_RUNTIME
```
