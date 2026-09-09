# CARD-KM-MVP-RELATION-FOCUS-20260901

- objective：修正互動圖的關聯高亮；Hover／Focus／Click 時只亮目前節點、直接相連節點、對應連線與 R01 治理軌，其餘節點及連線降亮度。
- scope：修改 `km-mvp-engineering-tunnel.html` 的關係資料、SVG edge metadata 與互動狀態；沿用既有 13 主線、5 修正線、3 NEXT seam。
- constraints：直接相連僅指一跳 edge；R01 選取時可亮全部節點，因治理軌涵蓋 N01–N15；一般節點只能額外亮 R01；Hover 離開後回到最後 Click／Tap 選取；Focus/keyboard 與 Hover 同效果；不能讓 opacity 低到看不懂全圖。
- acceptance：抽驗 N01、N08、N09、N14、N15、R01 的 active node／neighbor nodes／active edges 完全符合 edge list；無關節點不使用 accent 且降亮；Escape 回 N01；320／736／1024、light／dark、console regression 通過。
- status：accepted（STATIC_ONLY）；route=`minimal → Luna medium`；traces_to=`SC-KM-01,SC-KM-04`。
- evidence：單一 `edgeList` 共 21 條（13 主線、5 修正線、3 NEXT seam）；JS syntax 通過；抽驗 N01=1、N08=4、N09=4、N14=3、N15=4 條 incident edges；Visualize render 通過；禁止樣式／完整頁殼掃描無命中。
- acceptance_note：Hover／Focus／Click 關聯集合與狀態恢復已由程式結構驗收；本回合未取得可用瀏覽器 session，因此 320／736／1024 與 light／dark 的實際互動截圖仍標記 `STATIC_ONLY`，未冒充 runtime 證據。
