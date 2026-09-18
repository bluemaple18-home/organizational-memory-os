# SSP-324 切片 A — repair-02 定點複審交付包

## 鎖定

```
base             faf6822
repair-01        7879330（delivery fd1278b）
repair_commit    （本次 commit，待 push 後補上）
branch           cc/ssp324-package-boundary
```

## 這輪只收那一筆 F-02 同根 P1

matcher 的 UUID 版本改成**從上游宣告推導**，不是寫死：

```ruby
id_algorithm       = vocab.dig("identifiers", "omos_generated", "algorithm")  # "UUIDv7"
uuid_version_digit = id_algorithm[/\AUUIDv(\d)\z/, 1]
```

- version nibble（第三段首字）與 variant nibble（第四段首字 `8/9/a/b`）
  一起守。
- 新增兩條契約斷言：`algorithm` 必須是 `UUIDv<n>` 形式；
  `id_serialization` 必須仍是 `lowercase-hyphenated-uuid`。上游改版本號，
  matcher 自動跟著走。
- **同根一併收**：`candidate_ref` 從「只比對前綴」改成套用同一條 identity
  shape。

## 請重播

```bash
ruby scripts/validate_minimal_evidence_package_contract.rb   # 應 PASS
ruby scripts/validate_personal_memory_contract.rb             # 應 PASS（聚合器）

# 你的兩筆 repro
grep -A6 "MEP_NEG_EVIDENCE_REF_UUIDV4"      規格/v0.1/fixtures/minimal-evidence-package-negative-fixtures.json
grep -A6 "MEP_NEG_SOURCE_ANCHOR_REF_UUIDV4" 規格/v0.1/fixtures/minimal-evidence-package-negative-fixtures.json
# 我方同根掃描補的
grep -A6 "MEP_NEG_CANDIDATE_REF_NOT_UUIDV7" 規格/v0.1/fixtures/minimal-evidence-package-negative-fixtures.json
```

重播結果（含你沒點名、我自己掃出來的三個同根變體）：

```
baseline（UUIDv7）                  → nil
evidence_refs 用 UUIDv4             → MEP_EVIDENCE_REF_NOT_CANONICAL
source_anchor_refs 用 UUIDv4        → MEP_SOURCE_ANCHOR_REF_NOT_CANONICAL
provenance_chain_refs 用 UUIDv4     → MEP_PROVENANCE_REF_NOT_CANONICAL
candidate_ref 用 UUIDv4             → MEP_CANDIDATE_REF_NOT_CANDIDATE
version 對但 variant nibble 非法     → MEP_EVIDENCE_REF_NOT_CANONICAL
```

26/26 return site 全紅；中和 `MEP_EVIDENCE_REF_NOT_CANONICAL` 驗證聚合器
同步轉紅；35/35 Ruby validator PASS；`git diff --check` clean。

## 請注意兩件我主動揭露的事

1. **原本的 fixture identity 根本不是合法 UUIDv7**（`00000001-1111-2222-…`
   的第三段首字是 `2`）。這本身就是上一輪 matcher 太鬆的證據——全部
   fixture 已改成合法 UUIDv7。
2. **切片 4 有同款不一致，本輪未修**：
   `validate_weekly_review_cycle_contract.rb` 的
   `WRC_ITEM_REF_NOT_CANDIDATE` 對同一個 id_template 也只比對前綴，所以
   `urn:omos:personal-memory:candidate:<UUIDv4>` 在切片 4 仍會通過。切片 4
   已 `ACCEPTED_GO`、且驗的是本機 closeout 歷史而非對外傳輸，我判斷不該
   在這輪重開，已登 `文件/待辦重整.md` 為 P3。**請裁決這個判斷是否成立**
   ——若你認為應該一併收，我照辦。

## Gate

```
ruby scripts/validate_*.rb（35 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
