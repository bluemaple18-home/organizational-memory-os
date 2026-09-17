# SSP-294 切片 B — evidence

日期：2026-09-17　branch：`cc/ssp294-promotion-policy`　base：`8334020`

## 稽核到的起始狀態

上游 15 格全貌（5 actor × 3 材料類別），實際被驗到的只有一格：

```
EMPLOYEE  × 3 類別  CONDITIONAL（4 條件）
MANAGER   × EMPLOYEE_PRIVATE DENY／其餘 CONDITIONAL（6 與 5 條件）← 只有這格的 3 條被驗
ADMIN     × 3 類別  DENY
REVIEWER  × 3 類別  CONDITIONAL（5／4／4 條件）
SYSTEM    × 3 類別  DENY
```

`validate_personal_memory_scope_contract.rb:127-130` 驗的是
`MANAGER/COMPANY_MANAGED_PERSONAL` 的 3 條條件「有沒有列在清單裡」——不是
「升格時有沒有滿足」。其餘 14 格完全沒有 evaluator 會攔。

## 交付

```
規格/v0.1/emem-promotion-policy.yaml                    129 行
scripts/validate_emem_promotion_policy_contract.rb      222 行（< 400）
fixtures：正例 15 筆（每格一筆）／負例 10 筆
```

## 自己探測出的三個問題（送審前修掉）

這輪一開始就用逐 return site 探測＋上游變動探測，結果自己抓到三件事：

### 1. 覆蓋斷言不夠——治理放寬會無聲通過

原本只驗「每格被 fixture 踩過」。實測把 `ADMIN/SHARED_WORK_CONTEXT` 從
`DENY` 翻成 `CONDITIONAL`，**gate 照樣 PASS**——因為該格的正例是 `DENIED`，
而 `DENIED` 在任何 decision 下都合法。等於上游把一條禁令放寬，沒有人發現。

改成決策感知：`CONDITIONAL` 格必須有成功升格的正例、`DENY` 格必須有被拒的
正例。三種上游變動現在都會紅：

```
DENY 放寬成 CONDITIONAL → FAIL CONDITIONAL 格 ADMIN/SHARED_WORK_CONTEXT 缺少成功升格的 fixture
新增一個 actor          → FAIL DENY 格 CONTRACTOR/EMPLOYEE_PRIVATE 缺少被拒的 fixture
新增一條條件            → FAIL POLICY_POS_EMPLOYEE_EMPLOYEE_PRIVATE_ALL_CONDITIONS 預期 allow，
                               實際被拒：POLICY_CONDITION_UNSATISFIED
```

### 2. 逐 site parity 抓到 site 7 未覆蓋

`POLICY_CONDITIONS_NOT_MAP` 有兩個 return 位置：`satisfied` 不是 map、以及
上游 `required_conditions` 不是清單。我的負例只打到前者。補上後者
（用自帶 policy 的 fixture，因為健康上游產不出這種輸入）。

### 3. 負例的 actor 名稱會撞名

`POLICY_NEG_UNKNOWN_ACTOR` 原本用 `CONTRACTOR`；我在測「上游新增 actor」時
剛好也用了這個名字，於是那個負例失效、錯誤碼變成別的。改用
`ACTOR_THAT_DOES_NOT_EXIST_UPSTREAM`。

## 套用了前面各輪的教訓

- **不做任何寬容轉型**：`satisfied_conditions`、`required_conditions` 都先
  `is_a?` fail-closed，不用 `.to_a`／`.to_h`——切片 A 就是栽在這。
- **不重述上游**，並有斷言禁止抄名稱。
- **一開始就用逐 return site**（非逐 code）探測。
- **provenance boundary 主動宣告**，包含「宣告的 actor 未必是真的 actor」。

## 一個當場印證的 backlog 項目

切片 A 的 review 指出「禁止重述用全文 substring 掃描偏脆」。本輪**當場被自己
的檢查抓到**：`provenance_boundary` 散文裡寫了 `EMPLOYEE`／`REVIEWER` 兩個
詞，被判定成重述上游名稱。我改寫了散文繞開，但這正是那筆 backlog 說的問題
——已登記在 `文件/待辦重整.md`，本輪不擴大處理。

## Gate

```
ruby scripts/validate_*.rb（29 支，含新增這支）  → PASS
四支 Python schema engine                         → PASS
git diff --check                                   → clean
逐 return site parity（10 個）                     → 10/10 全紅
決策格覆蓋                                          → 15/15
```
