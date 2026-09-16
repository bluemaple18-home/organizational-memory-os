# repo #4 repair-03 — 定點 re-review 交付包

同一條 review line。只收 `d058e1f` 的那一筆 P1。

## 鎖定

```
base                23e6a95
original_review     12b7c90
repair_01           4ddbfe5
repair_02           d058e1f   （NO_GO，P1=1：兩個 normative surface 矛盾）
repair_commit       <見對話中的派工區塊>
branch              cc/permission-retention-deletion
```

## 收法

`freshness_binding` 的敘述仍停在 repair-01 的舊形狀
（`decision_acl_snapshot_ref` / `current_acl_snapshot_ref`），而
`retrieval_run.fields` 與 evaluator 已是 `source_anchor` /
`evidence_envelope`。已改寫敘述並逐行列出事實來源；全 repo 舊欄位名殘留
**0 命中**。

**另外加了兩道機器防線**，因為這是本 session 第二次「改了語意、舊 prose
沒跟著走」（native adapters 那輪同型）：

1. `retrieval_run.fields` 必須與 evaluator 實際讀取的 key 雙向一致。
2. 契約新增 `freshness_binding_records`（承載 freshness 事實的紀錄欄位），
   必須同時出現在 fields、evaluator 實讀、與 `freshness_binding` 敘述裡。

## 請重播

```bash
grep -rn "decision_acl_snapshot_ref\|current_acl_snapshot_ref" 規格/ scripts/
# 我的結果：0 命中

ruby scripts/validate_permission_retention_deletion_contract.rb   # 應 PASS

# 防線探測（請移除「所有」提及，只改一句不夠——見下）
#   敘述中移除全部 evidence_envelope 提及  → 應 FAIL
#   retrieval_run.fields 改回舊欄位名       → 應 FAIL（三條）
```

**主動揭露**：我第一次探測防線時只改了一句敘述，gate 仍 PASS——因為敘述
後面還有 `source_anchor.access...` 等提及。那是探測不夠力，不是斷言無效；
移除全部提及後正確轉紅。請重播時注意這點，以免低估或高估這道斷言。

## Gate

```
ruby scripts/validate_*.rb（26 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
逐 return site parity                 → 22/22 全紅
validator 363 行 / 契約 270 行（< 400）
```

## 請只判斷

這一筆是否已關閉，以及兩道新防線是否真的能擋住同類漂移。
`provenance_boundary` 與 `*_KNOWN_GAP` 你已接受，未重開。
