# SSP-324 切片 B — 大 review 交付包

## 鎖定

```
base    72ac78d
review  3119fa1
branch  cc/ssp324-revision-dedup
```

```
規格/v0.1/personal-harness-integration.yaml         +evidence_package_revision
scripts/validate_evidence_package_revision_contract.rb   262 行
規格/v0.1/fixtures/evidence-package-revision-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb        +1 行（SLICE_VALIDATORS）
```

**未修改切片 A 的封包契約、`historical_comparison`、`correction_flow` 任何
一行。**

## 這張卡

`SSP-324`（EMEM-10）切片 B：immutable revision 與 dedup／resend。驗證單位
是**同一個 candidate 的提交鏈**——重複重送與鏈分叉只有跨筆比對看得見。

**關鍵決定：信封，不動封包。** 切片 A 的 `package_required_fields` 是封閉
allowlist；把 revision 欄位加進封包會重開一個已驗收的封閉 shape。所以 B
用外層信封包住 A 的封包，契約以 `layering_boundary` 明寫分層。

## 我先套用了切片 A 兩輪 NO_GO 的教訓

上兩輪都是同一個模式：**只鎖了名字，沒鎖值**。這片在設計階段就處理：

- `submission_allowed_fields` 封閉 allowlist，且每個讀到的值另有形狀檢查
  （URN／sha256／map）
- `content_hash` 直接用既有共用的 `SHA256_LOCKED_PATTERN`，不自寫 regex
- `non_transmittable_dispositions` 這份本片新增的清單，每個值都必須存在於
  上游 `historical_comparison.dispositions`（斷言強制），且每個值都必須被
  負例實際打過（另一條斷言）

## 請重播

```bash
ruby scripts/validate_evidence_package_revision_contract.rb   # 應 PASS
ruby scripts/validate_personal_memory_contract.rb              # 應 PASS（聚合器）

# 卡片 Acceptance #7（UNCHANGED 不重送）
grep -A4 "PKGREV_NEG_RESEND_UNCHANGED"        規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json
grep -A4 "PKGREV_NEG_RESEND_LOCAL_RECURRENCE" 規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json
# immutable / 可追溯
grep -A4 "PKGREV_NEG_CHAIN_FORK"              規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json
grep -A4 "PKGREV_NEG_DUPLICATE_PACKAGE_ID"    規格/v0.1/fixtures/evidence-package-revision-negative-fixtures.json
```

逐 return site parity：22/22 全紅；中和 Acceptance #7 的 guard 驗證聚合器
同步轉紅；36/36 Ruby validator PASS；`git diff --check` clean。

## 對應卡片 Acceptance

```
#6 已提交 package 的後續變化只能追加        → PKGREV_DUPLICATE_PACKAGE_ID /
   revision/supersession；舊 package 可驗     PKGREV_CHAIN_FORK /
   hash/provenance                            PKGREV_PREDECESSOR_NOT_IN_CHAIN /
                                              PKGREV_CONTENT_HASH_NOT_SHA256
#7 UNCHANGED 不重送；material effect 才      → PKGREV_RESEND_DESPITE_NON_TRANSMITTABLE /
   產生 update                                PKGREV_DISPOSITION_NOT_DECLARED_FOR_CATEGORY
「不建立第二套 revision lifecycle」          → correction_kind 綁 correction_flow；
                                              非 correction disposition 不得帶 correction 欄位
#1/#2/#3/#4/#5/#8                            → 切片 A 已收或切片 C（明確不在本片）
```

## 請特別判斷

1. **`non_transmittable_dispositions` 是本片唯一自創的決定**：上游沒有
   「哪些 disposition 授權對外傳輸」這個概念。我用「明寫在契約 + 每個值
   必須存在於上游 dispositions + 每個值必須被負例打過」三層約束。請判斷
   這個處理是否恰當，或該由 Owner 簽。
2. **B 不重驗封包內部形狀**（只鎖自己讀的三個欄位）：理由是 A 已驗、兩支
   同在一個 aggregator 下。請確認這個分層切分正確，或 B 該連封包一起驗。
3. **鏈的順序來自陣列順序**：B 假設 `submissions` 是依序排列，並以此判定
   「第一筆」與「predecessor 必須更早出現」。目前沒有用 timestamp 交叉
   驗證順序。請判斷是否該加（例如要求 `submitted_at` 單調遞增），或順序
   由提交方負責即可。

## Gate

```
ruby scripts/validate_*.rb（36 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
