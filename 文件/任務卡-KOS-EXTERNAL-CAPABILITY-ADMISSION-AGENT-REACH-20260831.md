# 任務卡｜KOS-EXTCAP-01｜External Capability Admission × Agent-Reach Donor

日期：2026-08-31

狀態：

```text
OWNER_ADMITTED_TO_BACKLOG
QUEUED_AFTER_CURRENT_CORE_FRONTIERS
DESIGN_AND_FIXTURE_FIRST
NO_IMPLEMENTATION_AUTHORIZATION
NO_INSTALL_AUTHORIZATION
NO_CONNECTOR_DEPLOYMENT
NO_EMPLOYEE_MEMORY_PRIORITY_CHANGE
```

## 0. Card identity

```yaml
id: KOS-EXTCAP-01
capability: External Capability Admission
priority: P1-A
responsibility:
  - DOMAIN_CORE
  - ENTERPRISE_GOVERNANCE
  - DETERMINISTIC_FIRST
source_repo: Panniantong/Agent-Reach
source_commit: 06c202b03400a7d31886bf4399213706da1a0324
source_license: MIT
```

## 1. Backlog placement

現有 `文件/待辦重整.md` 已將 External Capability Admission 標為：

```text
MISSING
P1-A
DOMAIN_CORE / ENTERPRISE_GOVERNANCE
```

本卡把 Agent-Reach 的成熟 prior art 登錄為 donor，但不插隊目前既有順序：

```text
1. Raw Evidence Contract
2. Document Adapter Mapping
3. Jira Adapter Mapping
4. Permission / Retention / Deletion Contract
5. Canonical Direct-Write Audit
6. 最新繁體中文互動 Architecture Canvas
7. KOS-EXTCAP-01
```

Employee Personal Memory 的下一個 review target 仍是 `EMEM-00 Scope / Ownership / Privacy Contract`。本卡是平台級 cross-cutting capability，不是 Employee Memory runtime 或來源擷取卡。

## 2. Root question

Knowledge OS 接入外部 CLI、MCP、API、browser bridge、crawler、transcriber 或其他 executor 前，如何先以 deterministic contract 回答：

```text
它是什麼能力？
目前哪個 backend 真的可用？
使用何種 credential／runtime／network？
會產生哪些 side effects？
失效時如何降級、修復、回退？
輸出如何進 Raw Evidence，而不是直接進 Canonical Knowledge？
```

## 3. Product / Domain Responsibility

External Capability Admission 是 Knowledge OS 應擁有的 domain responsibility，因為平台必須控制：

- 哪個外部能力允許被使用。
- 哪個 provider 目前健康。
- 誰授權安裝、登入、使用 credential 或 network。
- 哪些輸出可成為 Evidence。
- 失效、換 provider、撤權、刪除與 retention 如何處理。

底層工具本身仍是可替換 executor；其 package、MCP server 或 Agent 不取得 Knowledge Authority。

## 4. Existing seam

應接到現有：

```text
Source Adapter
RawEvidenceEnvelope
Permission / Retention / Deletion
Config Scope / Precedence
Minimum Telemetry / Cost
AnswerTrace / EvaluationReceipt
Canonical Single Writer
```

不得建立第二套 Evidence、Permission、Knowledge DB、Agent Registry 或 Runtime lifecycle。

## 5. Prior art teardown

固定來源：

```text
Panniantong/Agent-Reach@06c202b03400a7d31886bf4399213706da1a0324
MIT
```

Relevant donor files：

- `agent_reach/channels/base.py`
- `agent_reach/channels/__init__.py`
- `agent_reach/doctor.py`
- `agent_reach/probe.py`
- `agent_reach/config.py`
- `agent_reach/channels/twitter.py`
- `agent_reach/core.py`

值得吸收的工程語意：

```text
Channel
→ ordered backend candidates
→ real lightweight probe
→ OK / WARN / OFF / ERROR
→ active backend
→ repair prescription
```

關鍵細節：

- `which`／package existence 不等於可用；必須真正執行 bounded probe。
- 第一個 `WARN` 不應遮住後面真正 `OK` 的 provider。
- stale／unknown user override 不得隱藏健康 provider。
- 單一 channel exception 不得拖垮完整 health report。
- doctor output 必須 scrub URL credentials／secret-bearing error text。
- 不能安全驗證的登入態應標 `WARN`／`UNKNOWN`，不得假裝 `OK`。
- install 預設應可 dry-run；system mutation 必須另行明示。

## 6. Reuse Candidate

### Absorb

1. ordered backend candidate list。
2. user／scope override with safe fallback。
3. real health probe。
4. `OK / WARN / OFF / ERROR` state model。
5. active provider resolution。
6. per-provider failure isolation。
7. evidence timestamp／TTL。
8. repair prescription。
9. install dry-run／mutation manifest。
10. rollback／uninstall plan。
11. credential scrub 與 credential-scope metadata。
12. provider change history as operational evidence。

### Do not absorb

- 整包搬入 Agent-Reach CLI。
- 預設安裝其上游 scraper／browser／MCP tools。
- 自動讀瀏覽器 Cookie 或員工登入態。
- 把「能讀到網站」等同「合法且可進公司知識庫」。
- 繞過來源 Terms、license、ACL、retention、consent 或 offboarding。
- 讓 active backend projection 成為 permanent capability truth。
- 讓 tool output 直接寫 Canonical Knowledge。

## 7. Required resources

```text
ExternalCapabilityDefinition
ProviderCandidate
CapabilityHealthReceipt
CapabilityAdmissionDecision
InstallPlan
RepairPrescription
RollbackPlan
```

