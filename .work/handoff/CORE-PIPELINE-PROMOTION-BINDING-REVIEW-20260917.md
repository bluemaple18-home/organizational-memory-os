# 收 repo #5 F-01 — 大 review 交付包

## 鎖定

```
base    8bf224c
review  <見對話中的派工區塊>
branch  cc/core-pipeline-promotion-binding
```

## 這張卡在做什麼

Owner 裁決 repo #5 稽核的 F-01（P2）不長期停留在 `KNOWN_UNBOUND`，在
SSP-294 開工前以小卡收掉；F-02 維持 P3 不處理。

**理由與稽核當時的說法不同，請注意**：稽核時寫的是「怕上游改了副本忘記改」，
但 repo #5 repair-01 的語意比對**不管有沒有 pointer 都會跑**，所以「上游插入
新步驟」早就會紅。真正沒守住的是**上游移除或改名**——副本留下的孤兒名稱不再
是 canonical step，會直接從比對範圍消失、靜默通過。本卡補的是這個。

## 請重播

```bash
# 1. 上游改名 VERIFICATION → VERIFICATION_STEP       → 應 FAIL（孤兒檢查）
# 2. 上游移除 VERIFICATION                            → 應 FAIL（同上）
# 3. core_pipeline 刪掉 VERIFICATION、covers 不改      → 應 FAIL（宣告與內容脫節）
# 4. promotion_path_ref 改成 none（散文仍提到 pointer）→ 應 FAIL（見下）
ruby scripts/validate_ai_work_record_boundary_contract.rb
ruby scripts/validate_canonical_promotion_binding.rb   # 應 PASS，known unbound=0
```

## 主動揭露：我在探測時抓到自己一個洞

探測 4 第一次跑**沒有紅**。canonical gate 原本用
`raw.include?(BOUNDARY_POINTER)` 判定綁定——整份檔案文字裡提到那串字就算數，
所以散文裡的一句說明就足以冒充綁定。

這與你上輪打我的 P1 同類（驗存在、不驗實質），只是換位置。已改成只認
**結構化欄位的整值**。請重點覆核這個改法有沒有反過來誤殺合法的宣告方式
（例如某契約用 `promotion_path_from:` 這種不同 key 名帶同樣的值——我的實作
不看 key 名、只看值，應該不受影響，但請驗）。

## 請特別判斷

1. **孤兒檢查的方向是否正確**：我要求 `covers` 每一步都必須是上游現存步驟。
   反過來說，上游新增步驟時本卡不會紅（由 canonical gate 的跳步檢查負責）。
   請判斷這個分工有沒有漏。
2. **`core_pipeline` 實際內容必須剛好等於 `covers`** 是否過嚴——若日後
   core_pipeline 想合法地多描述一段 canonical 路徑，就必須同步更新 `covers`。
   我認為這正是要的效果，但請裁決。
3. **斷言放在 boundary validator** 是否是對的落點（它本來就讀該檔並斷言
   `core_invariants`，`core_pipeline` 就在隔壁卻沒被讀）。

## Gate

```
ruby scripts/validate_*.rb（27 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
