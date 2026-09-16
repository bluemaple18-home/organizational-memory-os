# AIWR 最後一哩 closeout repair-02 — evidence

回應 `7e5eed0` 定點 re-review 的 NO_GO（P1×1）。只收這一筆。

## F-01（第二輪，P1）：`urn:omos:task-card:not-a-uuid` 仍會被放行

屬實。repair-01 我把身分收窄到 `\Aurn:omos:task-card:.+\z`，只擋了
**entity 種類**，沒擋 **identity 形狀**——`urn:omos:task-card:not-a-uuid`
這種不存在的身分照樣組出 batch、`hook_capture_failure` 也回 `nil`。

repo 裡 canonical 的 task-card identity 形狀定義在
`scripts/validate_ai_task_card_record_contract.rb` 的 `CARD_ID_URN`：

```
/\Aurn:omos:task-card:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
```

## 修法：綁定，不是手抄

沒有把上面那條 regex 抄一份進 builder——那會變成兩份各自演化的定義，正是
這條 review line 一再被抓的反模式。改成從
`validate_ai_task_card_record_contract.rb` 的**原始碼**抽出 `CARD_ID_URN`
的字面值再 eval：

```ruby
def canonical_task_card_urn_pattern
  source = File.read(CARD_RECORD_VALIDATOR_PATH)
  literal = source[/\nCARD_ID_URN = (\/.*?\/)\.freeze\n/m, 1]
  raise "抽不到 CARD_ID_URN（...結構已改變？）" unless literal
  eval(literal)
end
```

上游若改名或改結構，這裡會 **fail loud**（RuntimeError），不會默默退回寬鬆
比對。錯誤訊息也一併改成印出實際綁到的 pattern 與來源，避免訊息與行為脫節。

## 驗證

### reviewer 的案例直接重播

```
OMOS_TASK_REF=urn:omos:task-card:not-a-uuid → hook 記下 declared_task_ref
ruby scripts/build_aiwr_capture_batch.rb ... → exit=3，且未產出任何檔案
```

修正前：`exit 0` ＋ 產出 batch ＋ `hook_capture_failure` 回 `nil`。

### 固定成常設負例

`validate_aiwr_capture_batch_builder.rb` 的 F-01 負例改成兩個案例並行：

| 案例 | 意義 |
|---|---|
| `urn:omos:evidence:not-a-task-card` | 根本不是 task-card entity |
| `urn:omos:task-card:not-a-uuid` | 是 task-card 前綴，但 identity 形狀不合法 |

另加一個對照組：canonical UUID 形狀必須放行（確認收窄沒有過頭）。

### Enforcement parity（cp 備份／還原）

```
把 TASK_CARD_URN 放寬回 /\Aurn:omos:task-card:.+\z/
  → FAIL F-01 負例（task-card 前綴但非 canonical UUID 形狀）...實際 nil

把來源綁定的常數名改掉（模擬上游改名）
  → RuntimeError: 抽不到 CARD_ID_URN（...結構已改變？）  ← fail loud，非默默降級
```

還原後 `diff` 逐位元相同，gate 回到 PASS。

## 順帶修正（非 finding）

檔頭註解原本把 FP-3-A 描述成「`session_id + native_correlation_ref +
event` 的決定性字串」，沒反映 repair-01 已改成 JSON tuple 編碼。雖然敘述
本身沒有變成假的，但同樣是「舊敘述沒跟著新實作走」，一併補上。

## Gate

```
ruby scripts/validate_*.rb（25 支）  → PASS
四支 Python schema engine            → PASS
git diff --check                      → clean
兩支腳本                               → 155 / 196 行（< 400）
真人 pilot log                         → 仍 2 筆，未受污染
```
