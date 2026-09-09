# CARD-KM-MVP-RELATION-LAYOUT-20260901

- objective：重排 KM MVP 圖為關係優先的工程地圖；修正預設暗場、Hover 狀態與顏色語意。
- change_mode：`redesign`；surface_mode=`read`；visual_route=`relationship-first engineering map`。
- scope：只修改 thread visualization `km-mvp-engineering-tunnel.html` 的版面、線路幾何、卡片色彩語意、圖例與 Hover／Focus 狀態；保留所有節點內容與 21 條 edge。
- constraints：主線 13、修正 5、NEXT 3 不增不減；預設沒有 active／related／dimmed，所有卡片正常亮度；只有 mouseenter／focus 才啟動一跳關聯聚焦，mouseleave／focusout 立即回全圖；click/tap 只更新詳情，不釘住暗場；Escape 清除聚焦並回 N01 詳情；關鍵資訊不可只靠 Hover。
- layout_contract：主線依真實流向形成連續閱讀路徑；N15 修正站靠近 N06／N08／N09／N14 的回路區；NEXT 團隊靠近 N07／N08／N14 seam；不得為等寬整齊犧牲線路可讀性；優先減少交叉、折返與文字壓線。
- color_contract：卡片表面維持中性；色彩只編碼 `來源/證據`、`審查/治理`、`正式真相/交付`、`修正回圈`、`NEXT` 五種角色，並以文字＋線型圖例雙重說明；active 才用 accent 面；related 僅提高邊線／文字，不做第二個 active。
- acceptance：預設無 `.is-dimmed`；Hover N01/N08/N09/N14/N15 只聚焦 active＋一跳＋R01＋incident edges；離開後所有節點／21 edges 回正常；N08/N09/N14 分支線在 1024/736 不穿越卡片或標籤；320 使用窄版分支表且互動不依賴 SVG；light/dark 可讀；JS/console 無錯。
- route：`standard visual redesign → delegated worker`；status=`accepted (STATIC_ONLY)`。
- evidence：map full-width；5 欄三階段蛇形幾何；N05/N06、N10/N11 垂直鄰接，N14/N15 同列；21 edges 單一 authority；預設 markup 無 active/related/dimmed；只有 transient Hover/Focus 套 dim；角色圖例與線型圖例分離；Visualize render、JS syntax、`git diff --check` 通過。
- acceptance_note：目前無可用瀏覽器 session，未取得 1024/736/320 light/dark 截圖；因此不把 static geometry 宣稱為 runtime visual evidence。
