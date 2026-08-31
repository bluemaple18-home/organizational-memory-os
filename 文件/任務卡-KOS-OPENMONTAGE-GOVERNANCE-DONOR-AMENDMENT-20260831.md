# 任務卡｜KOS-GOV-DONOR-01｜OpenMontage Governance Contract Amendment

日期：2026-08-31

狀態：

```text
OWNER_ADMITTED_TO_BACKLOG
REFERENCE_ONLY_DONOR_AMENDMENT
MERGE_INTO_EXISTING_CAPABILITIES
NO_STANDALONE_IMPLEMENTATION
NO_VIDEO_SUBSYSTEM
NO_SOURCE_COPY_WITHOUT_LICENSE_REVIEW
NO_CURRENT_FRONTIER_CHANGE
```

## 0. Card identity

```yaml
id: KOS-GOV-DONOR-01
capabilities:
  - Review / Approval
  - Minimum Telemetry / Cost
  - External Capability Admission
  - Long-running Stage / Artifact Governance
priority: P0-min / P1-A donor amendment
responsibility:
  - DOMAIN_CORE
  - ENTERPRISE_GOVERNANCE
  - CROSS_CUTTING_PLATFORM_CONTROL
  - DETERMINISTIC_FIRST
source_repo: calesthio/OpenMontage
source_commit: cd9f3c1f03368be87b140af494914b8ee4e3c7a4
source_license: AGPL-3.0
```

## 1. Backlog placement

本卡不是新產品主線，也不是影片功能卡。它只把 OpenMontage 已成熟的 stage、approval、tool、cost 與 artifact contract pattern 合併到 Knowledge OS 既有缺口：

```text
Review / Approval
Minimum Telemetry / Cost
External Capability Admission
Evaluation → Repair → Re-eval
```

現有施工順序保持：

```text
1. Raw Evidence Contract
2. Document Adapter Mapping
3. Jira Adapter Mapping
4. Permission / Retention / Deletion Contract
5. Canonical Direct-Write Audit
6. 最新繁體中文互動 Architecture Canvas
```

本卡是上述能力進入 exact contract 時的 donor reference；不建立獨立 OpenMontage implementation frontier。Employee Personal Memory 的 `EMEM-00` review target 也不變。

## 2. Root question

Knowledge OS 的長流程與外部能力，能否借用 OpenMontage 的 declarative contract pattern，把以下語意從 prompt 習慣提升成可驗證契約：

```text
stage order
required inputs
produced artifacts
allowed tools
checkpoint
human approval
review focus
success criteria
cost reservation
execution receipt
rollback / refund
```

同時維持：

```text
Agent / Model
= replaceable executor
!= control-plane authority

Execution completed
!= Verification passed
!= Acceptance granted
```

## 3. Product / Domain Responsibility

Knowledge OS 必須擁有：

- Knowledge mutation 的 stage／artifact prerequisites。
- Verification 與 human approval requirements。
- 外部工具的 allowed capability／side effects／cost envelope。
- 長流程 checkpoint、resume、failure 與 rollback evidence。
- estimate、reserve、actual reconciliation 與 refund。
- artifact provenance、license 與 acceptance trace。

OpenMontage、任何 Agent 或 provider 只能提供 donor implementation／execution evidence，不能取得 Knowledge Authority、Permission Authority 或 Canonical Writer 權限。

## 4. Fixed prior art

固定來源：

```text
calesthio/OpenMontage@cd9f3c1f03368be87b140af494914b8ee4e3c7a4
license: AGPL-3.0
```

Relevant donor files：

- `pipeline_defs/*.yaml`
- `schemas/pipelines/pipeline_manifest.schema.json`
- `tests/contracts/test_pipeline_catalog.py`
- `tools/base_tool.py`
- `tools/cost_tracker.py`
- `lib/checkpoint.py`
- `lib/pipeline_loader.py`
- `lib/events.py`
- `backlot/**`

Observed donor semantics：

### Pipeline manifest

```text
stage
├── required_artifacts_in
├── produces
├── required_tools / optional_tools
├── checkpoint_required
├── human_approval_default
├── review_focus
└── success_criteria
```

### Tool contract

```text
identity / version
capability / provider
runtime / stability / determinism
input / output / artifact schema
dependencies / resources
retry / resume / idempotency
side effects / fallback
user-visible verification
cost / duration / artifacts / error
```

