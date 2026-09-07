---
id: SCHEMA-HARDENING-REPAIR-01-20260907
status: COMPLETE_TARGETED_REREVIEW_GO_20260907
type: repair
chain_id: SCHEMA-HARDENING-PRE-ADAPTER-20260907
generation: 1
---

# Repair-01｜resolved_at RFC3339 parity

- Finding：P1 `SH-RV-001`，`resolved_at` schema pattern 誤拒合法 fractional UTC，同時 Python validator 未啟用 format assertion，可能允許 invalid calendar timestamp。
- Base checkpoint：`0b0b0dd`（parent `d7c064d`）；base immutable。
- Root cause：HARDEN-S02 以 seconds-only regex 補 UTC `Z`，但漏了 STD-00 已鎖的 0～9 位 fractional seconds；`Draft202012Validator` 未傳 `FormatChecker`，`format: date-time` 不會執行日曆合法性。
- Scope：只修 `source-anchor.schema.json` timestamp pattern、STD-02 schema AST assertion／negative fixtures、standard engine format checker／fixture metadata、repair evidence。
- Constraints：不改 UUID／authority／profile／selector／Adapter／EMEM-02；不順手修 P2／P3；不 commit／merge／push。
- Evidence：`.work/evidence/SCHEMA-HARDENING-REPAIR-01-20260907.md`。

## Red-capable public cases

1. Positive：`2026-09-04T01:00:00.123Z` 必須被 schema 與 Ruby 接受。
2. Negative：`2026-99-99T99:99:99Z` 必須被 schema 以 `format` 拒絕，Ruby 也必須拒絕。
3. Existing negative：`+08:00` 仍必須被 UTC `Z` pattern 拒絕。

## Acceptance

- Pattern 允許 0～9 位 fractional seconds，不允許空小數點，且必須以 `Z` 結尾。
- Python standard engine 對所有 validators 啟用 `FormatChecker`；現有 expected errors 如因 format assertion 增加，必須精確更新，不得降級 exact parity。
- 新正／負案例直接覆蓋原 P1；全量 STD-00～03、cross-layer、personal-memory、JSON／YAML parse、`git diff --check` PASS。
- 完成後回原 `schema_hardening_review` 只定點複審 `SH-RV-001` 與 regression。

## Closure｜2026-09-07

- First targeted re-review：`NO-GO`；Ruby `Time.iso8601` 仍接受 10 位 fractional seconds。
- Second repair：Ruby predicate 與 schema 共用 0～9 位 fractional UTC 語意，並新增 test-only regression matrix。
- Second targeted re-review：`SH-RV-001 CLOSED`；verdict `GO`；P0～P3 無 findings。
