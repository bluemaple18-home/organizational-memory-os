# 收 repo #5 F-01 — evidence

日期：2026-09-17　branch：`cc/core-pipeline-promotion-binding`　base：`8bf224c`
Owner 裁決：F-01 在 SSP-294 開工前以小卡收掉；F-02 維持 P3。

## 四個探測（全部實測）

```
探測 1：上游把 VERIFICATION 改名 VERIFICATION_STEP
  → FAIL core_pipeline_promotion_binding.covers 含上游已不存在的步驟
         （移除或改名？）：VERIFICATION

探測 2：上游移除 VERIFICATION
  → FAIL（同上）

探測 3：core_pipeline 偷偷刪掉 VERIFICATION、covers 沒改
  → FAIL core_pipeline 實際出現的 canonical 步驟必須與 covers 宣告一致：
         實際=[CANDIDATE, ACCEPTANCE, RECORD] 宣告=[CANDIDATE, VERIFICATION, ACCEPTANCE, RECORD]

探測 4：拿掉結構化 pointer（散文仍提到）
  → 第一次：**沒有紅**（見下）
  → 修正後：FAIL ...沒有指回 ai-work-record-boundary.promotion_path 的 pointer
```

探測 1／2 正是本卡存在的理由——repair-01 的語意比對補不到「上游瘦身、副本
留下孤兒步驟」這一種。

## 自己抓到的洞（探測 4）

canonical gate 原本判定綁定的方式是 `raw.include?(BOUNDARY_POINTER)`——
**整份檔案文字裡有沒有出現那串字**。所以把 `promotion_path_ref` 改成
`none`、只靠下方 `rule` 散文裡提到 pointer，仍會被當成已綁定。

這與 repo #5 大 review 指出的 P1 是同一類（驗存在、不驗實質），只是出現在
另一個位置。改成只認結構化欄位的值：某個 scalar 的**整個值**必須是 pointer
或其點號延伸才算綁定；散文因為前後有句子，整值比對不會命中。

## Gate

```
ruby scripts/validate_*.rb（27 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
canonical gate                        → known unbound=0（例外清空）
```

## 改動範圍

```
規格/v0.1/personal-harness-integration.yaml         +25（新增 binding 宣告，未改既有步驟）
scripts/validate_ai_work_record_boundary_contract.rb +36（三條斷言）
scripts/validate_canonical_promotion_binding.rb     +31/-7（清空例外、改綁定判定）
```

未改動 canonical 權威本身，未碰 F-02。
