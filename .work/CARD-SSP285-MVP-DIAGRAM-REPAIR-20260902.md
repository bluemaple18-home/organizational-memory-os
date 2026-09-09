# CARD-SSP285-MVP-DIAGRAM-REPAIR-20260902

- objective：`KM-REPAIR-SSP285-01` 修正新版 SSP-285 圖的兩個驗收缺口；traces_to=`SC-001..SC-004`。
- scope：只修改 fragment，並以 Visualize render.py 重產同名 standalone；修正 M08→M04 loop 幾何與票面 non-goal 可見文字。
- constraints：不得改節點、edge 數或 Jira；不得引入新功能／框架；保持預設全亮與 Hover/Focus 一跳關聯；Browser URL policy 已阻擋 file URL，不可用其他瀏覽器、CDP、localhost 或任何 workaround 繞過。
- acceptance：所有 viewport 尤其 <=430 的 loop path/label/marker 不可超出 SVG viewBox／主容器，不依賴 `overflow:visible` 畫到 width+N；「不做」可見文字精確涵蓋 4 組：外部服務自動同步、未經人工確認的自動知識升格、OCR／圖片／音訊／影片解析、完整聊天 UI／進階語意推薦／複雜多租戶權限；8 nodes/8 edges 不變；fragment/standalone term assertions、JS syntax、render、git diff --check 通過。
- evidence_and_route：bounded repair=`gpt-5.6-terra medium`；回報具體幾何策略與 assertions；browser evidence 仍標 `BLOCKED_BY_POLICY`，不可冒充通過。
- status：`ACCEPTED_STATIC`；回圈改走 viewBox 內側安全軌且 SVG `overflow:hidden`；4 組 non-goals 可見；8 nodes／8 edges、JS syntax、render、standalone freshness、git diff check 通過；browser runtime 仍 `BLOCKED_BY_POLICY`。
