---
id: DOC-ADAPTER-DETERMINISM-SPEC-FREEZE-20260910
status: OWNER_SIGNED
type: spec-decision
lane: A（repo 施工順序 #2 / EMEM-02 前置）
tier: T2
blocks: DOC-ADAPTER-MAPPING-20260909
review_line: DOC-ADAPTER-MAPPING（凍結於 `cc/doc-adapter-mapping` @ `e7505f8`）
trigger: hard stop —— 同一 blocker（F-03 determinism）連續 6 次 NO_GO
---

# Document Adapter Mapping｜determinism 語意凍結（T2）

👉 [假設與目標確認]
- 目標：把「document adapter 的 deterministic projection 到底宣稱什麼」一次凍成 Owner 決策，
  讓後續實作只需照簽好的做，big-review 只驗「有沒有照簽」。
- 邊界：只凍 determinism 語意。不動 STD-01/02/03（皆 `LOCKED_OWNER_ACCEPTED`）；不重開
  已 CLOSED 的 F-01 / F-02 / P2；不動 repo #3（已 merge）。
- 驗收：Owner 在 FP-1…FP-5 各簽一個選項 → CC 依簽定實作一張 T1 收尾卡 → 針對性 review 只
  驗照簽與否。

## 為什麼停在這裡

`DOC-ADAPTER-MAPPING` 這條 review line 的 finding 歷程：

| 輪次 | commit | verdict |
|---|---|---|
| big-review | `c2e184f` | NO_GO 3×P1（F-01 / F-02 / F-03） |
| repair-01 | `faddb8c` | NO_GO P1=2, P2=1（F-01 CLOSED） |
| repair-02 | `d2ee1d2` | NO_GO P1=2（P2 CLOSED） |
| repair-03 | `df6b2ff` | NO_GO P1=1（F-02 CLOSED） |
| repair-04 | `f2333e1` | NO_GO P1=1（F-03-R03） |
| repair-05 | `9ef254f` | NO_GO P1=1（F-03-R04 → paired drift 已封） |
| repair-06 | `e7505f8` | NO_GO P1=1, P2=1（F-03-R05 → block content drift 已封） |

**F-01 / F-02 / P2 從 repair-03 起就穩定 CLOSED，churn 100% 集中在 F-03（determinism）。**
CC 的操作規則是「同一 blocker 第 3 次失敗即停回 Owner」；此處已第 6 次，repair-06 卡自帶
hard stop，故轉本卡。

## 根因（不是 reviewer 挑剔，是契約缺一個總分類）

目前 `deterministic_derivation` 同時維護**三份互相重疊、但彼此不一致**的排除／綁定清單：

| 清單 | 涵蓋 | 用途 |
|---|---|---|
| `run_scoped_paths` | raw_evidence + source_anchor 的 per-run 路徑 | reconstruction 比對前先剝除 |
| `block_run_scoped_keys` | block 的 per-run key（`block_id` / `parent_id` / `source_anchor_refs` / `quality`） | deterministic block surface 前先剝除 |
| `excluded_from_canonical_digest` | 只有 raw_evidence 的 wall-clock/receipt + source_anchor 的 resolution | `projection_digest` 計算前剝除 |

**沒有任何一份是對整個 projection 的總分類，而且第三份完全沒涵蓋 block 的 run-scoped key。**
每一輪 review 找到的都是「掉進兩份清單之間縫隙」的欄位 —— repair-04 是 `normalized_digest` /
`source_instance_id`，repair-05 是整個 `blocks` slice，repair-06 是 `projection_digest` 與
`block_run_scoped_keys` 互相矛盾。只要不建立單一總分類，這個迴圈就會繼續。

## 本輪 reviewer 的 P1（已本地重現，非推論）

保持 7 個 `determinism.inputs` 完全不動，只改
`block_instances[0].quality.extraction_confidence`（`0.98` → `0.50`，schema-valid，且
repair-06 自己定義 `quality` 為 run-scoped）：

```
deterministic_surface_mismatches  A: []   B: []          （兩份都 PASS）
normalized_document_digest        A == B: true
projection_digest                 A != B                （14c7dcd4… vs 75350038…）
```

