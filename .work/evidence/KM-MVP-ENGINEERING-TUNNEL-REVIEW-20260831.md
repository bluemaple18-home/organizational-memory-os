<!-- 👉 [假設與目標確認] 目標：獨立審查 KM MVP 工程甬道的矩陣忠實度與互動驗收；邊界：唯讀判定、不修改視覺檔；驗收：SC-KM-01..04 與 Agentic Workflow Audit 六項皆有可追溯證據。 -->
# KM MVP 工程甬道獨立審查 receipt

- 卡號：`CARD-KM-MVP-ENGINEERING-TUNNEL-REVIEW-03`
- 類型：獨立唯讀審查／browser acceptance
- 狀態：`GO`（R01 P1 修復複審通過）
- 審查範圍：節點矩陣 `.work/evidence/KM-MVP-NODE-MATRIX-20260831.md` 與 `/Users/matt/.codex/visualizations/2026/08/31/01a056cb-048c-7332-988c-42cf06ea9751/km-mvp-engineering-tunnel.html`。
- 不包含：不修改 UI、矩陣或產品架構；不宣稱 runtime 已實作。

## 證據摘要

- 靜態資料：`data` 含 `N01–N15,R01` 共 16 筆；每筆都有 `title` 加上 technology、I/O、owner、team、hook、loop、gate、human、failure、evidence 十欄（11/11）。逐節點文案保留 `UNKNOWN`，並與矩陣的 owner、I/O、gate、failure、evidence 與 MVP/NEXT 限制一致。
- 主圖：N01–N15 均為原生 `button`，常駐呈現 ID、MVP、title、owner、D/H/A?/↺；N09/N10、N11/N12、N13→N14 的 Truth/permission 邊界未被合併。`A?` 僅在 N07/N08/N14，並在 NEXT seam 說明為條件式、未封 bounds。
- Loop／Hook：主圖僅把 `L-CORRECTION: N14/Eval FAIL → N15 → N06` 畫為 MVP 實線，明列不可覆寫 N03、每輪停 N09；H05、AT01–03、L-CLOSEOUT、L-PROJECTION-REBUILD 和 runtime-native donor seam 均標成虛線 NEXT/NORTH STAR，未偷升級。

## Browser evidence

- 方法：隔離 headless Chrome CDP；在導航前啟用 `Runtime`、`Log`、`Network`、`Page` 事件收集，再載入本機 HTML。
- 互動：Hover N14 顯示「Answer／API／Outline＋Citation／Trace」；Focus N08 顯示「Required／Actual Verification」且 active node=N08；Click 與 Tap N15 均顯示「Evaluation Failure／Correction／Revision Candidate」；Escape 後 selected 與 active node 都回 N01。
- 節點詳情：逐一 Click N01–N15，每次均顯示正確 title 與 10 個 detail 欄位。
- 版面：320px（desktop CSS viewport）`scrollWidth=320/clientWidth=320`、root width=304；736px root width=720；1024px root width=1008；三者均無水平 overflow。light/dark emulation 下均保留 15 nodes、10 detail 欄與無 overflow。
- 事件：console=[]、pageerror=[]、requestfailed=[]。headless dump DOM 亦確認 `select('N01')` 已完成初始 render，無頁面 traceback。
- 截圖限制：本次未寫 screenshot；以 CDP DOM snapshot、斷點寬度量測和 interaction assertions 取代。原 DevTools MCP 共用 profile 被既有 Chrome 鎖定，且 node_repl connector 載入 Playwright 時回報 `./index.js does not provide an export named default`；未中斷或關閉他人瀏覽器。

## 初審 SC 映射（歷史；R01 P1 已由下方 R1 複審取代）

