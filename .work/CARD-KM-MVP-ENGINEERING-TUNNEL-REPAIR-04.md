# CARD-KM-MVP-ENGINEERING-TUNNEL-REPAIR-04

- objective：修復 Review P1：讓 R01 治理軌與 N01–N15 一樣可用 Hover／Focus／Click／Tap 取得完整 detail。
- scope：只修改 `km-mvp-engineering-tunnel.html` 中 R01 的互動入口、選取狀態與必要事件綁定；不得重設版面或改變其他節點資料。
- constraints：依 `.work/evidence/KM-MVP-ENGINEERING-TUNNEL-REVIEW-20260831.md` 原 finding 修復；R01 必須使用語義 button 或等價原生控制；essential label/summary 常駐；完整詳情與矩陣一致。
- acceptance：R01 Hover／Focus／Click／Tap 顯示 R01 detail；Escape 回 N01；N01–N15 regression 不變；320／736／1024、light／dark、console/pageerror/requestfailed 通過。
- status：completed／re-review PASS；chain_id=`KM-MVP-ENGINEERING-TUNNEL-R1`；generation=`1/1`；static-contract=PASS；script-syntax=PASS；Reviewer browser regression=PASS；traces_to=`SC-KM-01,SC-KM-04`；evidence_ref=`.work/evidence/KM-MVP-ENGINEERING-TUNNEL-REVIEW-20260831.md`。