而 YAML 仍把 `projection_digest` 列在 `derived`，並宣稱
「same seven declared inputs necessarily share the same deterministic projection」。
**契約自我矛盾** —— 這是 F-03 的 closure 缺口，不是新 scope。

## Owner 簽定（2026-09-10）

Owner 於互動對話中明示「就照你建議」，五個凍結點全部採 CC 建議選項：

| 凍結點 | 簽定 |
|---|---|
| FP-1 determinism 宣稱範圍 | **A —— 只宣稱 evidence identity**；不宣稱整份 emitted projection 逐位元相同 |
| FP-2 `projection_digest` 語意 | **A —— 更名 `deterministic_projection_digest`**，只 hash reconstruction/deterministic surface，留在 `derived` |
| FP-3 單一總分類 | **簽定** —— 契約只保留一份窮盡的 `classify(path) → DETERMINISTIC \| RUN_SCOPED`；reconstruction／digest／excluded 全部由它推導，不得另立清單；未分類路徑 fail-closed |
| FP-4 block `parent_id` / `source_anchor_refs` | **A —— run-scoped**；結構由 `level` / `order` 承載 |
| FP-5 `quality` | **A —— run-scoped** 抽取量測，不參與 identity 與任何宣稱為 deterministic 的 digest |

後續：`.work/CARD-DOC-ADAPTER-DETERMINISM-CLOSEOUT-20260910.md`（T1）依此實作，
`cc/doc-adapter-mapping` 於 `e7505f8` 之後接新 commit。

### FP-3 施行細則（2026-09-10，實作時補記）

FP-3 的「單一總分類」在實作上逐**子欄位**分類 `source_anchor/profile_details`，而不是把整個
subtree 列為 run-scoped：

- run-scoped 子欄位（anchor 位置與 per-run ref）：`page`、`page_number_basis`、`bbox`、
  `block_id`、`char_range`、`char_representation_ref`、`codepoint_range`、`line_range`、
  `line_number_basis`、`heading_path`、`selected_text`。
- 因此 `char_representation_digest` **依同一條規則**即為 DETERMINISTIC（綁
  `inputs.normalized_representation_digest`），**不需要任何特例**。

這是 FP-3 的施行方式，不是新的凍結點：FP-3 簽定的就是「只有一份分類 authority」，先前
implementation 對這個 digest 開了硬編特例，等於第二份 authority，與簽定牴觸，故收斂。
validator 另斷言 locked profile schema 的每個 `profile_details` 必填欄位都必須被此分類涵蓋
（run-scoped 或明列 deterministic），未涵蓋即 fail-closed。

## 需要 Owner 簽的凍結點（原提案，保留供追溯）

### FP-1 — determinism 宣稱的範圍

| 選項 | 內容 |
|---|---|
| **A（CC 建議）** | 只宣稱 **evidence identity**：相同 inputs → 相同的 RawEvidence/SourceAnchor identity slice + deterministic block surface。**不**宣稱整份 emitted projection 逐位元相同。 |
| B | 宣稱整份 emitted projection 逐位元相同 —— 則所有 per-run 欄位（evidence_id / anchor_id / block_id / source_anchor_refs / quality / chronology …）都必須成為 declared input 或改成由 input 決定的確定值。 |

> CC 建議 A：mapping 契約的職責是「同一份文件內容 → 同一個 evidence identity」；emitted
> projection 依設計就帶 per-run ref。宣稱 B 是 overreach，正是這 6 輪的成因。B 也會把
> `block_id`（STD-03 鎖為 UUIDv7 urn）逼成 input，等於推翻 STD-03。

### FP-2 — `projection_digest` 的語意（依 FP-1 決定）

| 選項 | 內容 |
|---|---|
| **A（CC 建議，搭 FP-1=A）** | 更名 `deterministic_projection_digest` = SHA256(reconstruction surface)。真正是 `f(inputs)`，留在 `derived`。run-scoped 欄位永遠不影響它。 |
| B | 保留 full-projection digest，但**移出 `derived`**、明確標為 run-scoped/audit 用途，契約不再宣稱 same-inputs→same-digest。 |
| C | 兩個 digest 並存（identity 一個、emitted 一個）。 |

