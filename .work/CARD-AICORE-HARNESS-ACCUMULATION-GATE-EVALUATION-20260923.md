---
id: AICORE-HARNESS-ACCUMULATION-GATE-EVALUATION-20260923
status: COMPLETED
type: GOVERNANCE_EVALUATION
priority: P1
authority: EXISTING_AI_CORE_RULES
decision: ADJUST
source_project: organizational-memory-os
date: 2026-09-23
---

# Harness / Test 累積評估：沿用既有治理

👉 [假設與目標確認]
- **目標**：完成 AI Core 既有精煉規則修訂、開發／review 引用與本卡、既有 backlog 的對齊。
- **邊界**：本輪只修改 AI Core 的 `rules/07-code-simplifier-protocol.md`、`rules/05-karpathy-coding-protocol.md`、`skills/code-review-gate/SKILL.md`，以及本卡、`文件/待辦重整.md`；不新增 gate、規則檔、skill 或 runner，不修改產品碼、測試與歷史 receipt。
- **驗收**：驗證程式的責任邊界只有一處 canonical 規則，開發與 review 入口可抵達；既有 compiled、skill surface、devflow guards 與相關測試、引用及差異檢查通過；本卡狀態只宣告已完成的治理修訂。
- **授權範圍**：承接使用者「評估現有的，不要疊床架屋」及後續完成要求；產品 harness 拆分仍是後續工作，不以本卡結案宣稱已拆分。

## 1. 原提案觀察（歷史快照）

以下保留 2026-09-23 原提案對 `product/personal-memory` 的記錄，不作為目前執行結果或拆分基線：

| 指標 | 現況 |
|---|---:|
| `test/conformance_3c.rb` | **3,563 行** |
| 其中測試／程式邏輯 | 2,766 行 |
| 註解 | 498 行 |
| 空白 | 299 行 |
| `C.check` | **358 個** |
| 大型 section | **28 個** |
| `lib/omos/` 最大產品單檔 | `schedule.rb` 655 行 |
| `lib/omos/` 19 檔總計 | 4,864 行 |

因此本次 gap **不是「產品核心 class 寫到 3,000 行」**，而是：

> 產品 capability 已分模組；驗證 harness 沒有跟著 authority seam 分模組。

目前同一支 `conformance_3c.rb` 同時承載：

- Host / Session binding
- standalone packaging
- runtime profile
- Personal Inbox
- weekly review queue
- launchd lifecycle transaction
- bounded convergence
- weekly upload accountability

Git history 顯示這不是一次性大檔，而是多輪「功能 → reviewer finding → regression → repair → regression」持續 append 的結果。2026-09-20 曾由 3,011 行整理到 2,931 行，但後續能力與 repair 繼續集中寫回同一入口，至 9/23 又成長到 3,563 行。

## 2. 原提案分析

此節是問題線索；檔案大小或持續 append 本身不足以證明既有 review 未執行，也不構成新增全域 gate 的理由。

不是測試太多；這些 regression evidence 多數應該保留。

真正的問題是 **驗證組織方式只按『同一個 conformance level』聚合，沒有再按 capability / authority seam 分層**。

典型成長模式：

```text
new capability
  → append tests to one conformance file
  → reviewer finds gap
  → append regression
  → repair
  → append mutation / replay evidence
  → next capability continues appending to same file
```

最後造成：

1. 一個概念的變更會在超長檔案裡找測試，review blast radius 變模糊。
2. 測試 helper／fixture 容易跨 capability 偷共用，形成實作耦合。
3. mutation / replay evidence 越來越難判斷是在驗哪一條 authority。
4. 大檔本身變成另一個需要維護的「系統」，違反 measured minimum。
5. 後來的人傾向繼續 append，因為入口已經存在，累積效應自我強化。

## 3. 裁決：ADJUST

沿用既有治理，修訂 `rules/07-code-simplifier-protocol.md` 的驗證程式責任邊界；開發與 review 只引用同一處。不新增 Harness / Test Accumulation Gate、規則檔、skill、runner、registry、掃描器或 CI gate。

| 原問題 | 裁決與既有承接位置 |
|---|---|
| 是否升成全域規範 | `ADJUST`：補足既有精煉規則中的具體判準與拆分驗收，納入原開發／review 流程；不建立獨立 gate。 |
| 適用面與 trigger | 沿 `rules/07-code-simplifier-protocol.md` 的「驗證程式的責任邊界」；本卡只保留本案證據，不另寫一套門檻。 |
| canonical 落點 | `rules/07-code-simplifier-protocol.md` 是唯一條文來源；`rules/05-karpathy-coding-protocol.md` 與 `skills/code-review-gate/SKILL.md` 只作按需引用。 |
| warning 或 hard gate | 沿同一條文與既有 review／驗收分級；不新增自動 warning、LOC hard fail 或 CI gate。 |
| 既有大型 harness | `conformance_3c.rb` 另作 bounded refactor；本卡第 5 節保存本案驗收，既有 backlog 只引用，不重開另一套治理分類。 |

