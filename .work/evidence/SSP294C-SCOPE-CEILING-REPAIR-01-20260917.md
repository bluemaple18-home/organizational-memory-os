# SSP-294 切片 C repair-01 — evidence

回應 `61ba39b` 的 NO_GO（P1×1 + P2×2）。P1 收，P2 依 reviewer 指示登 backlog。

## P1：FP-2-A 只有文字宣告，沒有機器強制

屬實，而且是最不該犯的一種——**我在契約與交付包裡宣稱「已隔離」，卻只驗證了
「文字有沒有寫著隔離」**，不是「有沒有真的隔離」。

reviewer 塞了 `promotion_path_ref: ai-work-record-boundary.promotion_path.
ordered_steps` 進契約，原本兩條斷言（檢查 `promotion_name_collision.rule`
與 `hard_stops` 的散文內容）照樣 PASS——因為它們驗的是說明文字裡有沒有提到
`promotion_path` 這個詞，不是契約結構裡有沒有真的綁它。

修法：新增結構化掃描。走遍整份契約的 Hash／Array／String 節點，任何字串值
只要**整個值**（不是子字串）符合
`ai-work-record-boundary.promotion_path` 或其子路徑的形狀，就判違規。

```ruby
def promotion_path_pointer?(value)
  return false unless value.is_a?(String)
  /\Aai-work-record-boundary\.promotion_path(\.[\w.]+)?\z/.match?(value.strip)
end
```

用 `\A...\z` 整值比對而非子字串搜尋，刻意讓「散文裡提一句話討論兩者的差異」
不會被誤判——那正是本契約 `promotion_name_collision.rule` 自己要做的事。

## 驗證：重播 reviewer 的確切 exploit ＋ 兩個變體 ＋ 一個對照

```
reviewer 的原始 exploit（ceiling_binding.promotion_path_ref = ordered_steps）
  → FAIL FP-2-A 違規：...ceiling_binding.promotion_path_ref

變體 1（裸前綴，無子路徑）
  → FAIL ...ceiling_binding.x

變體 2（藏在陣列裡）
  → FAIL ...sneaky_list[0]

對照（散文句子裡包含這個字串，非欄位值本身）
  → PASS（正確不誤殺——這正是契約自己在做的事）
```

## 無 repair regression

- 逐 return site parity 重跑：7/7 全紅（本輪未動 `scope_ceiling_failure`
  本體，此為確認未受影響）。
- 30 支既有 validator 全 PASS，`git diff --check` clean。

## 兩筆 P2 依 reviewer 指示登 backlog，未在本輪修

1. 「新增 scope 必轉紅」宣稱過寬——覆蓋斷言只盯
   `widening_requires_promotion_gate: true` 的範圍，新增一個旗標 `false` 的
   scope 不會被踩到。
2. `from_scope == to_scope` 未定義語意——因嚴格子集判斷落入放寬分支，語意上
   應是 no-op。

兩者修法已知、已記入 `文件/待辦重整.md` 規範債表。

## Gate

```
ruby scripts/validate_*.rb（30 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
validator                             → 224 行（< 400）
```
