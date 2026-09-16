# repo #5 稽核 repair-01 — 定點 re-review 交付包

同一條 review line。只收 `1fe526e` 的那一筆 P1。

## 鎖定

```
base                710d2c8
original_review     1fe526e   （NO_GO，P1=1）
repair_commit       <見對話中的派工區塊>
branch              cc/canonical-direct-write-audit
```

定點 diff 只動 `scripts/validate_canonical_promotion_binding.rb`。

## 收法

你說得對：原本兩個 early return（有 pointer／在 KNOWN_UNBOUND）讓 gate 只
驗「有沒有綁」，不驗內容。`KNOWN_UNBOUND` 因此是變相放行。

改成**在 pointer 與例外檢查之前**先做語意比對：

- `weakening_in_sequence`：順序必須遞增（`steps_out_of_order`）；自己涵蓋的
  index 區間內不得跳步（`skip_any_step`）。只檢查它自己涵蓋的範圍，讓「只
  描述尾段」這種合法寫法不被誤殺。
- `weakened_rules`：任何與上游 `promotion_path.rules` 同名的 key，值必須與
  上游相同——`skip_any_step: allowed` 在寫下的當下就被擋。
- `KNOWN_UNBOUND` **只**豁免「缺 pointer」，永不豁免 step／order／rule 漂移。

## 請重播（你的兩個 bypass ＋ 兩個補充）

```bash
# 1. 從 core_pipeline 刪掉 VERIFICATION（該條已登記在 KNOWN_UNBOUND）
#    → 應 FAIL（證明例外不再豁免內容漂移）
# 2. 新增帶正確 pointer、只有 CANDIDATE → RECORD、skip_any_step: allowed 的 yaml
#    → 應 FAIL 兩條（規則面 + 步驟面）
# 3. 順序顛倒 PERSONAL_ACCEPTANCE → VERIFICATION
#    → 應 FAIL
# 4. 只描述尾段 VERIFICATION → PERSONAL_ACCEPTANCE（合法）
#    → 應 PASS（請確認沒有誤殺）
```

我的結果與上述一致，詳見
`.work/evidence/CANONICAL-DIRECT-WRITE-AUDIT-REPAIR-01-20260917.md`。

## 請特別判斷

1. **「只檢查自己涵蓋的 index 區間」這個設計是否留了洞**：契約可以合法地
   只描述尾段，所以我不要求每條 restatement 都從第一步開始。請判斷這會不會
   讓「只寫 CANDIDATE → RECORD 但語意上宣稱那就是全部」逃掉——我的看法是
   那個情境會被跳步檢查抓到（中間缺 VERIFICATION／ACCEPTANCE），但請覆核。
2. **`weakened_rules` 用「同名即須同值」是否過嚴**：下游若有正當理由使用
   同名 key 表達不同層次的東西，會被誤殺。我認為在這個 repo 值得從嚴，但
   請裁決。
3. `KNOWN_UNBOUND` 現在只豁免缺 pointer——是否已不再是變相放行。

## Gate

```
ruby scripts/validate_*.rb（27 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
```

## 請只判斷這一筆

稽核 findings（F-01 P2／F-02 P3）你上輪已接受、且依 FP-3-A 處置權在 Owner，
本輪未動。