上述路徑皆相對於 AI Core 根目錄；以專案 `CLAUDE.md` 的共用入口與按需載入地圖解析。`skills/evidence-first-acceptance/SKILL.md` 承接證據驗收，`skills/minimal-change-gate/references/code-retirement.md` 承接取代與退場。`dynamic-harness-gate` 是編排形狀判斷，`test-skill` 是 skill 生成管線測試，本案不擴充兩者。

### 專案入口取代

- **本次取代**：`CLAUDE.md` 對 `.agentskills/docs/coding-standards.md`、`system-mindset.md` 與 `.agentskills/skills/` 的強制入口，改為 AI Core 共用入口與按需載入。另移除強制另建 `implementation_plan.md` 的同義要求，沿用原卡／plan。
- **舊版處置**：移除本專案的 active 引用；共用 `.agentskills` 原檔供其他使用端保留，不刪檔、不修改內容。歷史卡／receipt 不重寫，其舊引用不構成當前通用治理入口。
- **理由**：舊行數表描述 UI 元件、表單與頁面，歷史規範債卻將其套為 validator 的 `<400` 判準；舊思維文件另要求 CCB／Buddy、固定 plan／task 檔與流程固化。沿用現有 AI Core 路由、按需記憶與原卡驗收，避免雙重入口。
- **回退**：僅還原本輪三份文件的改前內容；已保留工作副本，不以整庫 reset 覆蓋在途產品修改。

## 4. 既有先例與證據

- [既有 validator 重構卡](CARD-REFACTOR-VALIDATOR-STRUCTURE-20260909.md) 已使用薄 refactor plan。
- [Repair 01 複審 receipt](evidence/REFACTOR-VALIDATOR-STRUCTURE-REREVIEW-01-20260909.yaml) 記錄 F-01：拆分縮窄舊命令 coverage，即使成功輸出逐字相同仍會假綠。修復 `d4934a5` 保留舊命令，透過舊命令驗證五個 slice 的 mutation parity；歷史 receipt 的 `GO` 與 `owner_accept: PENDING` 依原文保留，不互相代替。
- [目前 aggregator](../scripts/validate_personal_memory_contract.rb) 已串接 15 個 validator，可直接參考其單一入口責任；本案只沿用 parity 驗收方法，不把 subprocess runner 搬進 conformance。
- 本輪觀察基底為 `c1a85b9c3582eedfdf910d0ea3be36ae05bf0f46`，產品有在途修改。文件修改前 `conformance_3c.rb` 為 3,762 行、370 處 `C.check` 靜態呼叫；這不是實際執行數，也不是後續固定驗收門檻。

## 5. 後續 bounded refactor：PLANNED

由知識庫既有主線在產品在途變更收斂、可鎖定基線時承接；不以本卡結案宣稱產品拆分完成。待辦沿用[規範債 backlog](../文件/待辦重整.md)，不新增分類或重開已完成的 validator 重構。

通用判準、證據保留及退場沿第 3 節的 canonical 引用；以下只保留產品特有的範圍與驗收。

1. **範圍與基線**：只拆 `product/personal-memory/test/conformance_3c.rb` 與必要測試模組；鎖定包含在途 `review_ledger.rb`、`review_queue.rb` 與 conformance 成果的實際基線。`lib/`、規格、evaluator、fixtures 的語意不變。
2. **既有介面**：沿用 `Support::Checks`、原 reporter 與原命令；特別保留共用 `group`、結果收集、單次 `report!` 與既有執行順序，不順手改成平行 runner。
3. **驗證範圍**：原 3a／3b／3c 命令與其既有 regression／mutation／replay 都納入等價驗收；引用第 4 節 F-01 先例核對原入口的 failure detection，產品拆分可以獨立回退。

## 6. 專案入口整併驗證（前一階段）

**治理文件完成；產品工作區不變性為 PARTIAL。** 本輪不重跑歷史 mutation，也不宣稱產品 conformance 已重新驗收。