> CC 建議 A。C 目前沒有 measured need（audit/replay 尚無需求方），依 `NO_FUTUREWARE` 不預先加。

### FP-3 — 單一總分類（結構性，建議直接簽）

凍結：契約只保留**一份**權威分類
`classify(projection_path) → DETERMINISTIC | RUN_SCOPED`，對
`{raw_evidence, source_anchor, blocks}` **窮盡**；`reconstruction`、`projection_digest`、
`excluded_from_canonical_digest` 全部由它推導，不得另立清單。未被分類的路徑一律 fail-closed。

> 這條是止血點：有總分類後，「掉進清單縫隙」的 finding 由構造上不可能發生。

### FP-4 — block 樹狀連結（`parent_id` / `source_anchor_refs`）

| 選項 | 內容 |
|---|---|
| **A（CC 建議）** | run-scoped（per-run UUID 連結）；文件結構由 `level` / `order` 承載於 deterministic surface。 |
| B | 視為 deterministic identity 的一部分 → 需要一個穩定（非 UUID）的正規化父子表示 → 這會動到 STD-03，須另開卡。 |

### FP-5 — `quality`（`extraction_confidence` / `warnings`）

| 選項 | 內容 |
|---|---|
| **A（CC 建議）** | run-scoped 抽取量測；不參與 identity，也不參與任何契約宣稱為 deterministic 的 digest。 |
| B | 納入 deterministic surface → 需宣告決定它的 input（parser 版本 + 模型版本 …）。 |

## 簽定後 CC 會做什麼（一張 T1 收尾卡，不再迴圈）

1. 依 FP-3 建立單一 `classify()`，把三份清單收斂成一份窮盡分類。
2. 依 FP-1 / FP-2 調整 `deterministic_derivation` 的宣稱與 `projection_digest` 語意／命名。
3. 依 FP-4 / FP-5 落定 block 欄位歸屬。
4. 補負例：run-scoped 欄位變動 → 契約宣稱為 deterministic 的 digest **不得**改變；
   deterministic 欄位變動 → 必須 RED。
5. 修 carry-over P2（見下）。

## Carry-over 缺陷（CC 自承，簽定後一併修）

`DOC_MAP_NEG_DERIVATION_PAIRED_BLOCK_CONTENT_DRIFT` 的 `content_sha256` 是我**編造**的
hex，不是實算值：

```
content        = "Authorization boundary"
fixture 寫的   = sha256:0e2b0a4bd8c8f5c9d3a1f6e7b2c4d5a6e7f8091a2b3c4d5e6f70819a2b3c4d5e6   ← 捏造
實際 SHA256    = sha256:6553c60633584d85f96a7063a340735c017dd6cc9de33f1b1e296d3d46ba43b4
```

因此該負例同時被 `content_sha256` 不一致擋下，沒有隔離出「純 paired block drift」。
非阻塞，但屬事實錯誤，收尾卡一併校正。

## 不得重開

- **F-01**（profile_details 重定義 STD）— CLOSED @ repair-01
- **F-02**（mapping ↔ schema-valid fixture 脫鉤）— CLOSED @ repair-03
- **P2**（instance-negative dead contract）— CLOSED @ repair-02
- **F-03-R04 paired drift**（`normalized_digest` / `source_instance_id`）— CLOSED @ repair-05
- **F-03-R05 block content paired drift** — CLOSED @ repair-06

## 現況

- 本卡已簽定；`cc/doc-adapter-mapping` 於 `e7505f8` 之後接 `9dbae75`（T1 收尾實作）與
  `230bcf0`（FP-3 施行細則收斂），本卡副本隨後續 docs commit 進入同一條 review line 的
  frozen tree，供 reviewer 直接核對 authority。
- frozen chain：`c2e184f → faddb8c → d2ee1d2 → df6b2ff → f2333e1 → 9ef254f → e7505f8`（全部 immutable）。
- 下游：`SSP-291`（EMEM-02）、`SSP302-CONTRACT-TIGHTEN` 仍等 repo #2 merge。
- repo #3 Jira Adapter Mapping 已 `ACCEPTED_GO` / merged（`0ac8c09`），不受本卡影響。
