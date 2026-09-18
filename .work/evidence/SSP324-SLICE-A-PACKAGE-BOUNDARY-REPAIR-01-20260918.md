# SSP-324 切片 A — repair-01 evidence

日期：2026-09-18　branch：`cc/ssp324-package-boundary`

```
base            faf6822
original_review ebd2dd3（審的是 faf6822..3cecb25；ebd2dd3 只是 handoff SHA 補正）
repair_commit   7879330
```

## Reviewer NO_GO（2026-09-18，對 `3cecb25`）

```
P0=0 / P1=3 / P2=0 / P3=0
```

1. **P1**：Package 不是 closed shape——只驗 required + 固定 forbidden 名單，
   加 `private_blob="FULL_STORE_CONTENT"` → `nil`/PASS；
   `organizational_value_reasons` 用 `any?` 而非全元素驗證，同類 nested
   payload 也有洞。
2. **P1**：evidence／source anchor／ACL ref 只驗 generic OMOS URN——三個
   欄位分別換成 `urn:omos:canonical:secret` 全部 PASS。
3. **P1**：`content_snapshot`／`content_hash` 沒有形成 bounded integrity
   boundary——整份 Personal Store 序列化成一個字串仍合法；
   `content_hash="not-a-hash"` PASS；內容改掉但 hash 不變也 PASS。

裁決：交付包問題 1／2 判為 P1 必須收；問題 3（access_request 不加
actor/permission）接受維持現狀；問題 4（切片 3 P2）在 bypass 關閉前不得
標 CLEARED。

## 修法

### F-01：package 變成 closed shape

`package_required_fields` 同時就是完整 allowlist：`package.keys -
PACKAGE_REQUIRED_FIELDS` 必須為空（`MEP_PACKAGE_UNKNOWN_FIELD`）。禁用
清單保留在 allowlist **之前**，讓那些特定名字仍以自己的明確錯誤碼失敗，
兩個檢查都可達。`organizational_value_reasons` 的 `any?` 改成
「非空陣列 ＋ 全元素皆為非空字串」。

### F-02：ref 綁上游真正定義它的形狀

- canonical ref matcher 由 `common-vocabulary.identifiers.omos_generated.
  ref_template`（`urn:omos:{resource-kind}:{uuid}`）與
  `common-vocabulary.resource_kinds` 在評估當下組出來，URN 結構不手抄。
- `evidence_refs` pin `EVIDENCE_RECORD`；`source_anchor_refs` pin
  `SOURCE_ANCHOR`（validator 另斷言這兩個 kind 確實在上游 resource_kinds
  裡，且 YAML 宣告的 pinned kind 與 evaluator 實際 pin 的一致）。
- `source_acl_snapshot_ref` 綁 STD-01 schema 的
  `access.acl_snapshot_ref.pattern`，pattern 從 schema 讀、不手抄——與
  `validate_permission_retention_deletion_contract.rb` 綁的是同一個來源。
- **誠實邊界**：上游沒有 PROVENANCE resource kind，所以
  `provenance_chain_refs` 只能綁到「kind 屬於上游宣告的 resource_kinds」
  這個層級，不是 pinned kind；`package_id`／`employee_owner_ref`／
  `consent_ref`／`redaction_ref` 是 org 端 identity、不是 OMOS canonical
  resource，維持 generic omos-URN。兩者都寫進契約的 `ref_binding.
  known_gap`，不讓它們看起來跟 pinned 欄位一樣強。

### F-03：bounded content + 真正可驗的 integrity

- `content_bound.max_bytes`（4096，UTF8_BYTES）宣告在契約裡，evaluator
  從值本身量 `bytesize`，不信任任何自報 size 欄位
  （`MEP_CONTENT_SNAPSHOT_OVER_BOUND`）。數字是 policy，住在契約不在程式。
- `content_hash` 必須符合既有 `SHA256_LOCKED_PATTERN`
  （`MEP_CONTENT_HASH_NOT_SHA256`），**並且** evaluator 依
  `content_hash_basis`（SHA-256、content_snapshot 的 UTF-8 bytes、
  逐字不正規化）重算後必須完全相符（`MEP_CONTENT_HASH_MISMATCH`）。
  「內容改掉、hash 不動」不再可能。

## 重播 reviewer 的 exploit（對修好的程式碼）

```
baseline（未改）                                → nil
private_blob="FULL_STORE_CONTENT"               → MEP_PACKAGE_UNKNOWN_FIELD
organizational_value_reasons nested payload     → MEP_VALUE_REASONS_EMPTY
evidence_refs = urn:omos:canonical:secret       → MEP_EVIDENCE_REF_NOT_CANONICAL
source_anchor_refs = urn:omos:canonical:secret  → MEP_SOURCE_ANCHOR_REF_NOT_CANONICAL
source_acl_snapshot_ref = urn:omos:canonical:secret → MEP_ACL_SNAPSHOT_REF_NOT_CANONICAL
whole store 序列化進 content_snapshot            → MEP_CONTENT_SNAPSHOT_OVER_BOUND
content_hash = "not-a-hash"                     → MEP_CONTENT_HASH_NOT_SHA256
內容改掉但 hash 不變                             → MEP_CONTENT_HASH_MISMATCH
```

九個變體全數關閉（含 baseline 仍通過，證明不是全部擋掉了事）。另補一筆
`urn:omos:evidence-record:not-a-uuid` 的負例：kind 對了但 uuid 不合法
仍拒絕。

## 逐 return site parity（非逐 code）

26 個 return site（repair 前 18 個，本輪新增 8 個）逐一中和 → 26/26
全紅，未被測到：無。

## 接回總入口的實測

```
中和 MEP_PACKAGE_UNKNOWN_FIELD（reviewer 的 private_blob repro）：

直接呼叫新片   → FAIL MEP_NEG_PACKAGE_UNKNOWN_FIELD 預期 deny，實際通過
               → FAIL error_contract 宣告但 evaluator 不可能回傳
呼叫總入口     → 同樣的 FAIL，外加
               → FAIL personal memory contract validation :: slice
                 validate_minimal_evidence_package_contract exited 1

還原後 diff 逐位元相同，兩個入口都回到 PASS。
```

## Fixture 變更

負例 22 → 31。新增涵蓋：closed-shape bypass（`private_blob`）、
`organizational_value_reasons` nested payload、三個 ref 欄位各自的
`urn:omos:canonical:secret`、evidence ref kind 對但 uuid 不合法、
content 超出 byte bound、hash 形狀錯、hash 與內容不符。正例的
`evidence_refs`／`source_anchor_refs`／`provenance_chain_refs`／
`source_acl_snapshot_ref` 全部改成真正的 canonical ref，`content_hash`
改成實際計算出來的 SHA-256。

## 切片 3 的 P2

依裁決改標 `CLEARED_CONTRACT_LEVEL`（首輪誤標 `CLEARED`）：contract 層
兩項封閉列舉都有實際 enforcement；**runtime 層仍由 `SSP-295` 真人 pilot
負責**，已在 backlog 該列明寫。

## Gate

```
ruby scripts/validate_*.rb（35 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
```
