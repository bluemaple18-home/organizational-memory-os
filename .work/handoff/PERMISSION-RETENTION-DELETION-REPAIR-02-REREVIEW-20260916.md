# repo #4 repair-02 — 定點 re-review 交付包

同一條 review line。收 `4ddbfe5` 的 P1×2。

## 鎖定

```
base                23e6a95
original_review     12b7c90   （NO_GO，P1=2）
repair_01           4ddbfe5   （NO_GO，P1=2，同一根因）
repair_commit       <見對話中的派工區塊>
branch              cc/permission-retention-deletion
```

## 先講結論：根因**沒有**被關閉，而是被明確界定並記錄

你兩輪指出的是同一件事：caller 自己提供所謂的權威事實。我沒有做第三次
「多要一個 caller 輸入」的嘗試，而是先查證：

- 全 repo 沒有任何既有契約記錄 retention 歷史。
- 要綁就得建持久紀錄 = retention DB／ledger，**卡片自身 Constraints 與
  `FORBIDDEN_BY_DEFAULT` 都禁止**。
- 唯一既有權威 `source-anchor.schema.json`（`access` 同時 required
  `acl_snapshot_ref` 與 `permission_decision_ref`）可用，但 anchor 本身仍是
  caller 提交的。

→ 升級 Owner 裁決（`.work/CARD-PRD-PROVENANCE-BINDING-SPEC-FREEZE-20260916.md`），
Owner 簽 **(A)**：誠實記錄邊界 ＋ 示範性 fixture，不新增儲存。

## 本輪實際做了什麼

1. **F-02 結構改良**：`permission_staleness_failure` 不再收 run 直接宣告的
   兩個 snapshot ref，改為要求提交 `source_anchor` 與 `evidence_envelope`
   兩份紀錄，事實從紀錄自己的欄位讀，並要求兩者 `evidence_ref` 相同。
2. **`provenance_boundary`**：契約明寫
   `verifies: SUBMITTED_RECORDS_ARE_MUTUALLY_CONSISTENT` /
   `does_not_verify: SUBMITTED_RECORDS_ARE_AUTHENTIC`，並逐字記錄兩輪被打穿
   的過程與為何這是能力上限。`hard_stops` 補上「不建權威儲存」。
3. **示範性 fixture**：`PRD_POS_FORGED_HISTORY_KNOWN_GAP` 與
   `PRD_POS_CALLER_SUPPLIED_RECORDS_KNOWN_GAP`——刻意會通過的正例，各自帶
   `known_gap` 說明，證明缺口是真的而非假裝不存在。
4. **讓「記錄了缺口」也可驗**：契約列出的 `demonstrative_fixtures` 必須存在
   於正例且必須帶 `known_gap`；刪掉任一個 → gate 紅。

## 請重播

```bash
ruby scripts/validate_permission_retention_deletion_contract.rb   # 應 PASS

# 你的兩個 exploit 現在是「已登記的已知缺口」，而非未察覺的洞：
#   自洽偽造 history                    → 仍通過（PRD_POS_FORGED_HISTORY_KNOWN_GAP）
#   caller 提交兩份快照相同的紀錄        → 仍通過（PRD_POS_CALLER_SUPPLIED_RECORDS_KNOWN_GAP）
# 差別在契約現在明說它驗不了這件事，並用 fixture 釘住。

# 刪掉任一示範 fixture → 應 FAIL（缺口不得被默默移除）
# 逐 return site parity（非逐 code）→ 我的結果 22/22 全紅
```

## Gate

```
ruby scripts/validate_*.rb（26 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
validator 337 行 / 契約 252 行（< 400）
```

## 請判斷

1. 「界定並記錄」是否為本卡可接受的收斂方式（Owner 已簽 (A)，先例為
   `ai-work-record-hook.yaml` 的 `batch_scoping_rule`）。
2. `provenance_boundary` 的措辭是否誠實、沒有把缺口說小。
3. 兩個 `*_KNOWN_GAP` fixture 是否真的釘住了你這兩輪的 exploit。
4. F-02 的結構改良（綁 anchor／envelope 欄位）是否至少讓「run 直接宣告
   新鮮度」這條路消失。
