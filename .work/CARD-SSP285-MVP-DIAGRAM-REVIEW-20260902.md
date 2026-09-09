# CARD-SSP285-MVP-DIAGRAM-REVIEW-20260902

- objective：`KM-REVIEW-SSP285-01` 對新版 fragment 與 standalone 做唯讀獨立驗收，判斷是否真正對齊 SSP-285，不能因畫面簡潔就放過需求缺口。
- scope：讀 `CARD-SSP285-MVP-DIAGRAM-REDESIGN-20260902.md`、兩份 `km-mvp-engineering-tunnel.html` 與 Jira 票面摘錄；核對 8 節點、8 edges、驗收軌、Hover/Focus/Click 狀態、responsive geometry、繁中與 scope/non-goal trace。
- constraints：只讀，不修改任何檔案／Jira；檢查 exact ticket non-goals：外部自動同步、未經人工確認的自動升格、OCR/圖片/音訊/影片解析、完整聊天 UI/進階語意推薦/複雜多租戶權限；不得把 source assertion 當 browser evidence。
- acceptance：輸出 findings-first，僅 P0/P1 可 NO_GO；特別檢查 320px SVG/loop 是否造成 overflow、736/1024 線是否可能穿卡、standalone 是否包含最新 fragment、預設是否無 dim/active、禁止技術是否仍被當成架構內容而非 non-goal 說明。
- evidence_and_route：standard reviewer=`gpt-5.6-terra medium`；報告需附 `path:line`、severity、可重現證據與 bounded repair；若無 P0/P1，明示 GO 與 residual risks，交主線裁決。
- status：`ABORTED_USAGE_LIMIT`；Reviewer 未產出結論，不計為 review 通過；主線依靜態 finding 開 repair 卡並自行做 evidence-first acceptance。