### Cost lifecycle

```text
estimate
→ reserve
→ execute
→ reconcile
```

未執行時：

```text
reserve
→ refund
```

### Contract testing

Shipped manifest 若 schema 失敗，不應靜默 fallback 到另一個 stage order 或讓 approval gate 消失；catalog contract test 應直接 fail。

## 5. Reuse Candidate

### Absorb as semantic pattern

1. Declarative stage manifest。
2. `required_artifacts_in` 與 `produces`。
3. required／optional tools 分離。
4. checkpoint policy。
5. `human_approval_default` 與 risk override。
6. `review_focus` 與 machine-testable `success_criteria` 分離。
7. shipped manifest 全量 contract test。
8. malformed manifest fail-closed，不可靜默換 stage／gate。
9. tool identity、capability、runtime、dependencies、resource、retry、resume、idempotency、side-effects、fallback contract。
10. standard execution result：success、data、artifacts、error、cost、duration、model／seed where applicable。
11. estimate／reserve／reconcile／refund。
12. event-derived operator projection／replay，不要求 Agent 額外寫報告。
13. artifact provenance、source URL、license、provider decision。
14. max revisions／send-backs／wall-time boundary。

### Do not absorb

- OpenMontage video production product、pipeline catalog 或 creative role topology。
- Remotion、FFmpeg、TTS、image／video provider subsystem。
- 「LLM coding assistant 本身就是 control plane」的 authority model。
- OpenMontage checkpoint file 直接成為 Knowledge OS canonical lifecycle。
- Backlot UI／replay 成為 truth store。
- 固定影片成本門檻、stage 名稱或 renderer lock。
- 任何 AGPL source code 未經 license review 直接複製進商業 SaaS。
- 新 workflow engine、Agent Registry、provider registry 或独立 runtime。

## 6. Proposed Knowledge OS crosswalk

| OpenMontage donor concept | Knowledge OS target | Truth role |
|---|---|---|
| pipeline manifest | Mutation／Evaluation Stage Policy | managed policy, not runtime truth |
| stage prerequisites | Verification Requirement／Acceptance prerequisite | domain rule |
| produced artifact | Evidence／Candidate／Receipt references | typed resource |
| checkpoint | bounded execution progress evidence | operational record |
| human approval | Acceptance Decision／scope widening approval | canonical governance decision |
| review focus | reviewer guidance | policy input |
| success criteria | deterministic／human verification requirement | testable contract |
| ToolContract | External Capability Definition／Provider Candidate | managed configuration |
| ToolResult | Execution／Capability Receipt | evidence, not knowledge |
| CostTracker | Cost Estimate／Reservation／Reconciliation | operational financial record |
| Backlot events | Control-plane projection／replay | rebuildable projection |

## 7. Minimum schemas to amend

### StagePolicy

```yaml
stage_policy_id:
capability_or_flow:
version:
required_inputs:
produced_outputs:
allowed_capabilities:
forbidden_side_effects:
checkpoint_required:
verification_requirements:
human_approval:
review_focus:
success_criteria:
max_revisions:
max_send_backs:
max_wall_time:
policy_source:
```

### CostEstimate / Reservation / Reconciliation

```yaml
cost_entry_id:
operation_identity:
capability_id:
provider_id:
currency:
estimated_amount:
reserved_amount:
actual_amount:
status: ESTIMATED | RESERVED | COMPLETED | FAILED | REFUNDED
approval_required:
approval_ref:
created_at:
reconciled_at:
receipt_ref:
```

### ExecutionArtifactReceipt

```yaml
execution_id:
stage_policy_id:
input_refs:
output_refs:
provider_version:
policy_version:
started_at:
finished_at:
status:
verification_state:
acceptance_state:
cost_entry_refs:
side_effects:
residual_resources:
error_class:
```

## 8. Truth and authority boundaries

```text
StagePolicy
= managed policy

Checkpoint / Event
= operational evidence
!= acceptance

ToolResult
= execution evidence
!= verified fact
!= canonical knowledge

Approval Decision
= governance fact
but only within its declared scope and policy version

Backlot / dashboard / replay
= projection
!= canonical truth
```

任何 stage 完成，都不得直接呼叫 Canonical Writer；仍須通過 Knowledge OS 的 Proposal、Verification、Acceptance 與 Single Writer boundary。

## 9. Deterministic First

應 deterministic：

