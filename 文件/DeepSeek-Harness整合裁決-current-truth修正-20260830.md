# DeepSeek Harness 整合裁決｜Current Truth 與 Personal Memory 範圍補正

日期：2026-08-30

狀態：

```text
CURRENT_TRUTH_AMENDMENT
OUT_OF_SCOPE_FOR_PERSONAL_MEMORY_HARNESS
SEPARATE_RUNTIME_RESEARCH
IMPLEMENTATION_DEFERRED
NO_IMPLEMENTATION_AUTHORIZATION
NO_INSTALL_AUTHORIZATION
NO_RUNTIME_EXECUTION_AUTHORIZATION
```

---

# 0. Scope correction

DeepSeek Harness不是Personal Memory Harness的施工項目。

正式關係：

```text
AI Core
= 保持完整，擁有Work／Task／Runtime／Review

Personal Memory Harness
= 只承接記憶Evidence、Candidate、Governance、Projection、Recall

DeepSeek Harness
= AI Core未來可能評估的optional runtime executor
```

即使未來AI Core使用DSH：

```text
DSH run／receipt／artifact
→ 可能成為Personal Memory的一種上游Evidence來源
```

也不代表Personal Memory Team要建立：

```text
DSH adapter
provider registry
runtime router
session bridge
hook
Agent Teams
Creator Mode
```

---

# 1. Still-valid DSH authority boundary

以下裁決維持有效：

```text
DeepSeek Harness
!= Knowledge Authority
!= Permission Authority
!= Canonical Writer
!= AI Core Work Authority
```

如果未來另案獲准，第一個候選profile仍至少：

```text
HEADLESS
ONE_SHOT
ASSIGNED_WORKTREE_ONLY
TELEMETRY_DISABLED
NO_WEB_UI
NO_EXTERNAL_MCP
NO_AGENT_TEAMS
NO_CREATOR_AUTO_MOUNT
NO_DYNAMIC_WORKFLOW
NO_NESTED_CODEX_OR_CLAUDE_SUBAGENTS
```

並維持：

```text
Runtime completed
!= AI Core accepted
!= Memory verified
!= Knowledge accepted
```

---

# 2. Current AI Core seam correction

AI Core舊有 generic provider extension四檔：

```text
scripts/execution_provider_extension.py
config/execution_provider_extensions.json
docs/execution-provider-extension.md
tests/test_execution_provider_extension.py
```

已由 accepted removal commit：

```text
38f7f7e6d95d4e77fbd426a458d7aa83a82dddb5
```

移除，且已在reviewed AI Core HEAD ancestry中。

因此禁止依舊文件重建同名或等價：

```text
provider registry
provider metadata database
universal runtime API
provider lifecycle FSM
formal dispatcher platform
```

未來若AI Core另案評估DSH，只能採runtime-native bounded execution seam；該工作由AI Core擁有，不由Personal Memory Harness擁有。

---

# 3. Personal Memory only needs the evidence boundary

對Personal Memory Team唯一相關的未來介面是：

```text
AI Core accepted／bounded runtime artifact or receipt ref
        ↓
OMOS RawEvidence semantics
        ↓
Personal Memory Candidate（若內容值得長期沉澱）
        ↓
Memory Governance／Acceptance
```

Personal Memory端不需要知道或管理：

```text
DSH Session
Profile／Bundle／Patch
Node process
credential route
runtime interruption
subagent lifecycle
workflow script
```

除非它們是追溯某一Evidence不可缺少的bounded provenance metadata。

---

# 4. Backlog disposition

原本：

```text
OMOS-DSH runtime adapter／trajectory／capability admission
```

對Personal Memory Harness全部改為：

```text
OUT_OF_SCOPE
AI_CORE_OR_PLATFORM_OWNED
NOT_A_MEMORY_FRONTIER
```

Personal Memory目前唯一下一步仍是：

```text
PMEM-00
AI Core Memory Surface／Authority Audit
```

DSH不得阻塞：

- Memory surface audit。
- Personal Memory Contract。
- Founder Vault projection contract。
- Recall／Context Pack contract。

---

# 5. Hard stops

禁止：

- 因Personal Memory需要Evidence就重建DSH integration platform。
- 讓DSH session／trajectory成Personal Canonical Memory。
- 將DSH exit 0當Memory Verification PASS。
- 將DSH hook或tool event直接promotion。
- 把DSH memory／team／workflow功能搬進Personal Memory Harness。
- 讓Personal Memory Team擁有runtime install、credential、sandbox或provider fallback。

---

# 6. Final disposition

```text
DSH research value
= retained

DSH runtime work
= AI Core／runtime-owned separate future card

Personal Memory relationship
= optional upstream Evidence source only

Current Personal Memory priority impact
= none
```
