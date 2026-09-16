# repo #5 Canonical Direct-Write Audit — findings

日期：2026-09-16　branch：`cc/canonical-direct-write-audit`
Owner 簽定範圍：`FP-1: B / FP-2: A / FP-3: A / FP-4: B`

- **FP-1-B**：掃契約宣告面 **＋** `scripts/` validator 是否真的強制。
- **FP-2-A**：單一判準＝每個引用 promotion／acceptance／writer 的契約必須
  pointer-bind 回 `ai-work-record-boundary.promotion_path` 且不得弱化。
- **FP-3-A**：CC 只產 findings，**不自行開 repair 卡**，逐條回 Owner 裁決。
- **FP-4-B**：留下常設 validator。

## 稽核對象

`grep` 確認 **11 份契約**引用 promotion／acceptance／canonical writer。
上游權威 `ai-work-record-boundary.yaml#promotion_path`：

```
ordered_steps: TASK_CARD_OR_WORK_RECORD → RAW_EVIDENCE_ENVELOPE →
               PERSONAL_MEMORY_CANDIDATE → VERIFICATION →
               PERSONAL_ACCEPTANCE → PERSONAL_MEMORY_RECORD
rules:         evidence_step_required / task_card_direct_to_record: forbidden /
               candidate_before_verification_and_acceptance /
               skip_any_step: forbidden / steps_out_of_order: forbidden
receipts_required: VERIFICATION → verification_receipt_ref
                   PERSONAL_ACCEPTANCE → personal_acceptance_ref
```

## 結論摘要

**沒有發現任何現行的 canonical direct-write 繞過路徑。** 找到的是一個
**綁定缺口**（會漂、但目前沒漂）與一個 prose 重述風險。

| # | 嚴重度 | 標題 |
|---|---|---|
| F-01 | **P2** | `core_pipeline` 重述 canonical 順序但未綁定，且無任何 validator 讀取 |
| F-02 | **P3** | e2e 契約在 prose 內以箭頭重述路徑（機器綁定正確，僅文字有漂移風險）|

## F-01（P2）：`core_pipeline` 未綁定且未被讀取

`規格/v0.1/personal-harness-integration.yaml:668-678` 宣告一條 10 步
`core_pipeline`，其中含 canonical 尾段：

```
... → PERSONAL_MEMORY_CANDIDATE → VERIFICATION → PERSONAL_ACCEPTANCE
    → PERSONAL_MEMORY_RECORD → ...
```

- **未 pointer-bind**：整份契約沒有任何指回
  `ai-work-record-boundary.promotion_path` 的參照。
- **未被強制**（FP-1-B 的重點）：`grep -rn "core_pipeline" scripts/`
  **零命中**——沒有任何 validator 讀它。
- **對比**：同一份契約的 `core_invariants`（就在 `core_pipeline` 下方幾行）
  **有**被 `validate_ai_work_record_boundary_contract.rb:263` 讀取並斷言。
  也就是說相鄰的兩個 key，一個綁了、一個沒綁。

**目前不是繞過路徑**：順序與上游一致，沒有少步驟。風險是**漂移**——上游
若修改 `ordered_steps`，這裡不會有人發現；反之亦然。

依 FP-3-A，處置權在 Owner。可選方向（CC 不自行執行）：
(a) 讓它 pointer-bind 回上游並由 validator 斷言尾段一致；
(b) 明確宣告它是一條**不同**的流程（不是 canonical 升格路徑的重述），
    並在契約裡寫清楚兩者關係；
(c) 維持現狀，接受漂移風險——但已由本輪的常設 gate 登記在案。

## F-02（P3）：e2e prose 內的箭頭重述

`規格/v0.1/ai-work-record-e2e-acceptance.yaml:99-100` 在說明文字裡把路徑
寫成 5 段箭頭鏈。

**機器面是正確的**：`validate_ai_work_record_e2e_acceptance_contract.rb:201-208`
實際讀 `boundary.promotion_path.ordered_steps` 與 `receipts_required`，
斷言 `promotion_path_ref` 指向上游、`promotion_refs` 的步驟必須是上游成員、
並涵蓋 `receipts_required`。這是本 repo 裡綁得最紮實的一處。

風險僅在文字：prose 的箭頭鏈省略了第一步 `TASK_CARD_OR_WORK_RECORD`
（語境上它就是承載這些 ref 的 work_record 本身，故不構成弱化宣稱），但
若上游步驟日後調整，這段文字不會自動跟上。屬本 session 已反覆出現的
「舊 prose 沒跟著語意走」型態。

依 FP-3-A，是否要求文字也綁定，由 Owner 決定。

## 沒有發現問題的部分

- 其餘 5 份契約（`ai-work-record-hook` / `-loop` / 兩份 native adapter /
  `permission-retention-deletion`）**完全沒有重述 canonical 步驟**，只宣告
  `grants_canonical_writer: false` 與 forbidden 欄位清單。乾淨。
- `ai-work-record-harness` / `-hermes-adapter` / `-skill` 同上（各 3 處引用
  皆為「不取得權限」的宣告，非路徑重述）。
- **每一份 `規格/v0.1/*.yaml` 都至少被一支 validator 讀取**，沒有孤兒契約。
- 8 支 validator 實際讀取 `ai-work-record-boundary.yaml`，上游權威確實被
  下游使用，不是只寫在文件裡。

## FP-4-B：常設防線

新增 `scripts/validate_canonical_promotion_binding.rb`：

1. 從 boundary 讀出 canonical 步驟詞彙（**不硬編**）。
2. 走遍所有契約 YAML，找出任何「元素與 canonical 步驟重疊 ≥ 2 個」的陣列
   ——那就是在重述同一條路徑。
3. 該契約必須帶指回 `ai-work-record-boundary.promotion_path` 的 pointer，
   否則必須登記在 `KNOWN_UNBOUND` 並附 finding 編號與理由。
4. `KNOWN_UNBOUND` 的項目若已不存在也要紅，避免例外清單變殭屍。

`KNOWN_UNBOUND` 目前只有 F-01 一筆——依 FP-3-A **不自行修**，而是以
「已登記、待 Owner 裁決」的形式留著，既不默默修掉也不默默放行。

### 三種漂移模式皆已驗證會紅

```
移除 F-01 的登記            → FAIL core_pipeline ... 沒有指回 ... 也未登記
新增一份未綁定的重述契約     → FAIL zz-probe.yaml#probe_pipeline ...
例外清單登記不存在的項目     → FAIL KNOWN_UNBOUND 登記的 ghost.yaml#gone 已不存在
```

## Gate

```
ruby scripts/validate_*.rb（27 支，含新增這支）  → PASS
四支 Python schema engine                         → PASS
git diff --check                                   → clean
```

## 本輪明確沒有做的事（FP-3-A）

- **沒有開任何 repair 卡**，也沒有修改任何既有契約或 validator。
- 沒有自行判定 F-01 該怎麼處置——那是 Owner 的裁決。