| SC | 判定 | 證據／缺口 |
|---|---|---|
| SC-KM-01 | **FAIL (P1)** | R01 有 `data.R01` 的完整 11 欄契約，但畫面中的 `.rail` 是不可 focus/click/tap 的 `div`（`r01Interactive=false`），不在 15 個可操作 node 中；因此 R01 不能展開其完整工程 detail。這違反「所有矩陣節點可操作」與 Hover/Focus/Tap detail 要求。 |
| SC-KM-02 | PASS | 四類 badge、條件式 A?、薄 Hook、bounded loop 與 correction 回路均與矩陣一致；未發現常駐 Agent Team、direct ACCEPTED hook、無界 retry 或第二套 runtime/FSM 宣稱。 |
| SC-KM-03 | PASS | MVP 主線與 NEXT/NORTH STAR 虛線邊界可見；所有未封定 bounds 保留 UNKNOWN。 |
| SC-KM-04 | PARTIAL | N01–N15 的 Hover/Focus/Click/Tap/Escape、320/736/1024、light/dark 與 console/pageerror/requestfailed 已有 runtime 證據；R01 缺少相同互動路徑，故不可判完整 PASS。 |

## Agentic Workflow Audit

| 檢查 | 判定 | 審查依據 |
|---|---|---|
| 1 Task 邊界 | PASS（design） | 16 筆 detail 有獨立 I/O、owner、stop；UI 未合併 N09/N10 或 N11/N12。 |
| 2 I/O 契約 | PASS（design） | Evidence、Candidate、Verification、Acceptance、Write、Projection、Answer receipt 的邊界在明細中可定位。 |
| 3 可程式化成功標準 | PARTIAL | deterministic gate 已呈現；retry/fan-out/budget/model 等 UNKNOWN 仍未成 runtime validator。 |
| 4 獨立 SOP / Skill | PARTIAL | 矩陣為可定位的設計合約；無 executable SOP/fixture 證據。 |
| 5 控制流歸屬 | PASS（design） | hook 僅通知、N09 human authority、N10 single writer、N15 新 revision 回 N06 均明確。 |
| 6 失敗處理與回退 | PARTIAL | fail-closed、append-only/supersession、projection 不回寫 canonical 均明確；未封 retry cap 仍需 implementation 前補齊。 |

- 單步隔離執行：`NOT_RUN`（本次僅視覺／矩陣，無 runtime artifact）。
- 憑 trace 重建流程：`NOT_RUN`（無 end-to-end run manifest）。
- 總體：設計仍是拆解式 workflow；runtime 實作證據不足。

## R1 P1 修復複審（2026-09-01）

- 範圍：只驗原 P1「R01 無法 Hover/Focus/Tap 展開 detail」及指定 repair regression；不重開一般設計建議。
- 靜態修復：R01 現為 `<button type="button" class="rail node" data-id="R01" aria-controls="km-detail" aria-pressed="false">`；`select()` 同步所有 `.node` 的 selected class 與 `aria-pressed`。R01 保持治理軌，不改 Agent Team／Hook／Loop／phase 意義。
- Browser：在導航前啟用 Runtime、Log、Network、Page 事件；R01 Hover、Focus、Click、CDP Touch Tap 均顯示「Identity／ACL／Provenance／Chronology 治理軌」。Focus active=R01 且 `aria-pressed=true`；Click/Tap selected=R01；Escape 後 title/selected/active 均為 N01。
- Regression：N01、N15 Click 仍顯示正確 detail，N15 保有 10 個 detail 欄位。320/736/1024px 的 `scrollWidth=clientWidth`，root widths 依序為 304/720/1008；light/dark（736px）均有 16 nodes、無水平 overflow。console/pageerror/requestfailed 均為空。

| SC | R1 判定 | 證據 |
|---|---|---|
| SC-KM-01 | PASS | R01 已是可操作原生控制項，且呈現 `data.R01` 的完整 detail；N01–N15 回歸未壞。 |
| SC-KM-04（原 P1 範圍） | PASS | R01 Hover／Focus／Click／Tap／Escape 與 320/736/1024、light/dark、console/pageerror/requestfailed 都有 runtime 證據。 |

## Findings 與結論

- 原 **P1 — R01 governance rail 不可操作** 已修復並通過複審；本 review scope 結論為 **GO**。
- 既有 `UNKNOWN` 是矩陣明示的 implementation 前邊界，非本次 repair regression finding；本次不新增一般建議或移動驗收球門。

## Mainline snapshot

- root question：工程甬道是否忠實且可操作地呈現 KM MVP 合約？
- blocker：無（原 R01 interaction blocker 已排除）。
- fork：無。
- current state：`GO`。
- next step：交回主線整合。
- waiting conditions：無。
- limits：未執行或聲稱產品 runtime 的 agentic workflow。
