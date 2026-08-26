# 待辦補充｜DeepSeek Harness｜2026-08-26

狀態：`DONOR_PINNED / IMPLEMENTATION_DEFERRED / NOT_CURRENT_FRONTIER`

Authority：`文件/DeepSeek-Harness整合裁決與施工切片.md`

本補充不改變 `文件/待辦重整.md` 的 current execution order，也不把 DSH 升成第九顆 Minimal Core。

## Backlog placement

| ID | 能力 | 狀態 | 責任分類 | Priority / Delivery | 裁決 |
|---|---|---|---|---|---|
| `OMOS-DSH-00` | RawEvidence `AGENT_RUNTIME` fixture | MERGE | DOMAIN_CORE / ENTERPRISE_GOVERNANCE | P0 current contract | 合併進 Raw Evidence Contract，不建立 DSH dependency |
| `OMOS-DSH-01` | DSH ExecutionEvidence Source Adapter | BLOCKED | RUNTIME_OWNED / EXECUTOR_ONLY / DOMAIN_ADAPTER | P1-A / NEXT | 等 RawEvidence Contract 與 AI Core provider adapter |
| `OMOS-DSH-02` | DSH Capability Admission fixture | MERGE | ENTERPRISE_GOVERNANCE | P1-A / NEXT | 合併 External Capability Admission |
| `OMOS-DSH-03` | Trajectory → AnswerTrace | BLOCKED | PROJECTION_ONLY | P1-B / NEXT | 等 AnswerTrace contract；不得成 truth |
| `OMOS-DSH-04` | Dynamic Workflow Evaluation Executor | DEFER | MODEL_ASSISTED / RUNTIME_OWNED | Trigger / NORTH STAR | 只限 high-risk/conflict/low-confidence escalation |
| `OMOS-DSH-05` | Agent Teams / Creator | REFERENCE_ONLY | DEFER / TRIGGER | Trigger / NORTH STAR | 不阻塞 MVP，不預設啟用 |

## Current priority remains

```text
1. Raw Evidence Contract
2. Document Adapter Mapping
3. Jira Adapter Mapping
4. Permission / Retention / Deletion Contract
5. Canonical Direct-Write Audit
6. 最新繁體中文互動 Architecture Canvas
```

本輪只完成 donor pin、authority diff、seam reservation與 AI Core blocked Stage A card；沒有 runtime implementation authorization。
