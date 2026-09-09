# CARD-KM-MVP-ZH-CONNECTIONS-REPAIR-20260901

- objective：修復 320px 窄版連線語意，避免把 N14→N15 錯誤支線呈現為 MVP 正常主線。
- scope：只調整窄版流程連線／常駐標籤；桌面 13 主線＋5 修正線＋3 NEXT seam 不變。
- constraints：N01→N14 主線連續後明確結束；常駐顯示 N08 驗證失敗→N15、N14 答案錯誤→N15、N09 退回→N06/N15、N15 新修訂→N06、N07/N08/N14→NEXT seam；不得依賴 Hover 才知道支線。
- acceptance：320px 不再暗示 N14→N15 是正常主線；支線方向可讀且無重疊／溢出；736／1024、互動、中文化、console regression 不變。
- status：completed／static+render PASS／browser runtime pending；chain_id=`KM-MVP-ZH-CONNECTIONS-R1`；generation=`1/1`；traces_to=`SC-KM-03,SC-KM-04`。
