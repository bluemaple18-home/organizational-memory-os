# STD-03 NormalizedDocument block subset v0.1 — 驗證證據

- 狀態：`LOCKED_OWNER_ACCEPTED_20260907`；獨立 review `GO` 後，Owner 已明確接受並鎖版。
- 範圍：NormalizedDocument root／block JSON Schema、PDF／Markdown／Jira 正例、單一 mutation 負例、deterministic Ruby validator 與標準 JSON Schema engine parity。

## 已確認結果

- 標準 JSON Schema engine：`STD03 JSON_SCHEMA coverage: 7/7`；`STD03 RUBY_SEMANTIC schema-allowed then excluded from schema rejection coverage: 11`。
- Ruby contracts：`STD-00`、`STD-01`、`STD-02`、`STD-03` 皆 PASS。
- 回歸與格式：personal-memory regression、JSON parse、YAML parse、`git diff --check` 皆 PASS。
- cross-layer：`uv 0.9.27` 在此 sandbox 因 macOS system-configuration dynamic store NULL object panic（exit 101）；改用同一無外部依賴腳本的 `/usr/bin/python3 scripts/validate_cc_cross_layer_contract.py` 限域 fallback 複驗，結果 `PASS`，解析 STD-01 RawEvidence／STD-02 SourceAnchor registry 並拒絕 8 個負例。

## 裁決與限制

- `CC-SF-009`：`source_aliases: []` 為合法語意；`source_identity.native_id` 仍必填且非空。裁決狀態為 `CLOSED_DECISION_ALLOW_EMPTY`，不改動 STD-01 contract。
- 本 slice 是 `PROJECTION_ONLY`；未加入 parser／adapter runtime、canonical writer、DB 或 EMEM-02。

## Independent fixed-commit review｜2026-09-07

- Binding：`cfaeec6` relative to parent `287f491`。
- Verdict：`GO`；P0／P1 = `0/0`。
- Reviewer 複驗：STD-00～03、standard engine、personal-memory、cross-layer、JSON／YAML parse、`git diff --check 287f491 cfaeec6` 全 PASS；`--probe-structural-relabel` 與 `--probe-unrelated-json-schema` 均如預期非零轉紅。
- `STD03-RV-001`（P2，非阻塞）：待新增 table `attributes={}` 與 image `attributes={}` schema negatives，並鎖定 conditional AST，確保刪除 conditional 時 gate 會轉紅。
- `STD03-RV-002`（P3，非阻塞）：STD-03 JSON Schema actual error set 與 declared set 目前僅 subset parity；與 `CC-SF-007` 同卡改為 exact／symmetric parity。
- Owner decision：2026-09-07 同意鎖定並 push；非阻塞 findings 留在 Adapter Mapping 前的 hardening card。
