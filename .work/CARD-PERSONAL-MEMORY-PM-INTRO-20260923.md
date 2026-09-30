# 個人知識庫 PM 介紹與使用說明

- objective：交付 PM 可閱讀、可播放的產品介紹，含架構圖、日常與每週流程，以及可操作的使用手冊。
- scope：目前依 Owner 已核准的新八頁大綱，改走 PPTSKILL 原生單檔 HTML 工作流；本輪依已核准大綱與 Owner 選定的 D｜工作節奏，產製八頁 PPTSKILL 原生單檔 HTML。先前 PPTX／PDF 等檔保留為舊草稿。
- constraints：以 `product/personal-memory` 的目前實作及 2026-09-17 Owner 裁決為來源。公司級 Knowledge OS 只作邊界說明。使用合成資料驗證，不安裝 Host、不啟用提醒、不讀取個人 Store。
- baseline：main / c1a85b9；開始時 review_ledger.rb、review_queue.rb、conformance_3c.rb 已有工作中修改，保留原狀。未提交修復不能代表已交付版本。
- acceptance：涵蓋產品價值、架構、日常匯入、每週回顧、操作範例、功能邊界；可編輯文字／圖形；8 頁逐頁視覺檢查；手冊指令用隔離 Store 實測；來源與驗證可追溯。
- decision：本輪依安裝的 PPTSKILL 使用 grill-outline、Company Style Pack、style-candidates 及原生規格；全稿由 workflow-cli.mjs render-new 產生。Owner 已核准大綱並明確選 D｜工作節奏。
- status：LAYOUT_MAPPING_REPAIRED / STATIC_QA_PASS / VISUAL_QA_BLOCKED；已修正七張內容頁的 CompositionSpec variant，重新輸出八頁 HTML；內容與封面保留檢查通過。瀏覽器本機檔案 URL 被安全政策封鎖，逐頁視覺與互動驗收未完成。
- evidence refs：`.work/artifacts/personal-memory-pm-20260923/`。

## 交付

以下是先前草稿的交付與驗證記錄，不代表新八頁 PPTSKILL 全稿已完成。

`文件/產品介紹/個人知識庫-PM-20260923/`：8 張原生可編輯 PPTX、PDF 閱讀版、離線 HTML、3 張 SVG、Markdown／HTML 使用手冊與完整 ZIP。

## 驗證

PPTX 結構、版面、字型宣告與重新匯入檢查通過；8 頁逐頁視覺檢查完成。PDF 8 頁經 PDFium 渲染，與已檢視的原圖像素一致。核心 CLI 流程使用隔離 Store、虛構紀錄、模擬時間及測試起點收據，11 項通過。

HTML 僅完成靜態連結與腳本語法檢查；瀏覽器 URL 政策拒絕本機預覽，未繞過限制。未在 PowerPoint 應用程式開啟，也未代使用者安裝 Host、啟用排程或發送資料。

## 2026-09-24｜PPTSKILL 重製

Owner 已完成訪談與八頁大綱確認；受眾為使用 Claude Code／Codex 的 PM 與 UIUX PM，約二十分鐘。價值排序 B→A→C。PM、UIUX 與工程整合為同一條產線；資料可信度與經驗再利用分工。

本輪 evidence：`.work/artifacts/personal-memory-pptskill-20260924/`。候選輸出：`文件/產品介紹/個人知識庫-PPTSKILL-20260924/`。本輪不更新 PPTSKILL 共用 runtime、不改產品程式、不安裝 Host、不啟用排程。

四款均由安裝的 `core/runtime/style-candidates.js#buildStyleCoverPreview` 直接產生；A 載入既有 Clickforce Dark Company Style Pack，B／C／D 分別使用 minimal-institutional、typography-hero、graphic-brand-field 原生構圖。已完成同文案與構圖差異檢查。先前 `style-selection.json` 維持 pending；Owner 後續在原任務明確回答 `D`，已據此更新選款並產生全稿。

## 2026-09-24｜D 款八頁全稿

- 交付：`文件/產品介紹/個人知識庫-PPTSKILL-20260924/deck.html`；DeckSpec 與選款紀錄位於 `.work/artifacts/personal-memory-pptskill-20260924/`。
- 產製：既有 `grill.json`、已核准 `outline.json`、Owner 原話 `D` 對應 `memory-rhythm` StyleSpec，使用 PPTSKILL `workflow-cli.mjs render-new`；gate 回報 `pass`。
- 靜態驗收：八頁 ID 與順序一致，標題／副標／重點逐欄與大綱一致；內嵌 DeckSpec 與 D Style 正確；沒有外部資源引用或本機絕對路徑。HTML SHA-256：`6ff58d5c8f7e77a9ce95b47108a6cd845407dd21d4c721ce13bcf8406ea7c471`。
- 限制：受管瀏覽器拒絕開啟本機 `file:` 簡報 URL，明示不可改用間接路徑或其他瀏覽器繞過；因此未完成八頁逐頁視覺與互動驗收。D 色彩與 StyleSpec 已用，正式全稿的封面構圖是否與選款預覽相符尚未經瀏覽器確認。
