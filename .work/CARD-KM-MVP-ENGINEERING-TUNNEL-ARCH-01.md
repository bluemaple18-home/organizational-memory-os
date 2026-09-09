# CARD-KM-MVP-ENGINEERING-TUNNEL-ARCH-01

- objective：產出完整節點矩陣，逐節點鎖定技術、I/O、owner、Agent Team 適用性、Hook／Loop 位置、deterministic gate、failure、rollback／stop 與 evidence。
- scope：唯讀核對最新 KM 討論、前版圖、organizational-memory-os 本機 authority；輸出 `.work/evidence/KM-MVP-NODE-MATRIX-20260831.md`。
- constraints：不修改視覺檔、不新增產品架構；未知項標 `UNKNOWN`；Agent Team 只在有 bounded fan-out／獨立責任時使用，Hook 不做推理與決策，Loop 不得無上限自動重試。
- acceptance：矩陣覆蓋所有 MVP 節點；每節點包含必填欄位；另列 Agent Team／Hook／Loop 全域邊界與 MVP/NEXT/NORTH STAR 分類；可被實作 Worker 直接轉成互動資料。
- status：completed；traces_to=`SC-KM-01,SC-KM-02,SC-KM-03`；evidence_ref=`.work/evidence/KM-MVP-NODE-MATRIX-20260831.md`；verification=16 節點各 14/14 欄位＋Agentic Workflow Audit 六項檢核＋`git diff --check` pass。
