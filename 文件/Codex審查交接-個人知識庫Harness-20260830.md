# Codex 審查交接｜個人知識庫 Harness｜2026-08-30

狀態：

```text
READ_ONLY_REVIEW
NO_IMPLEMENTATION_AUTHORIZATION
NO_GIT_MUTATION_AUTHORIZATION
NO_RUNTIME_INSTALL_AUTHORIZATION
NO_SCHEMA_ACCEPTANCE_AUTHORITY
```

Repo：

```text
bluemaple18-home/organizational-memory-os
```

Target HEAD：

```text
<請先重新讀取 main 並回報 actual HEAD>
```

Cross-repo evidence：

```text
bluemaple18-home/aicore
reviewed HEAD in proposal:
87f6a16cf22642513730ea56530a8b5b1ce4ee99
```

---

## 1. Review targets

主要審查：

```text
文件/個人知識庫Harness提案查核與整合裁決-20260830.md
規格/v0.1/personal-harness-integration.yaml
文件/DeepSeek-Harness整合裁決-current-truth修正-20260830.md
文件/待辦補充-個人知識庫Harness-20260830.md
```

補讀：

```text
文件/SaaS能力等級.md
文件/個人證據與工作紀錄.md
文件/最小核心重基準.md
文件/DeepSeek-Harness整合裁決與施工切片.md
文件/權限政策與設定治理.md
文件/STD-00-Schema-Vocabulary-Freeze-v0.1-提案.md
```

AI Core current-truth source：

```text
docs/ai-core-canonical-architecture.md
config/work_lifecycle_contract.json
.codex/hooks.json
.founder-vault/README.md
.founder-vault/memory-summary.md
docs/task_cards/CARD-AICORE-PERSONAL-MODE-PROVIDER-EXTENSION-REMOVAL-CC-LEVEL-A-BOUNDARY-STAGE-B6-20260828.md
```

---

## 2. Review purpose

判斷這份整合是否：

1. 正確分開 OMOS Knowledge authority、AI Core Work authority與runtime-native state。
2. 沒有重新建立已被AI Core移除的provider extension platform。
3. 沒有把 proposal偽裝成現有規格。
4. 能讓後續開 bounded design card，而不先安裝／執行 runtime。
5. 能誠實處理Codex、Claude Code、Hermes、DSH不同native event。
6. 沒有讓Founder Vault取得企業Knowledge authority。
7. 沒有把四個Loop變成四套子系統。

不要評估UI美觀、商業定價或完整production架構。

---

## 3. Hard invariants

不得推翻：

```text
Evidence != Knowledge
WorkRecord != Knowledge
Personal Memory != Company Canonical Knowledge
Candidate != Canonical
Proposal != Canonical Write
Permission-before-Retrieval
EXECUTED != VERIFIED != ACCEPTED
Task Card != ExecutionRequest
ExecutionReceipt != VerificationReceipt
Native TaskCompleted != AI Core CLOSED
ObjectLink != Permission Expansion
Founder Vault != Enterprise Canonical Store
Projection must be rebuildable
```

---

## 4. Required checks

### A. Current truth

確認：

- Organizational Memory OS正式L1–L4是否仍為基礎／自動化／智慧化／自治化。
- Founder Vault folder taxonomy是否確實存在於AI Core。
- Founder Vault是否被正確限制為personal curated surface。
- AI Core Work lifecycle是否仍是task／status authority。
- AI Core provider extension是否已正式移除。
- `.codex/hooks.json` formal hook是否仍預設disabled。

### B. Proposal disposition

逐項確認九項提案的：

```text
ACCEPT
AMEND
REJECT
DEFER
TRIGGER
```

是否有證據，且沒有被過度裁決。

尤其檢查：

- `協作化` 是否應作獨立axis。
- `同事預設L2` 是否保留source safety gate。
- `memctl` 是否應維持read-only／defer。
- M0–M4是否只作delivery milestone。

### C. Task card

確認：

- 沒有建立第二套task truth。
- frontmatter validation profile只作validator。
- authorization缺失fail closed。
- ExecutionRequest與Task Card責任分開。
- ExecutionRequest沒有acceptance／canonical write authority。

