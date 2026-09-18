# SSP-324 切片 A — repair-02 evidence

日期：2026-09-18　branch：`cc/ssp324-package-boundary`

```
base            faf6822
repair-01       7879330（delivery fd1278b）
repair_commit   8ed905a
```

## Reviewer NO_GO（2026-09-18，對 `7879330` / delivery `fd1278b`）

```
P0=0 / P1=1 / P2=0 / P3=0
```

repair-01 的三個 P1 原始問題確認關閉（closed-shape bypass、wrong-kind
ref、content integrity），唯一殘留是 **F-02 同根 P1**：

> `common-vocabulary` 明確規定 OMOS-generated identity 是 **UUIDv7**，
> 但 repair-01 新寫的 canonical matcher 只驗「任意 UUID 格式」。

reviewer 重播：

```
urn:omos:evidence-record:123e4567-e89b-42d3-a456-426614174000（UUIDv4）→ PASS
urn:omos:source-anchor:123e4567-e89b-42d3-a456-426614174000（UUIDv4）→ PASS
```

即「kind 綁對了，但 canonical identity shape 還沒完整綁回上游」。

同輪裁決：`max_bytes = 4096` 接受不需 Owner freeze；
`provenance_chain_refs` 弱綁定接受維持 known gap，不新增 PROVENANCE
kind；`CLEARED_CONTRACT_LEVEL` 措辭正確，待本 P1 關閉後正式成立。

## 修法

matcher 的 UUID 版本不是寫死的 `7`，而是從上游宣告推導：

```ruby
id_algorithm = vocab.dig("identifiers", "omos_generated", "algorithm")  # "UUIDv7"
uuid_version_digit = id_algorithm[/\AUUIDv(\d)\z/, 1]                   # "7"
```

- `uuid_pattern(version_digit)` 同時守 **version nibble**（第三段首字）
  與 **variant nibble**（第四段首字須為 `8/9/a/b`，RFC 9562）。
- 另加兩條契約斷言：上游 `algorithm` 必須是 `UUIDv<n>` 形式；
  `id_serialization` 必須仍是 `lowercase-hyphenated-uuid`（否則本 matcher
  的小寫十六進位假設不再成立，必須一起檢討）。上游改版本號，matcher 自動
  跟著走，不必回來改這支。
- **同根一併收**：`candidate_ref` 原本只比對 id_template 前綴，
  改用 `build_id_template_pattern` 套用同一條 identity shape——
  `urn:omos:personal-memory:candidate:<UUIDv4>` 以前會通過，現在不會。

## 重播（對修好的程式碼）

```
baseline（UUIDv7）                                → nil
evidence_refs 用 UUIDv4       ← reviewer repro    → MEP_EVIDENCE_REF_NOT_CANONICAL
source_anchor_refs 用 UUIDv4  ← reviewer repro    → MEP_SOURCE_ANCHOR_REF_NOT_CANONICAL
provenance_chain_refs 用 UUIDv4  ← 我方同根掃描    → MEP_PROVENANCE_REF_NOT_CANONICAL
candidate_ref 用 UUIDv4          ← 我方同根掃描    → MEP_CANDIDATE_REF_NOT_CANDIDATE
version 對但 variant nibble 非法 ← 我方同根掃描    → MEP_EVIDENCE_REF_NOT_CANONICAL
```

reviewer 指名的兩筆之外，另外三個同根變體也一併關閉並補了負例，避免下一輪
再以「同一個根因換個欄位」回來。

## 逐 return site parity（非逐 code）

26/26 全紅（return site 數量未變，本輪是既有 matcher 收緊，不是新增
guard），未被測到：無。

## 接回總入口的實測

```
中和 MEP_EVIDENCE_REF_NOT_CANONICAL（UUIDv4 repro 的 guard）：

直接呼叫新片   → FAIL MEP_NEG_EVIDENCE_REF_NOT_CANONICAL／_BAD_UUID／_UUIDV4
               → FAIL error_contract 宣告但 evaluator 不可能回傳
呼叫總入口     → 同樣的 FAIL，外加
               → FAIL personal memory contract validation :: slice
                 validate_minimal_evidence_package_contract exited 1

還原後 diff 逐位元相同，兩個入口都回到 PASS。
```

## Fixture 變更

- 全部 fixture 的 identity 改成**合法 UUIDv7**（第三段首字 `7`、第四段首字
  `8`）——原本用的 `00000001-1111-2222-...` 並不是合法 UUIDv7，這本身就是
  上一輪沒被擋下來的證據。
- 負例 31 → 34：新增 `MEP_NEG_EVIDENCE_REF_UUIDV4`、
  `MEP_NEG_SOURCE_ANCHOR_REF_UUIDV4`（reviewer 的兩筆 repro）、
  `MEP_NEG_CANDIDATE_REF_NOT_UUIDV7`（同根）。

## 一併記錄：切片 4 的同款不一致（未在本輪修）

`validate_weekly_review_cycle_contract.rb` 的 `WRC_ITEM_REF_NOT_CANDIDATE`
對同一個 `PersonalMemoryCandidate` id_template 也只比對前綴，因此
`urn:omos:personal-memory:candidate:<UUIDv4>` 在切片 4 仍會通過。切片 4
已 `ACCEPTED_GO`，且它驗的是本機 closeout 歷史而非對外傳輸，影響有限，
故不在本輪重開——已登 `文件/待辦重整.md` 為 P3，修法已知（改用同款
`build_id_template_pattern`）。

## Gate

```
ruby scripts/validate_*.rb（35 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing）
git diff --check                      → clean
```

## 切片 3 的 P2

本 P1 關閉後，`CLEARED_CONTRACT_LEVEL` 依裁決正式成立；runtime proof 仍
留 `SSP-295`，backlog 該列已如此標註。
