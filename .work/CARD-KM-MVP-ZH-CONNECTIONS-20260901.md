# CARD-KM-MVP-ZH-CONNECTIONS-20260901

- objective：將 `km-mvp-engineering-tunnel.html` 升級為完整連線的繁體中文版互動工程流程圖。
- scope：連接 N01→N14 全主線、N08/N14→N15→N06 修正回圈、N09 退回 seam、N07/N08/N14→下一階段代理團隊 seam；R01 以跨全程治理軌呈現；所有可見文案與 detail labels/prose 中文化。
- constraints：技術標準／產品名可保留英文括註；`UNKNOWN` 改為「待定」但不得補成承諾；主線實線、修正回圈明確區別、NEXT／NORTH STAR 虛線；連線不得穿過節點文字或造成 mobile 橫向溢出；保留 Hover／Focus／Click／Tap／Escape。
- acceptance：16 節點皆可操作；主線每一對相鄰節點都有可見有向線；所有支線與治理軌有圖例；320／736／1024px、light／dark 無重疊裁切；console/pageerror/requestfailed 為空；繁中掃描無未翻譯的一般介面文案。
- status：implementation complete／acceptance PARTIAL；13 主線＋5 修正線＋3 NEXT seam 靜態與 render PASS；窄版主線終止／分支表修復 PASS；獨立 Reviewer 因 usage limit 未執行，修後 browser runtime 因既有 Chrome profile 鎖定未重測；route=`standard → Terra medium`；traces_to=`SC-KM-01..04`。
