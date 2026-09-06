---
id: CC-SCHEMA-FOUNDATION-PREP-20260904
status: COMPLETE_GO_READY_FOR_EXTERNAL_CC_REVIEW
type: implementation
---

# CC Schema Foundation 大 Review 前置強化

- Objective：把已完成的 EMEM-00／01、STD-00／01／02 整理成可由外部 CC 對固定 commit 做 blocking review 的完整 substrate。
- Owner decision：Owner 於 2026-09-04 提供整合建議並指示繼續；接受 `STD-02` 完成 DoD 後鎖版，核准本卡範圍。
- Scope：鎖版 DoD 定義、JSON Schema authority decision、標準 2020-12 engine acceptance gate、跨層合併 fixture／validator、current backlog status一致性、spec claim→enforcement matrix、review handoff素材。
- Constraints：Canonical Direct-Write Audit 另線 pending；不做 STD-03、Connector、DB、runtime、Hook、Loop、Harness、Hermes；不讓外部 reviewer寫 working tree；不 push／deploy。
- Acceptance：STD-00／01／02 各自具 versioned spec＋validator＋positive/required-negative fixtures＋evidence＋一致狀態；JSON Schema standard engine實際驗 schema/fixtures；Candidate→SupportLink→RawEvidence→SourceAnchor可真實 resolve並檢查 ACL／owner／digest；狀態 token不混底線／連字號；enforcement matrix可追到 exact file/gate；所有 validators、parse、`git diff --check`通過；獨立 review無 P0／P1。
- Evidence：`.work/evidence/CC-SCHEMA-FOUNDATION-PREP-20260904.md`。

## Architecture decision

1. JSON Schema Draft 2020-12 是 STD-01／02 field-level normative authority。
2. Ruby deterministic validators只補 JSON Schema無法表達或不適合單筆表達的跨事件／跨資源 invariants，並驗 fixture isolation。
3. 標準 engine gate失敗即 NO-GO；不得只以 Ruby PASS 宣稱 schema LOCKED。
4. Review snapshot必須 immutable：checkpoint commit SHA＋allowlisted paths＋commit blob OID／SHA-256＋enforcement matrix。

## Cross-layer minimum

- Positive：PersonalMemoryCandidate → MemorySupportLink → SourceAnchor → RawEvidenceEnvelope；refs、employee/tenant、ACL snapshot、visibility、source version、representation digest一致。
- Negative：missing/wrong ref、digest mismatch、source access revoked仍 exact、ACL/owner/scope widening、summary-only support；每例完整 base單一 mutation。

## Handoff boundary

- 外部 CC：read-only fixed commit，只回結構化 findings／receipt。
- Mainline：驗 binding、schema、redaction、zero mutation後寫回 repo。
- `Canonical Direct-Write Audit`：pending，不列本次 review。

## Review-01 Findings

1. P1：standard engine只要求任一 negative被拒，缺 per-case authority／expected rejection mapping。
2. P1：cross-layer fixture內嵌 SourceAnchor自證，未由 STD-02 fixture registry真實 resolve。
3. P1：JSON Schema normative與 Ruby field-level assertions責任敘述衝突。
4. P1：canonical current backlog仍含已解除的 STD-00／01 blocker。
5. P2：cross-layer command直接使用 `python3`；改為可重現 `uv` entry。

## Review-02／03 closure

- Repair-02：`RUBY_SEMANTIC` 必須先由 Draft 2020-12 實際 ALLOW；結構性 case 重標後仍會 fail-closed。
- Repair-03：canonical backlog 已同步 STD-01／02 鎖版與 STD-03 未施工；裁決只保留「每一個 JSON_SCHEMA case」閘門。
- Fixed checkpoint／allowlist／blob digest 綁定與內部 blocking review 已完成。

## Fixed checkpoint acceptance

- Review commit：`d0824e5a4dc02e8f77211ba1e790698a829e2a44`
- Tree：`4d6c9635b13b22a6c3670dc59223de0c0be6f30f`
- 內部獨立 blocking review：`GO`；P0／P1／P2 = `0／0／0`。
- 此 GO 只證明 CC 交件 substrate 已完成；不冒充外部 CC 已審。
- 下一關：外部 CC 對上述 fixed commit 做 read-only 大 review；通過前不啟動 STD-03。
