---
id: SSP324-MINIMAL-EVIDENCE-PACKAGE-20260917
status: READY
jira: SSP-324
parent_jira: SSP-286
related_jira: SSP-294, SSP-295
type: bounded-product-amendment
priority: MVP
---

# SSP-324｜EMEM-10 Personal → Company 最小證據封包與上傳邊界

## 定位

本卡是 SSP-294 已驗收 Promotion Governance 的 downstream payload boundary，不重新設計 Promotion。

必須直接重用 SSP-294 已 `ACCEPTED_GO` 的：

- Slice A：promotion widening gate（6 required + 3 forbidden）
- Slice B：actor × material class policy matrix
- Slice C：source ACL ceiling

也直接沿用既有 Verification、Review、Acceptance、Canonical Single Writer。

```text
Promotion Candidate / NEEDS_ORG_FOLLOWUP
        ↓
Minimal Evidence Package
        ↓
Existing SSP-294 Governance
        ↓
Verification / Review / Acceptance
        ↓
Canonical Single Writer
```

`Evidence Package != Company Knowledge`
`NEEDS_ORG_FOLLOWUP != Company Knowledge`

## Minimal Evidence Package contract

Package 只包含支撐本次 proposal/follow-up 的最小必要資料，至少應能表達：

- submission / candidate identity
- content / statement / structured proposal
- minimal supporting evidence excerpts 或 bounded artifact subset
- `evidence_refs`
- `source_anchor` / source identity / version
- provenance chain
- occurred / observed / submitted timestamp
- content/integrity hash 或等價 integrity metadata
- source ACL snapshot
- ownership mode
- visibility scope
- sensitivity
- redaction record / redaction reason / policy ref
- organizational value reasons
- uncertainty / missing evidence / unresolved question
- employee correction / annotation（若有）
- `suggested_expert`（optional；`null` 合法）

不得因「verification 可能需要」就擴張成 whole Personal Store dump。

## Reverse-access hard boundary

公司 Organizational Layer：

- 不得 browse Personal Store
- 不得 search Personal Store
- 不得 pull Personal Store
- 不得 remote-query / remote-mount Personal Store
- 不得因公司端 verification 不足就繞過本卡去取更多本機資料

若後續真的有新增 evidence，只能由 Personal 端形成一個新的明確 submission/revision package；不能讓公司直接進員工本機查。

## Company-side evidence handling

Evidence Package 只可作：

- Promotion review support
- Verification support
- Audit / dispute / provenance 備查

不得自動作：

- 一般公司搜尋 corpus
- RAG / LLM 正式 retrieval source
- Company Canonical Knowledge
- Personal Store replica

正式 Retrieval 仍只能透過既有 accepted Shared Canonical Knowledge + Permission-before-Retrieval。

## Immutable submission / revision semantics

- 每次 submission 保留 identity、hash、timestamp、provenance。
- 上傳後不可原地偷偷改 package。
- correction / new evidence / redaction change / policy change 以新 revision、correction 或 supersession package 表達。
- previous package 必須可追溯。
- 不建立第二套 revision lifecycle；重用既有 Correction / Supersession 語意。

## Dedup / resend rule

```text
UNCHANGED
→ no resend

NEW_EVIDENCE but no material effect
→ local recurrence/support history only

NEW_EVIDENCE with material effect
→ evidence update / revision package

MATERIALLY_CHANGED
→ revision / supersession proposal

CONTRADICTED
→ correction / conflict proposal
```

Material effect 至少包含：

- evidence-strength tier 改變
- applicability 改變
- risk 改變
- conflict 判定改變
- redaction / sensitivity requirement 改變
- conclusion 改變

不得每週因同一知識再次發生就往公司重送 duplicate package。

## NEEDS_ORG_FOLLOWUP

Personal Harness 已經把本人可回答的部分問完，但：

- 本人確實不知道答案，或
- 缺公司其他來源／其他角色 evidence，且
- organizational value 仍高

即可提交 `NEEDS_ORG_FOLLOWUP`。

規則：

- 它是 follow-up signal，不是 Knowledge。
- 不要求員工先知道哪位同事是 expert。
- `suggested_expert=null` 合法。
- expert routing / taxonomy / cross-person conflict resolution 留在 Organizational Layer。

## Ownership / consent boundary

### COMPANY_MANAGED_PERSONAL / SHARED_WORK_CONTEXT

- 員工可 correction、annotation、補 evidence、標 sensitive、要求 redaction。
- 單純「我不想傳」不得取代既有 company policy / source ACL / promotion gate。
- 這不代表強制 canonical；仍需既有 governance。

### EMPLOYEE_PRIVATE

- 無本人 consent 不得進 Promotion upload 或 Minimal Evidence Package。
- 缺 consent 必須 fail closed。

正式 invariant：

`physical_local_storage != employee_private_ownership`

## Acceptance

1. 合法 Proposal 可只帶 bounded evidence package 進既有 SSP-294 gate，不要求同步 Personal Store。
2. 缺 source anchor/provenance/ACL/integrity/redaction metadata 的 required case fail closed。
3. Reverse browse/search/pull/remote-query fixture 一律拒絕。
4. Supporting Evidence Package 無法被正式 company retrieval fixture 命中。
5. `NEEDS_ORG_FOLLOWUP + suggested_expert=null` 合法，但不能產生 canonical identity。
6. 已提交 package 的後續變化只能追加 revision/supersession；舊 package 可驗 hash/provenance。
7. `UNCHANGED` 不重送；material effect 才產生 update。
8. Company-managed work material 的 simple veto 不可繞 policy；EMPLOYEE_PRIVATE 無 consent fail closed。

## Hard stops

- 不改 SSP-294 A/B/C authority
- 不新建 promotion workflow
- 不新建 central Personal DB
- 不新建 reverse local connector/search API
- 不把 whole Personal Store 當 Evidence Package
- 不把 Evidence Package／Promotion Candidate／NEEDS_ORG_FOLLOWUP 當 Canonical Knowledge

## Pilot binding

SSP-295 真人 pilot 必須證明：公司只收到明確 submission package，且不存在 reverse-access path。
