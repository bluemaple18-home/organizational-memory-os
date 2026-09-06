---
id: CC-SCHEMA-FOUNDATION-REPAIR-01-20260906
status: COMPLETE_EXTERNAL_CC_GO
type: repair
base_commit: d0824e5a4dc02e8f77211ba1e790698a829e2a44
---

# CC Schema Foundation P1 Repair 01

- Objective：關閉外部 CC findings `CC-SF-001`、`CC-SF-002`，並修復共同成因 `CC-SF-003`。
- Scope：STD-01 RawEvidence schema／Ruby validator／negative fixtures／standard-engine parity gate，以及本卡 evidence。
- Constraints：`d0824e5` immutable；不改 STD-02 contract；不做 P3 backlog；不啟動 STD-03；不碰 KM／SSP／HTML／`.DS_Store`／`CLAUDE.md`；不 push／merge。
- Source evidence：外部 CC structured receipt；CodeGraph indexed HEAD `d0824e5`，定位 `validate_envelope`、RawEvidence schema conditional、`validate_raw_negatives`。

## Fact gate

- `CC-SF-001`：`native_event_id: ""` 同時繞過 schema 兩個 conditional 與 Ruby `.nil?` 判斷。
- `CC-SF-002`：`NON_I_JSON` 無 `CANONICALIZATION_UNAVAILABLE` gap 可被 schema 接受；現有 negative 因無關 JCS／I-JSON 規則被拒，屬 false coverage。
- `CC-SF-003`：Python 對 `JSON_SCHEMA` case 只斷言「有任一 schema error」；Ruby parity 只覆蓋 `RUBY_SEMANTIC`。
- Affected entry points：`scripts/validate_std_schema_engine.py`、`scripts/validate_std01_raw_evidence_contract.rb`、`規格/v0.1/raw-evidence-envelope.schema.json`、STD-01 negative fixtures。

## Verification plan

1. 將兩個最小 reproducer 固化為 negative fixtures，修前必須 RED。
2. Schema 封住 empty native id 與 NON_I_JSON gap；Ruby mirror 使用 non-empty presence semantic。
3. JSON_SCHEMA parity 必須驗證目標 invariant，不得以無關 error 過關；原 gate 全綠。
4. 重跑 standard engine、mutation probes、STD-00／01／02／cross-layer／personal-memory、parse、`git diff --check`。
5. 獨立 targeted reviewer 只驗 `CC-SF-001/002/003` 與 regression；P0／P1 為零才可 commit。

## Acceptance

- `native_event_id: "" + identity_basis: NATIVE` 同時被 Draft 2020-12 與 Ruby 拒絕。
- `NON_I_JSON + canonicalization NONE + canonical_digest null + 無 CANONICALIZATION_UNAVAILABLE gap` 被 Draft 2020-12 拒絕。
- 修復後刪除目標 schema/Ruby 規則會使 dedicated fixture fail；無關 error 不得充當 parity。
- Repair commit 以 `d0824e5` 為 parent，完整 SHA／tree／changed blobs 已驗證；獲 Owner 授權後已 push。

## Deferred backlog

- `CC-SF-004/005/006`、`source_aliases` 非空語意、cross-layer negative exact registry 另卡記錄，不攔入此 P1 repair。

## Internal targeted review

- Verdict：`GO`。
- Findings：P0／P1／P2／P3 = `0／0／0／0`。
- Closure：`CC-SF-001`、`CC-SF-002`、`CC-SF-003` 已關閉；原 gates 與兩個 fail-closed mutation probes 通過。
- External gate（已完成）：修補 commit 已 push，並已回原 CC review line 完成 targeted re-review。
- External result：CC targeted re-review 已於 repair commit `7e7f3a6c59217f7d1a1733cc01f8fb693d50598e` 裁決 `GO`；`CC-SF-001/002/003` 全數 `CLOSED`，P0／P1／P2／P3 = `0／0／0／0`。
- Mainline acceptance：binding／redaction／zero-mutation 與 fixed-archive runtime gates 複核通過；本組 findings 對 STD-03 的 blocker 已解除。
