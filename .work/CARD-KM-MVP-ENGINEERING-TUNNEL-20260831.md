# CARD-KM-MVP-ENGINEERING-TUNNEL-20260831

- objective：交付可互動的 KM MVP 工程甬道圖，讓每個節點可檢視所需技術、I/O、責任、Agent Team、Hook／Loop、gate、failure 與 evidence。
- scope：Tenant 0「廣告投放排查」最小知識閉環；包含 MVP 主甬道、人工修正回圈，以及明確標示的 NEXT／NORTH STAR 邊界。
- constraints：禁止把 runtime-native team 誤畫成常駐 Agent Team；Hook 只做薄事件擷取；Loop 必須 bounded、可重跑、有限次數並停在人核准；deterministic gate 不得由 LLM 自評取代；不可新增第二套 runtime／registry／FSM／database／canonical writer。
- acceptance：`SC-KM-01` 每節點有可操作細節；`SC-KM-02` Agent Team／Hook／Loop 位置與邊界清楚；`SC-KM-03` MVP／NEXT／NORTH STAR 不混淆；`SC-KM-04` 320／736／1024px、light／dark、Hover／Focus／Tap 與 console 均有證據。
- status：completed／GO；`SLICE-KM-ARCH-01=completed`、`SLICE-KM-UI-02=completed`、`SLICE-KM-REPAIR-04=completed`、`SLICE-KM-REVIEW-03=re-review PASS`；frontier=none；evidence_refs：`.work/evidence/KM-MVP-NODE-MATRIX-20260831.md`、`.work/evidence/KM-MVP-ENGINEERING-TUNNEL-REVIEW-20260831.md`、`km-mvp-engineering-tunnel.html`。
