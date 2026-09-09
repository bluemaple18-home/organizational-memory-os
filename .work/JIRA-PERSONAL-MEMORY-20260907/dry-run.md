# Jira Dry-run｜員工個人記憶與 AI 工作紀錄

- Project：`SSP`
- 上層：`MNG-305｜知識庫建立`
- 關聯票：`SSP-285`
- 新建：2 張「任務」＋18 張「子任務」
- 歷史補登完成：`EMEM-00`、`EMEM-01` 兩張子任務建立後轉為「完成」
- 其餘：建立為「待辦事項」；Deferred／Optional 寫在摘要與 DoD，不假裝已開工
- Assignee／開始日／截止日：不填，避免替 Owner 猜派工與日期
- 附件／留言：不建立

## Tree

```text
MNG-305｜知識庫建立
├─ SSP-285｜共用知識收錄、審核、搜尋與引用閉環（既有）
├─ 新 Task｜[MVP] 建立員工個人記憶閉環
│  ├─ EMEM-00｜Scope／Ownership／Privacy（歷史補登 → Done）
│  ├─ EMEM-01｜Candidate／Record Contract（歷史補登 → Done）
│  ├─ Personal Knowledge｜L1～L4 能力等級契約
│  ├─ EMEM-02｜Personal Evidence Profile 與來源映射
│  ├─ EMEM-03｜Recall／MemoryContextPack
│  ├─ EMEM-04｜Correction／Supersession
│  ├─ EMEM-05｜PERSONAL → Shared Promotion
│  ├─ EMEM-06｜產品部 Jira＋Document Pilot
│  ├─ EMEM-07｜Role Profiles（Deferred）
│  └─ EMEM-08｜AI Core Developer Adapter（Optional）
└─ 新 Task｜[MVP] 建立 AI 工作紀錄自動化執行層
   ├─ AIWR-01｜工作紀錄與 Personal Memory 邊界
   ├─ AIWR-02｜AI 任務卡自動紀錄格式
   ├─ AIWR-03｜工作紀錄 Skill
   ├─ AIWR-04｜Hook 事件擷取
   ├─ AIWR-05｜Loop 收口與缺口補登
   ├─ AIWR-06｜輕量 Harness 編排
   ├─ AIWR-07｜Hermes 薄 Adapter
   └─ AIWR-08｜端到端驗收與主管進度視圖
```

## Frontier

可立即派工：`Personal Knowledge L1～L4`、`EMEM-03`、`EMEM-04`、`AIWR-01`。

依賴既有下一施工序：`EMEM-02` 需銜接 Document／Jira Adapter Mapping；`EMEM-06` 等 `EMEM-02～05`；`EMEM-07／08` 等 pilot 後再決策。

完整票面 User Story、驗收重點、DoD、`traces_to` 與依賴見 `jira-tasks.json`。
