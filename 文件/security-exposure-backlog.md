# Security / Exposure Backlog

更新：2026-09-08
狀態：`ACTIVE / CROSS_CUTTING_PLATFORM_CONTROL`
責任分類：`ENTERPRISE_GOVERNANCE / CROSS_CUTTING_PLATFORM_CONTROL`

用途：補充 `文件/待辦重整.md` 的 repo / CI / publication exposure 治理。此檔不新增第九顆 Knowledge Domain Core；只記錄平台級安全治理待辦。Public repo 不保存 exploit payload、production secret、private endpoint 或可直接濫用的攻擊步驟。

## P0 — Repository governance

### SEC-P0-01 — Protect `main`

**狀態：MISSING**

最低要求：

- require PR。
- required CI / review gate。
- 禁止 force push / branch deletion。
- automation / Agent 寫入不得繞過 accepted mutation boundary。

理由：Repository governance 與 Canonical Single Writer 同型；外部 contributor、GitHub App、PAT 或 automation compromise 時，需要第二道 deterministic mutation boundary。

驗收：branch rule/ruleset 生效；正常研究/backlog merge flow 不回歸。

## P1 — Public knowledge vs defensive intelligence boundary

### SEC-P1-01 — `.work` publication classification

**狀態：MISSING**

目標：盤點 public `.work/`、handoff、review、evidence；每項標示：

- `PUBLIC_REPRO_EVIDENCE`
- `PUBLIC_ARCHITECTURE_KNOWLEDGE`
- `INTERNAL_DEFENSIVE_INTELLIGENCE`
- `PRIVATE_OPERATIONAL_RECORD`

規則：

- Evidence ≠ automatically public evidence。
- 可重建 projection / review artifacts 不因存在於 repo 就取得 publication authority。
- 會揭露 production topology、內部 identity、permission assumption、failure blind spot、secret/path/endpoint 的材料不得進 public canonical docs。
- Public architecture 可以保留 product principles / contracts；production-specific defensive intelligence 另放 private workspace。

### SEC-P1-02 — Security redaction gate for research/evidence imports

**狀態：MISSING / DETERMINISTIC_FIRST**

目標：任何外部研究包、Evidence、Agent output、execution receipt 在進 public repo 前先跑 deterministic redaction policy。

至少檢查：credential/token、cookie、private key、internal hostname/IP、absolute user path、private document URL、未去敏 request/response payload。

失敗時 `BLOCKED`，不得讓模型自行判定可公開。

## P1 — Historical secret assurance

### SEC-P1-03 — Full Git-object secret scan

**狀態：NOT_RUN**

目標：對完整 Git history 執行 gitleaks/trufflehog 類 full-object scan；current-tree search 不可替代 historical assurance。

輸出只保存：repo、commit/path locator、secret type、rotation status；不保存 secret value。

## Current bounded checks

- 本 repo 目前主要為 architecture / research / backlog authority，runtime attack surface 相對低。
- `main` branch protection：`MISSING`。
- public `.work/` 存在，需做 publication classification。
- historical secret absence 目前只能標 `NOT_FOUND_IN_BOUNDED_CHECK`，不得宣稱 `VERIFIED_ABSENT`。

## 與 Minimal Core 的關係

這些項目不改變八個 Minimal Core。它們屬 Managed Policy Floor / Evidence Governance / Acceptance 的 repo-level operational extension：

```text
Git / Agent / Research Evidence
→ deterministic redaction
→ publication classification
→ review / acceptance
→ public repo mutation boundary
```

與產品內 `Permission-before-Retrieval` 相同原則：未授權/未接受的 material 不得先暴露再補過濾。
