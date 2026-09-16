# repo #4 repair-03 — evidence

回應 `d058e1f` 的 NO_GO（P1×1）。只收這一筆。

## F-01（P1）：contract 兩個 normative surface 互相矛盾

屬實。repair-02 把輸入形狀從「run 直接帶兩個 snapshot ref」改成
「提交 `source_anchor` ＋ `evidence_envelope` 兩份紀錄」，同時改了
`retrieval_run.fields` 與 evaluator，**卻沒有更新
`permission_decision_contract.freshness_binding` 的敘述**——那段仍寫著
`decision_acl_snapshot_ref` / `current_acl_snapshot_ref`。

於是同一份契約的兩個規範面會導出不同實作，照舊敘述實作就會拿到
`PRD_FRESHNESS_RECORDS_MISSING`。

**這是本 session 第二次犯同一類錯**：native adapters 那輪也是改了語意、
舊 prose 沒跟著走，被大 review 擋下。所以本輪除了改文字，另外加了機器
防線（見下）。

## 修法

### 1. 更新敘述

`freshness_binding` 改寫成 repair-02 實際的綁定，並逐行列出事實來源：

```
source_anchor.access.permission_decision_ref  -- 依據的 decision
source_anchor.access.acl_snapshot_ref         -- 當初基於哪個 ACL
evidence_envelope.access.acl_snapshot_ref     -- 現行 ACL
```

也寫明兩份紀錄必須 `evidence_ref` 相同，以及「這不建立紀錄的真實性，
見 provenance_boundary」。

全 repo grep `decision_acl_snapshot_ref|current_acl_snapshot_ref`：
**0 命中**（evidence／handoff 的歷史記述除外）。

### 2. 加機器防線，讓同類漂移不可能再默默發生

新增兩道斷言：

- **宣告 ↔ 實讀雙向一致**：`retrieval_run.fields` 必須與 evaluator 實際
  讀取的 `run["..."]` key 集合完全相同。
- **敘述 ↔ 形狀一致**：契約新增 `freshness_binding_records`
  （`source_anchor` / `evidence_envelope`——承載 freshness 事實的紀錄欄位；
  `access_granted` 是被判定的結果，不是依據，刻意不納入），這些欄位必須
  同時出現在 `retrieval_run.fields`、evaluator 實讀集合、以及
  `freshness_binding` 的敘述裡。

### 3. 證明這兩道防線會紅

```
探測 1：敘述中移除所有 evidence_envelope 提及
  → FAIL freshness_binding 的敘述未提到 evidence_envelope（敘述與輸入形狀已漂移）

探測 2：retrieval_run.fields 改回舊欄位名
  → FAIL retrieval_run.fields 必須與 evaluator 實際讀取的 key 相同：
         宣告=[...decision_acl_snapshot_ref...] 實讀=[...source_anchor...]
  → FAIL freshness_binding_records 的 source_anchor 不在 retrieval_run.fields 裡
  → FAIL freshness_binding_records 的 evidence_envelope 不在 retrieval_run.fields 裡
```

第一次探測時我只改了一句敘述，gate 仍 PASS——因為後面還有
`source_anchor.access...` 等提及。那是**探測不夠力**而非斷言無效；改成移除
全部提及後正確轉紅。這點記下來，避免日後誤判這道斷言的強度。

## Gate

```
ruby scripts/validate_*.rb（26 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
逐 return site parity（22 個）        → 22/22 全紅
validator 363 行 / 契約 270 行（< 400）
舊欄位名殘留                           → 0
```

## 未改動

- `provenance_boundary` 與兩個 `*_KNOWN_GAP` fixture 原樣保留（reviewer 已
  接受 Owner 簽的 (A)）。
- 未動任何既有契約或 validator。
