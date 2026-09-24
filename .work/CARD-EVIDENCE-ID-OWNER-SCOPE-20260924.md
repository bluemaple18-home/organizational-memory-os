---
id: EVIDENCE-ID-OWNER-SCOPE-20260924
jira: 尚無對應 ticket，需補開一張並回填此欄
status: BACKLOG_NEEDS_OWNER_DECISION
tier: T3
parent: SSP295-FULL-PRODUCT-PILOT-20260921
blocks:
  - 公司端「每個人這禮拜上傳了什麼」的匯總
---

# Candidate／Evidence 的識別碼不含 owner，跨人會碰撞

## 實測

2026-09-24 pilot 回報比對時發現：Wen 的 evidence／candidate 編號與交付方
沙箱測試時**逐字相同**。控制條件後重現：

```text
同一份內容，兩個不同的 owner：
  wen    → candidate:c8423fd7-59ee-7fe8-81e8-b5912beeb986
  lettie → candidate:c8423fd7-59ee-7fe8-81e8-b5912beeb986   ← 同一個
```

`lib/omos/inbox.rb:119-120`：

```ruby
link_id      = EvidenceSnapshot.link_ref(digest)
candidate_id = EvidenceSnapshot.candidate_ref(digest)
```

兩者都**只由 content digest 推導**，`employee_owner_ref` 沒有參與。
`idempotency_key` 同樣是 `"inbox-candidate-#{digest}"`，也不含 owner。

物件本身**有**記 owner（envelope 的 `employee_owner_ref` 兩人不同），
碰撞的只有 identity。

## 今天的影響：零

- 每個人的 store 只在自己機器上，不互相看見。
- 週期 receipt 是 content-free 的，**不帶任何 candidate／evidence ref**。
- 單一 store 內部，「同內容同 id」正是想要的冪等行為——Wen 第二次匯入
  得到「重放，未新增任何一列」，那是對的。

## 之後會踩到的地方

Owner 的管理需求是「每個人這禮拜上傳了什麼」。一旦公司端開始收 candidate
ref，**兩個人上傳同一份公司文件會變成同一筆**——而這正是最可能發生的情況
（共用的規格、會議記錄、公司公告）。

## 需要 Owner 裁決的問題

識別碼的 scope 應該是什麼？

- **(a) 維持 content-scoped。** 公司端匯總時一律以
  `(employee_owner_ref, candidate_ref)` 複合鍵處理，不得單獨用 candidate_ref。
  好處：不動既有資料與契約；代價：這條規則必須寫進契約並被 evaluator 擋住，
  否則下游任何一個地方忘了帶 owner 就會靜默合併兩個人的東西。
- **(b) 改成 owner-scoped。** `candidate_ref` 的推導加入 `employee_owner_ref`。
  好處：碰撞在源頭消失；代價：既有 store 裡的 id 全部改變，要處理既有
  pilot 使用者的資料；且需確認 `personal_memory_resource_contracts` 的
  `id_templates` 允許。
- **(c) 兩層。** evidence（內容）維持 content-scoped，candidate（個人的處置
  對象）改成 owner-scoped。語意上最貼切：同一份內容是同一份證據，但
  「Wen 要怎麼處置它」與「Lettie 要怎麼處置它」本來就是兩件事。

交付方傾向 **(c)**，但這動到 `personal_memory_resource_contracts` 的
`id_templates`，屬 T3，必須 Owner 先裁決再實作。

## 不做

不在這張卡改任何程式。pilot 目前是 local-only，沒有立即風險；
在公司端匯總開工之前裁決即可。
