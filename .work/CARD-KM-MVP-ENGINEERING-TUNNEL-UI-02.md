# CARD-KM-MVP-ENGINEERING-TUNNEL-UI-02

- objective：依核准節點矩陣製作互動式工程甬道圖 `/Users/matt/.codex/visualizations/2026/08/31/01a056cb-048c-7332-988c-42cf06ea9751/km-mvp-engineering-tunnel.html`。
- scope：主圖常駐顯示階段、資料流、Agent／Hook／Loop 標記；Hover／Focus／Tap 顯示節點細節；保留錯誤→分類→人工修正→重測回圈及階段邊界。
- constraints：blocking_edge=`SLICE-KM-ARCH-01`；遵守 Visualize 1.0.23 fragment、theme token、accessibility、responsive；essential content 不可只靠 Hover；Visual Route=`dense interactive architecture map`，沿用 v4/v5 工程圖語言，不做卡片牆或行銷頁。
- acceptance：所有矩陣節點可操作且詳情正確；鍵盤與 touch 可取得同資訊；320／736／1024px 無裁切重疊；light／dark 可讀；console／pageerror／requestfailed 無 P0/P1。
- status：completed；evidence_refs=`km-mvp-engineering-tunnel.html`、Worker browser checks at 320/736/1024＋light/dark＋Hover/Focus/Tap＋console；traces_to=`SC-KM-01,SC-KM-02,SC-KM-03,SC-KM-04`；verification=render pass＋static policy pass＋browser user path pass；screenshot file persistence blocked by DevTools workspace-root policy。
