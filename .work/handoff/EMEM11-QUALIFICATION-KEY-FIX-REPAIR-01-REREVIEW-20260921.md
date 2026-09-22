---
id: EMEM11-QUALIFICATION-KEY-FIX-REPAIR-01-REREVIEW-20260921
card: CARD-EMEM11-QUALIFICATION-KEY-FIX-20260921
repair: 01
type: rereview
verdict: GO
reviewed_commit: d771058
base: 06f6c6f
---

# qualification key repair-01 再 review｜GO

| 級別 | 數量 |
|---|---|
| P0 | 0 |
| P1 | 0 |
| P2 | 0 |
| P3 | 0 |

兩筆 P1 **CLOSED**。

## 1. P1-1 integrity

reviewer **未沿用交付方的五種破壞方式**，改用「64 字元、但含非 hex 的 `g`」
破壞宣告，正確 fail closed 回 `OMOS_ARTIFACT_LINKAGE_DIGEST_MALFORMED`。

## 2. P1-2 兩層分家

行為與 Owner 裁決一致：

| 情境 | 結果 |
|---|---|
| metadata-only CPU ＋ ABI mismatch | `UNQUALIFIED_RUNTIME_PROFILE` |
| `/usr/bin/ruby` 真 ABI 不符 | exit 78 |
| native extension 真載不動 | exit 78 / `OMOS_NATIVE_REQUIRE_FAILED` |
| native linkage 真解析不到 | exit 78 / `OMOS_NATIVE_DEPENDENCY_UNRESOLVED` |

reviewer 另檢查 `verify!` 的順序為
**live native probe → artifact integrity → qualification key**，
在目前模型內**沒找到**「實際 runtime 已不相容、卻一路只落到 UNQUALIFIED」
的路徑。

## 3. reviewer 自己的鑑別力反證

只把 missing-declaration 的錯誤碼改錯，結果只有對應的 missing invariant
轉紅、其他 repair 保護仍綠——鑑別力成立，不是一反轉就整片紅的粗測試。

## 4. reviewer 側實跑

| 項目 | 結果 |
|---|---|
| 3a | 26/26 PASS |
| 3b | 34/34 PASS |
| 3c | 154/154 PASS |
| validators | 40/40 PASS |
| `git diff --check` | clean |

**`d771058` 可收，qualification key repair-01 ACCEPTED_GO。**