| 已執行檢查 | 結果 |
|---|---|
| 文件契約斷言 | 10/10 PASS：舊強制入口移除、可攜根目錄解析、三個入口引用、ADJUST 裁決、舊待採納提案移除、四個本地來源連結、五個 AI Core 治理來源、拆分後續邊界、唯一 backlog 引用、案例與 mutation 驗收。 |
| `git diff --check -- CLAUDE.md 文件/待辦重整.md` | PASS。 |
| 原卡尚未追蹤的 whitespace 檢查 | `git diff --no-index --check /dev/null .work/CARD-AICORE-HARNESS-ACCUMULATION-GATE-EVALUATION-20260923.md` 通過。 |
| 共用來源與歷史證據 SHA-256 | 9/9 相同：相關 AI Core 規則／入口／退場契約、兩份舊共用規範、歷史重構卡與複審 receipt。 |
| 45 個產品檔案 SHA-256 | 42/45 相同；`review_ledger.rb`、`review_queue.rb`、`conformance_3c.rb` 在本輪觀測期間改變，均為原先已在途的檔案。不以新基線覆蓋原結果，不宣稱整個 worktree 未變。 |
| 本輪修改範圍 | Native apply_patch 寫入目標僅本卡、`CLAUDE.md`、`文件/待辦重整.md`。另出現的產品介紹卡與 artifacts 未納入本輪修改。 |

以上是前一階段的觀測紀錄：產品變化維持原貌，未回退、重構或覆寫；全域規則／skill／runner／CI gate 新增數為零，未 stage、commit、push、merge 或部署。當時的 `COMPLETED` 僅指治理評估與專案文件整併；最新規則修訂及驗證以第 7 節為準，產品拆分仍為第 5 節的 `PLANNED`。

## 7. 既有規則修訂（2026-09-23）

- **Owner 指示**：「所以規則都沒改 還是怎樣 做完啊」。本輪執行既有規則修訂與必要引用，沿用前述不新增 gate 的邊界。
- **修改範圍**：本卡目標／邊界列明的五份文件；`CLAUDE.md`、compiled 入口、context map、skill registry 與歷史 receipt 須維持原內容。
- **實際修改**：`rules/07` 補上累積判斷與拆分證據保留；`rules/05` 接上引用，並把「重構前後 100% 綠燈」修正為行為等價驗收；review skill 只加同一來源的引用。本卡第 5 節移除上提條文的重述，只留產品特例，backlog 仍維持原分類與唯一待辦。
- **狀態**：`COMPLETED / ADJUST`；既有規則修訂與本機驗證完成。產品拆分仍為第 5 節的 `PLANNED`，本輪未執行產品 conformance／mutation／replay。
- **回退**：只還原本輪五份文件的差異；改前工作副本位於本機暫存 `aicore-harness-rule-refinement-7fy836uh`，不以整庫 reset 或舊 snapshot 覆蓋其他在途成果。

以下命令從 AI Core repo root 執行；使用既有 `.venv`，未安裝依賴或新增測試框架。

| 已執行驗證 | 實際結果 |
|---|---|
| `.venv/bin/python -B -m unittest tests.test_generate_compiled_rules tests.test_rules_bloat_audit tests.test_skill_surface_guard` | 39 tests，OK。 |
| `.venv/bin/python -B scripts/generate_compiled_rules.py --profile lite --check`；同命令 `--profile full --check` | 兩個 compiled 檔皆 matches canonical sources；沒有重寫或加長 bootstrap。 |
| `.venv/bin/python -B scripts/rules_bloat_audit.py` | PASS。 |
| `.venv/bin/python -B scripts/skill_surface_guard.py` | PASS。 |
| `bash scripts/devflow_context_map_guard.sh` | PASS=3，FAIL=0。 |
| 本案引用與來源核對 | 9/9 PASS：implementation／code_review 路由各可抵達唯一條文、標題唯一、實際 Codex review skill 連至本機新來源、7 份受保護來源不變、舊邊界文案移除、產品驗收改用引用、backlog 唯一待辦、Markdown 連結可解析。檢查結果存本機暫存 `aicore-harness-rule-refinement-7fy836uh/rule-link-checks.json`。 |
| 本輪產品觀測 | `review_ledger.rb`、`review_queue.rb`、`conformance_3c.rb` 的 SHA-256 均與本輪改前觀測相同；不覆寫前一階段曾觀測到變動的紀錄。 |

一次批次驗證呼叫被工具安全檢查阻擋，未算作執行；後續已逐項執行上述命令並取得實際通過結果。這些結果證明規則來源、引用與既有治理工具的契約檢查通過，不表示已執行後續產品拆分。未 stage、commit、push、merge、全域 sync 或部署。
