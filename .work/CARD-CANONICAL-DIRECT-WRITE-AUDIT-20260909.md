---
id: CANONICAL-DIRECT-WRITE-AUDIT-20260909
status: BLOCKED_AWAITING_OWNER_SCOPE_DECISION
type: audit
lane: A（repo 施工順序 #5 / SSP-294 前置）
tier: T3
---

# Canonical Direct-Write Audit（repo #5）

👉 [假設與目標確認]
- 目標：系統性盤點目前 repo 的所有規格 / 契約 / validator 中，是否有任何 write / mutation /
  promotion path 繞過 **Proposal → Acceptance → Single Writer** 這條 canonical 邊界。產出
  findings + 需補的 guard。
- 邊界：這是一次**稽核**，不是 build。輸出是 findings 清單與（若有）guard 需求，不是新契約。

## 為什麼 T3（停，回 Owner 做 level / scope 決策）

依 `~/.claude/CLAUDE.md` T3 觸發：「動到 authority 邊界、六條 Truth Boundary、或要新增
subsystem」。本卡直接稽核 **Canonical Single Writer** Truth Boundary（`LOCKED`），且其 findings
可能要求新增 guard / 拒絕現有路徑 —— 屬 Owner 的 level / scope 決策，**CC 不自行開工，也不自行
判定哪條路徑該被擋**。

需 Owner 先決定的 scope 問題：

1. **稽核範圍**：只掃 `規格/v0.1/*.yaml` + `*.schema.json` 的宣告面，還是也要掃
   `.work/` 卡片流與 `scripts/` validator 的隱含 write 假設？
2. **canonical writer 的具體邊界**：目前 repo 沒有實體 writer 實作，只有契約層宣稱
   （`ai-work-record-boundary` 的 `promotion_path` + `skip_any_step forbidden`、
   `personal_memory_resource_contracts` 的 `canonical_single_writer`、e2e 的
   `E2E_WORKRECORD_PROMOTED_WITHOUT_ACCEPTANCE`）。稽核對象是「契約有沒有互相放寬」還是
   「未來 runtime 的 write path」？
3. **findings 的處置權**：稽核發現某契約可繞過時，是 CC 開 repair 卡，還是回 Owner 逐條裁決？
4. **與 SSP-305 F-02 的關係**：SSP-305 repair 01 已補「e2e 匯流點不得放寬 SSP-298
   promotion_path」。本稽核是否即以「每個引用 promotion / acceptance / writer 的契約都必須
   pointer-bind 回 SSP-298 且不得弱化」為單一判準？

## Traces to

- `文件/待辦重整.md` 第二節「Canonical Direct-Write Audit | MISSING | DOMAIN_CORE /
  ENTERPRISE_GOVERNANCE | P0 | FIRST FRONTIER；盤所有 writer path 是否繞過
  Proposal/Acceptance/Single Writer」。
- `文件/最小核心重基準.md` §施工順序 #5。
- 六條 Truth Boundary（Canonical Single Writer）。
- 既有契約面：`規格/v0.1/ai-work-record-boundary.yaml` `promotion_path`、
  `規格/v0.1/personal-harness-integration.yaml` `personal_memory_resource_contracts` /
  `correction_flow` / `recall_context_pack`、`規格/v0.1/ai-work-record-e2e-acceptance.yaml`
  `memory_promotion_gate`。
- 下游：`SSP-294`（EMEM-05 Promotion）。

## Dependencies / Blockers

- Dependencies：無技術前置。
- Blockers：**Owner 尚未定 scope（上述 4 項）**。在定 scope 前本卡不開工。

## 解除條件

Owner 回覆稽核 scope（範圍 / 判準 / findings 處置權）後 → 本卡轉 `IN_PROGRESS`，CC 產出
`.work/evidence/CANONICAL-DIRECT-WRITE-AUDIT-<date>.md` findings 清單，依 Owner 指定的處置權
開 repair 卡或回 Owner 裁決。

## Likely output（解除後）

- `.work/evidence/CANONICAL-DIRECT-WRITE-AUDIT-<date>.md`（findings 清單 + guard 需求）
- 視 findings：0～N 張 repair 卡（每張針對一條可繞過的契約路徑）
