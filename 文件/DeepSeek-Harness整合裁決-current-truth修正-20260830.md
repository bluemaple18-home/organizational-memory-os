# DeepSeek Harness 與公司員工個人記憶標準｜範圍補正

日期：2026-08-30

狀態：

```text
SCOPE_CORRECTION
SEPARATE_RUNTIME_RESEARCH
OUT_OF_EMPLOYEE_MEMORY_CORE
NOT_MVP_BLOCKER
NO_IMPLEMENTATION_AUTHORIZATION
NO_INSTALL_AUTHORIZATION
```

---

## 0. 補正目的

公司員工 Personal Memory Standard 的目標是：

```text
每位員工使用同一套記憶 contract與lifecycle
```

不是：

```text
每位員工安裝DeepSeek Harness
每位員工有一套Agent Runtime
記憶團隊負責Runtime Provider整合
```

因此 DeepSeek Harness（DSH）從 Employee Personal Memory core與current backlog移出。

---

## 1. DSH 仍然有效的定位

```text
DeepSeek Harness
= Optional backend executor / runtime donor
!= Employee Personal Memory Standard
!= Knowledge Authority
!= Personal Memory Authority
!= Permission Authority
!= Canonical Writer
```

DSH未來可在公司後端、私有環境或特定進階角色中執行：

- bounded extraction。
- candidate generation。
- counter-evidence search。
- evaluation／verification task。
- source adapter helper。

但執行結果仍只是 Evidence／Proposal。

```text
DSH COMPLETE
!= Personal Memory Accepted
!= Company Knowledge Accepted
```

---

## 2. 一般員工不依賴 DSH

普通員工的產品入口仍是：

```text
Outlook
Teams
Jira
Documents
Meetings
Web
Existing company systems
```

中央或地端服務負責把來源映射到：

```text
RawEvidenceEnvelope
→ ObjectLink / WorkRecord
→ PersonalMemoryCandidate
→ Governance
→ PersonalMemoryRecord
```

執行這些 worker時，可以用 deterministic code、任一合規模型或未來的 DSH；員工本人不需要知道或管理 runtime。

---

## 3. DSH 與共用記憶規格的唯一接點

若未來另案核准 DSH，唯一合法輸入／輸出是既有中立 contract：

```text
Authorized bounded input
→ Optional DSH executor
→ Process / sanitized execution receipt
→ Raw Evidence or Candidate Proposal
```

DSH不得：

- 定義每位員工的memory schema。
- 保存公司唯一personal memory truth。
- 直接寫PersonalMemoryRecord。
- 直接升TEAM／COMPANY Knowledge。
- 決定employee privacy mode。
- 以Session／Trajectory作WorkRecord或Memory authority。

---

## 4. 與 AI Core 的關係

AI Core保留完整，不因Employee Personal Memory Standard被拆分。

DSH若未來接入AI Core或其他backend runtime，是獨立 runtime research；AI Core本身也只可作Employee Memory中的developer-specific source／consumer adapter。

```text
AI Core runtime integration
!= Employee Memory core

DSH runtime integration
!= Employee Memory core
```

兩者都不得成為一般員工使用Personal Memory的前置條件。

---

## 5. 原 DSH 裁決仍保留的安全限制

若未來另案進行DSH spike，第一版仍至少：

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

且：

```text
process receipt first
sanitized event bridge only if necessary
no raw transcript default export
no silent provider fallback
no runtime completion → verification/acceptance
```

這些限制屬 runtime research，不得插隊 Employee Personal Memory Standard。

---

## 6. Backlog 裁決

Employee Personal Memory backlog不包含：

```text
DSH adapter
DSH profile implementation
DSH SessionEvent mapping
DSH Agent Teams
DSH Creator Mode
```

DSH只保留在：

```text
Separate Runtime Donor / Trigger Research
```

當以下都成立才重評：

1. Employee Memory core contract已穩定。
2. 有真實backend executor缺口。
3. deterministic／現有model worker不足。
4. security、privacy、retention與cost可量測。
5. 有獨立Owner approval。

---

## 7. 最終句子

```text
Employee Personal Memory Standard
must remain runtime-neutral.

DeepSeek Harness may execute a bounded task,
but it never defines what an employee memory is.
```