### ExternalCapabilityDefinition

```yaml
capability_id:
channel:
description:
allowed_scopes:
risk_class:
source_type:
required_permissions:
network_policy:
credential_policy:
output_contract:
```

### ProviderCandidate

```yaml
provider_id:
capability_id:
priority:
runtime:
version_constraint:
license:
source_repo:
install_kind:
auth_mode:
credential_scope:
side_effects:
fallback_rank:
```

### CapabilityHealthReceipt

```yaml
receipt_id:
capability_id:
provider_id:
probe_kind:
probe_version:
probe_request_digest:
started_at:
finished_at:
status: OK | WARN | OFF | ERROR
active_provider:
evidence_ttl:
redacted_observation:
error_class:
repair_prescription_ref:
config_snapshot_digest:
```

### CapabilityAdmissionDecision

```yaml
decision_id:
capability_id:
provider_id:
requester:
scope:
policy_version:
permission_decision:
health_receipt_ref:
terms_license_decision:
data_handling_decision:
allowed_operations:
forbidden_operations:
expires_at:
```

## 8. Truth boundary

```text
Capability Definition
= managed product configuration

Capability Health Receipt
= time-bounded operational evidence
!= permanent truth

active_provider
= rebuildable projection

external tool output
= Raw Evidence candidate input
!= Knowledge Candidate automatically
!= Canonical Knowledge
```

任何 provider 切換都不得改變 RawEvidenceEnvelope 的核心 identity／provenance／ACL requirements。

## 9. Deterministic First

以下應 deterministic：

- provider ordering。
- version／binary／config checks。
- bounded command probe。
- timeout／exit code／schema validation。
- state classification。
- credential scrub。
- TTL／staleness。
- install mutation manifest。
- rollback completeness。

模型只能協助：

- 對非結構化錯誤產生候選 repair explanation。
- source Terms／license 初步分類。
- ambiguous capability mapping 建議。

模型不得成為 admission／permission／credential enforcement boundary。

## 10. Required fixtures

1. 第一 provider `OK`。
2. 第一 provider binary 存在但 execution broken，第二 provider `OK`。
3. 第一 provider `WARN`，第二 provider `OK`；active provider 必須選第二個。
4. user override 指向不存在 provider；健康 provider 仍可被找到。
5. 全部 provider unavailable。
6. provider timeout／malformed output／non-zero exit。
7. provider exception 不拖垮其他 channel。
8. error output 含 credential URL；render 後不得洩漏。
9. health receipt 過期，admission 必須重跑或拒絕。
10. install dry-run 列出所有 filesystem／config／package mutation。
11. rollback plan 缺項時 admission fail closed。
12. tool 輸出成功，但缺 source／license／ACL metadata；不得進 Candidate／Canonical。
13. provider 切換後，同一 source evidence identity 不得被重複 mint 成兩筆 canonical facts。
14. Employee Memory 使用此能力時，仍受 `EMEM-00` privacy／ownership policy；不得因 provider admin 權限擴張可見範圍。

## 11. Human Review Requirement

以下必須 Owner／security／legal 或 data-governance review：

- 新 system package／daemon／browser extension。
- credential／Cookie／SSO／OAuth scope。
- external network／proxy。
- source Terms 或 license 不明。
- 高敏感 source／CLIENT scope。
- provider 可寫外部服務。
- uninstall／source deletion 無法完全回退。

純 local read-only、無 credential、固定 output schema 的 provider 可走較低 risk review，但仍須有 machine admission receipt。

## 12. Why Custom Code Is Still Needed

Agent-Reach 提供的是個人工具層的 channel／doctor pattern；Knowledge OS 仍需自研最小 domain mapping：

- enterprise scope／actor／permission。
- source Terms／license／retention／deletion。
- CapabilityHealthReceipt → RawEvidence admission。
- config inheritance and overrides by company／department／team／user／client。
- audit／policy version／expiry。
- single-writer and canonical boundary。

自研只限上述產品語意，不重刻 provider probe framework 中已有的 deterministic pattern。

## 13. Acceptance

- External Capability Admission 不再是模糊「裝好就能用」。
- provider health 有 timestamp、TTL、probe evidence 與 error class。
- `WARN`／`UNKNOWN` 不會變 `OK`。
- credential 不出現在 log／receipt／UI。
- install 先有 dry-run mutation manifest。
- provider 失效可降級且不破壞 Evidence identity。
- external output 只能先進 Raw Evidence boundary。
- Permission-before-Retrieval、Retention、Deletion、Single Writer 不被繞過。
- 不建立 Agent Runtime／Registry／FSM／Ledger。
- 不改 Employee Personal Memory 現有 priority。

## 14. Required final disposition

```text
ADOPT_CONTRACT_PATTERN
THIN_ADAPTER_REQUIRED
REFERENCE_ONLY
DEFER
REJECT
```

本卡完成 design／fixture 後，若為 `ADOPT_CONTRACT_PATTERN` 或 `THIN_ADAPTER_REQUIRED`，仍須另開 implementation card；本卡不得直接部署 connector。

## 15. Stop conditions

- 需要先安裝或登入外部工具才能定義 contract。
- provider output 無法被限制到 Raw Evidence boundary。
- credential／Cookie 只能透過非明示方式取得。
- source Terms／license 無法判定且仍想預設啟用。
- proposal 需要新 Runtime／Agent Registry／Knowledge DB。
- 同一 blocker 三次無進展。

## 16. Final routing

```text
Current core frontier: unchanged
EMEM-00 review target: unchanged
Card registration: complete
Execution / install / deployment: not authorized
```