- manifest／schema validation。
- stage order 與 prerequisites。
- allowed capability／side-effect check。
- required artifact completeness。
- approval-required evaluation when policy is explicit。
- revision／send-back／wall-time limits。
- cost arithmetic、reservation、reconciliation、refund。
- event schema、sequence、projection rebuild。

模型可協助：

- review focus 內的語意評估。
- ambiguous artifact quality evaluation。
- failure classification candidate。

模型不得：

- 自行改 stage order 或 approval requirement。
- 將自己的 output 當 verification／acceptance。
- 自動提高預算或放寬 side effects。

## 10. Required fixtures

1. shipped stage manifest 全部 schema-valid。
2. 新 manifest 含未知欄位，must fail visible。
3. manifest parse fail 時不得 fallback 成另一條可執行 pipeline。
4. `human_approval_default=true` 無 approval，不得前進。
5. required input 缺失，不得執行 stage。
6. required tool unavailable，產生 bounded admission failure。
7. optional tool unavailable，可按 policy 降級且留下 receipt。
8. success criteria 未通過，即使 executor exit 0 仍不得 accepted。
9. estimate 超過單次門檻，reserve 前必須取得 approval。
10. reserve 後未執行，必須 refund。
11. actual cost 與 estimate 不同，reconcile 保留兩者。
12. execution failed 仍保留 actual cost、side effects 與 residual resources。
13. event projection 刪除後可由 canonical operational records重建。
14. artifact 缺 provenance／license，不得通過 admission／acceptance。
15. Agent 嘗試改 policy／skip gate，應被 deterministic validator 拒絕。

## 11. Human Review Requirement

必須人工 review：

- scope widening／promotion。
- canonical mutation。
- 高風險或外部 write capability。
- 新付費 provider／預算提升。
- source license／Terms 不明。
- irreversible side effects。
- failed verification 後的 override。

低風險 mechanical stage 可由 machine verification 自動完成，但 acceptance policy 必須明示，不得由 Agent 自行猜測。

## 12. License boundary

OpenMontage 為 AGPL-3.0。本卡預設：

```text
architecture / contract idea
= reference and independent reimplementation candidate

source code copy / modified source integration / network-served derivative
= license review required
```

未完成 license／distribution／network-service obligation review 前：

- 不複製 source code。
- 不 vendoring module。
- 不移植 tests verbatim beyond minimal independently authored fixture semantics。
- 不聲稱 MIT-compatible absorption。

## 13. Why Custom Code Is Still Needed

Knowledge OS 需要自研最小 domain mapping：

- Evidence／Candidate／Verification／Acceptance／Canonical Writer semantics。
- Permission／scope／retention／deletion。
- company／team／user／client config precedence。
- provider-neutral capability admission。
- cost owner、budget scope、approval actor 與 audit。

不需要重刻 OpenMontage 的影片 pipeline、tool providers、Backlot 或 Agent-led orchestration。

## 14. Acceptance

- Review／Approval、Cost、Capability Admission 得到 exact contract donor，不新增影片 subsystem。
- malformed policy／manifest fail-closed。
- `human_approval_default` 不會因 parse failure 消失。
- execution、verification、acceptance 保持三分。
- estimate、reserve、reconcile、refund 可追溯。
- dashboard／event replay 明確是 projection。
- Agent 不成為 control-plane authority。
- AGPL source copy boundary被鎖定。
- 不改目前六項 core frontier 與 `EMEM-00` priority。

## 15. Final disposition

本卡最終只可：

```text
MERGE_CONTRACT_PATTERNS_INTO_EXISTING_CARDS
REFERENCE_ONLY
LICENSE_REVIEW_REQUIRED_BEFORE_CODE_REUSE
DEFER
REJECT
```

不得輸出 `BUILD_OPENMONTAGE_SUBSYSTEM`。

## 16. Stop conditions

- 提案開始擴張成影片功能或 creative pipeline。
- 需要 Agent 取得 stage／approval／writer authority。
- 只能靠複製 AGPL code 才能成立，且 license review 未完成。
- checkpoint／dashboard 被當 canonical truth。
- 建議新增通用 workflow engine／Agent Registry／provider lifecycle DB。
- 同一 blocker 三次無進展。

## 17. Final routing

```text
Current core frontier: unchanged
EMEM-00 review target: unchanged
Card registration: complete
Implementation / source copy / deployment: not authorized
```