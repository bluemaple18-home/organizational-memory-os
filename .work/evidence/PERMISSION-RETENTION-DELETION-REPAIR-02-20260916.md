# repo #4 repair-02 — evidence

回應 `4ddbfe5` 的 NO_GO（P1×2）。兩筆是同一根因：**caller 自己提供所謂的
權威事實**。這是該根因第二次被打穿，因此本輪**先停下來查證、再升級 Owner
裁決**，不做第三次「多要一個 caller 輸入」的嘗試。

## 為什麼不是第三次修，而是升級

- 全 repo grep：**沒有任何既有契約記錄 retention 歷史**（唯一提到的是本契約
  自己）。要綁就得建持久紀錄。
- 建持久紀錄 = retention DB／ledger，**卡片自身 Constraints 與
  `FORBIDDEN_BY_DEFAULT` 都明文禁止**。
- 唯一既有權威是 `source-anchor.schema.json`：`access` 同時 required
  `acl_snapshot_ref` 與 `permission_decision_ref`。可用，但 anchor 本身仍是
  caller 隨 run 提交的，無處查證。

結論：這一層**能驗「提交的紀錄彼此自洽」，不能驗「紀錄本身為真」**，除非
有可查的權威來源——而那個來源不存在且被禁止建立。

Owner 於 2026-09-16 簽 **(A)**：誠實記錄邊界 ＋ 示範性 fixture。

## 實作

### 1. F-02 的結構改良（仍保留，但不宣稱關閉根因）

`permission_staleness_failure` 不再接受 run 直接宣告的兩個 snapshot ref，
改為要求提交兩份既有契約定義的紀錄，事實從紀錄自己的欄位讀：

- `source_anchor`（STD-02）→ `access.permission_decision_ref` 當初基於
  `access.acl_snapshot_ref` 做成
- `evidence_envelope`（STD-01）→ `access.acl_snapshot_ref` 為現行 ACL

並檢查兩份紀錄的 `evidence_ref` 相同（否則是拿不相干的東西互比）。新增
`PRD_FRESHNESS_RECORDS_MISSING`／`PRD_FRESHNESS_RECORD_MISMATCH`。

### 2. `provenance_boundary`（FP-1-A 的本體）

契約新增 `provenance_boundary` 區塊，明寫：

```
verifies:        SUBMITTED_RECORDS_ARE_MUTUALLY_CONSISTENT
does_not_verify: SUBMITTED_RECORDS_ARE_AUTHENTIC
caller_responsibility: SUBMITTED_RECORD_AUTHENTICITY
precedent: ai-work-record-hook.yaml#capture_contract.batch_scoping_rule
```

並逐字記錄兩輪被打穿的過程，說明為何這不是疏漏而是這一層的能力上限。
`hard_stops` 也補上「不建權威 retention-history／decision-receipt 儲存」。

### 3. 示範性 fixture（證明缺口是真的）

兩個**正例**，刻意會通過，各自帶 `known_gap` 說明：

| case_id | 證明什麼 |
|---|---|
| `PRD_POS_FORGED_HISTORY_KNOWN_GAP` | 自洽但偽造的 history 會通過——本層分辨不出 |
| `PRD_POS_CALLER_SUPPLIED_RECORDS_KNOWN_GAP` | caller 提交的 anchor／envelope 只要快照相同就通過，即使兩份都是偽造 |

### 4. 讓「記錄了缺口」這件事本身也可驗

契約列出的 `demonstrative_fixtures` 必須真的存在於正例中、且必須帶
`known_gap` 說明。驗證這道斷言會紅：

```
暫時刪掉 PRD_POS_FORGED_HISTORY_KNOWN_GAP
  → FAIL provenance_boundary 宣稱的示範 fixture ... 不存在於正例中
```

否則契約可以宣稱「缺口有被誠實記錄」，而 fixture 早就被人默默刪掉。

## Gate

```
ruby scripts/validate_*.rb（26 支）         → PASS
四支 Python schema engine                   → PASS
git diff --check                             → clean
逐 return site parity（22 個 site）          → 22/22 全紅，無遺漏
validator 337 行 / 契約 252 行（皆 < 400）
```

## 明確沒有宣稱的事

- **沒有宣稱「caller 無法偽造」**。本層做不到，這正是 `provenance_boundary`
  與兩個 `*_KNOWN_GAP` fixture 存在的理由。
- 要真正關閉這個根因需要可查的權威紀錄，那是 Owner 簽 (B) 才會展開的獨立
  大卡，不在本卡。