### D. Runtime events

確認：

- native event name被保存。
- semantic mapping不偽裝成native。
- Codex `turn/completed`不等於accepted。
- Claude `TaskCompleted`不等於AI Core closed。
- Hermes hook不被當唯一truth／security boundary。
- redelivery／event gap／payload mismatch有negative fixture。

### E. Runtime adapter

確認：

- 只有thin adapter operations。
- 無registry／DB／universal runtime。
- 無silent fallback。
- adapter不負責review／acceptance／merge／promotion。

### F. Four loops

確認：

```text
Capture
Closeout
Consolidation
Promotion
```

只是existing domain operation grouping，不會長成：

- four agents。
- four queues。
- four databases。
- four lifecycle authorities。

### G. Hermes

確認：

- exact pin可重現。
- one-shot command只是候選，不宣稱已驗證。
- Stage A profile足夠關閉Gateway／Kanban／Cron／Memory write／Skill self-modification／shell hooks。
- hook reliability限制有被納入。
- Hermes memory／kanban／session不取得authority。
- Hermes排在Codex baseline之後。

### H. DSH amendment

確認：

- 只supersede舊integration seam。
- 不推翻原本blocked/no-install姿態。
- 沒有復活已刪provider extension。
- request／receipt boundary可以同時適用DSH與Hermes。

### I. Machine-readable companion

檢查：

```text
規格/v0.1/personal-harness-integration.yaml
```

- YAML可解析。
- proposal disposition與Markdown一致。
- exact pins一致。
- enums沒有把execution／verification／acceptance混軸。
- forbidden actions與Hard Stops一致。

---

## 5. Output format

請只回：

```text
VERDICT: ACCEPT | AMEND | BLOCK

CURRENT-TRUTH-CONFIRMED
- ...

LOCKED-AS-IS
- ...

FINDINGS
- ID:
  Severity: BLOCKER | HIGH | MEDIUM | LOW
  File:
  Section / field:
  Problem:
  Evidence:
  Authority impact:
  Proposed amendment:
  Fixture/test required:

OPEN DECISIONS
- ...

READY NEXT
- PH-01 task-card frontmatter profile: YES | NO
- PH-02 ExecutionRequest/Receipt vocabulary: YES | NO
- PH-05 Codex Stage A mapping: YES | NO
- Hermes Stage A: YES | NO
- Reason:
```

每個Finding必須指向 exact file與section／field。

不要只寫：

```text
可以再完整一點
建議更安全
考慮更多runtime
```

---

## 6. `BLOCK` threshold

只有存在下列之一才可 `BLOCK`：

- 重新建立第二套Work／Knowledge authority。
- identity collision。
- runtime event可繞過review／acceptance。
- permission leak。
- Founder Vault可直升Company Canonical。
- WorkRecord可跨scope洩漏。
- silent runtime fallback。
- Hermes／DSH native state成為產品truth。
- machine-readable decision與Markdown互相矛盾。
- DSH amendment會復活已刪provider seam。

否則使用bounded `AMEND`。

---

## 7. Forbidden actions

本輪禁止：

- 修改任何repo檔案。
- 建立branch／commit／PR。
- 修改AI Core。
- 寫production JSON Schema。
- 安裝Codex／Claude Code／Hermes／DSH。
- 執行runtime probe。
- 建立`memctl`。
- 啟用global hook。
- 建立provider registry。
- 建立four-loop agents。
- 將proposal標為Canonical。
- 因找到其他framework重開Knowledge OS架構。
- 將Hermes／DSH排成current frontier。

---

## 8. Review disposition

`ACCEPT`：

```text
只代表review無阻塞finding
```

仍需要使用者／指定authority明確接受，才能：

```text
PH-01 = READY_FOR_DESIGN
PH-02 = READY_FOR_DESIGN
```

`ACCEPT` 也不代表：

```text
Hermes可安裝
runtime可執行
memctl可開發
hook可啟用
```

`AMEND`：

- 只提bounded amendment。
- 不重寫整套Personal Knowledge／AI Core。

`BLOCK`：

- 必須附可重現的authority bypass或fixture failure。
