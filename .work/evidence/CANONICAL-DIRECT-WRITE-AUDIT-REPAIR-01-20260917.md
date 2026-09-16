# repo #5 稽核 repair-01 — evidence

回應 `1fe526e` 的 NO_GO（P1×1）。

## F-01（P1）：gate 只驗「有沒有綁」，不驗「綁的內容有沒有被弱化」

屬實。原本的邏輯是兩個 early return：檔案裡有 pointer → 整份放行；key 在
`KNOWN_UNBOUND` → 整條放行。兩者都沒有比對步驟或規則本身。

reviewer 重播的兩個 bypass 都成立：

```
從 core_pipeline 刪掉 VERIFICATION            → 原本仍 PASS
新增帶正確 pointer 但只有 CANDIDATE → RECORD
且 skip_any_step: allowed 的契約              → 原本仍 PASS
```

所以 `KNOWN_UNBOUND` 確實變成變相放行——它只確認「這條路還存在」，不確認
「這條路沒有進一步漂壞」。這違反已簽的 FP-2-A（不得少步驟／不得放寬
forbidden）與 FP-4-B（任何弱化都要自動轉紅）。

## 修法：改成逐條語意比對

新增兩個純函式，**在 pointer 與例外檢查之前先跑**：

### `weakening_in_sequence(array, steps)`

- **順序**：restatement 內 canonical 步驟的 index 必須遞增，否則就是
  `steps_out_of_order`（上游 forbidden）。
- **不得跳步**：取該 restatement 自己涵蓋的 index 區間，區間內每一個
  canonical 步驟都必須出現，否則就是 `skip_any_step`（上游 forbidden）。
  刻意只檢查它自己涵蓋的範圍——契約可以只描述尾段（合法），但不能在自己
  描述的範圍中間挖掉一步。

### `weakened_rules(spec, upstream_rules)`

走遍整份契約，任何與上游 `promotion_path.rules` **同名**的 key，其值必須
與上游相同。不同即紅。理由：下游本來就不該重新定義上游規則，
`skip_any_step: allowed` 這種寫法應該在出現的當下就被擋，而不是等到有人
去比對兩份文件。

### `KNOWN_UNBOUND` 的豁免範圍收窄

現在**只**豁免「缺 pointer」這一項。step 跳步、順序顛倒、規則放寬一律照驗
照紅。檔頭註解也寫明這點，避免日後有人誤以為登記進去就整條免驗。

## 驗證：四種弱化模式 ＋ 一個不得誤殺的合法情境

```
bypass 1（reviewer）：core_pipeline 刪掉 VERIFICATION
  → FAIL ...涵蓋 PERSONAL_MEMORY_CANDIDATE → PERSONAL_MEMORY_RECORD
         但跳過了 VERIFICATION（上游 skip_any_step: forbidden）
     ※ 注意：這條已登記在 KNOWN_UNBOUND，仍然被擋——證明例外不再豁免內容漂移。

bypass 2（reviewer）：有正確 pointer、只有 CANDIDATE → RECORD、
                     且 skip_any_step: allowed
  → FAIL ...probe_rules.skip_any_step = "allowed"，與上游 ... "forbidden" 不一致
  → FAIL ...涵蓋 ... 但跳過了 VERIFICATION / PERSONAL_ACCEPTANCE
     ※ 同時觸發兩條，規則面與步驟面各擋一次。

探測 3：順序顛倒（PERSONAL_ACCEPTANCE → VERIFICATION）
  → FAIL 步驟順序與上游不一致 ...

探測 4（不得誤殺）：只描述尾段 VERIFICATION → PERSONAL_ACCEPTANCE
  → PASS（合法的局部重述，未跳步、未亂序）
```

## Gate

```
ruby scripts/validate_*.rb（27 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
validator                             → 177 行（< 400）
```

## 未改動

- 依 FP-3-A，仍**未開任何 repair 卡、未修改任何既有契約**。F-01／F-02 兩筆
  findings 的處置權仍在 Owner。
- 稽核 findings 文件（`CANONICAL-DIRECT-WRITE-AUDIT-20260916.md`）的結論
  未變——本輪修的是 gate 的強度，不是稽核結果。
