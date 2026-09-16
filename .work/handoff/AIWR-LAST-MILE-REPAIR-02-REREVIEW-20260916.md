# AIWR 最後一哩 repair-02 — 定點 re-review 交付包

同一條 review line。只收 `7e5eed0` 的那一筆 P1（F-01 第二輪）。

## 鎖定

```
base                654313b
original_review     3d3b53c   （第一輪 NO_GO）
repair_01           7e5eed0   （NO_GO，P1=1：F-01 未完全關閉）
repair_commit       <見對話中的派工區塊>
branch              cc/aiwr-last-mile
```

定點 diff：`git diff 7e5eed0..<repair_commit>`

## 收法

你指出 `urn:omos:task-card:not-a-uuid` 仍會被放行——屬實。我上一輪只擋了
**entity 種類**（前綴），沒擋 **identity 形狀**。

修法不是把 `CARD_ID_URN` 那條 regex 抄一份過來，而是**綁定它的原始碼**：
從 `scripts/validate_ai_task_card_record_contract.rb` 抽出 `CARD_ID_URN`
的字面值再 eval，抽不到就 `RuntimeError` fail loud。上游改名或改結構時
這裡會爆，不會默默退回寬鬆比對。

錯誤訊息也改成印出實際綁到的 pattern 與來源檔名。

## 請重播

```bash
# 你的案例
OMOS_TASK_REF=urn:omos:task-card:not-a-uuid \
  ruby .claude/hooks/aiwr_pilot_hook.rb <<< \
  '{"session_id":"s","prompt_id":"t","hook_event_name":"UserPromptSubmit"}'
ruby scripts/build_aiwr_capture_batch.rb .work/evidence/ssp310-pilot-runtime-log.jsonl /tmp/out
echo "exit=$?"   # 應為 3，且 /tmp/out 不存在
rm -f .work/evidence/ssp310-pilot-runtime-log.jsonl
git checkout -- .work/evidence/ssp310-pilot-runtime-log.jsonl

# 常設 gate（已把你的案例固定成負例）
ruby scripts/validate_aiwr_capture_batch_builder.rb   # 應 PASS

# enforcement parity
#   1. TASK_CARD_URN 放寬回 /\Aurn:omos:task-card:.+\z/  → 應 FAIL
#   2. 把綁定用的常數名改成不存在的                       → 應 RuntimeError（fail loud）
```

我的結果：`exit=3`、未產出檔案；gate PASS；兩個 parity 都如預期；還原後
`diff` 逐位元相同。

## 現在的負例覆蓋

| 案例 | 意義 |
|---|---|
| `urn:omos:evidence:not-a-task-card` | 不是 task-card entity |
| `urn:omos:task-card:not-a-uuid` | 前綴對、identity 形狀不合法（你這輪的案例）|
| 對照組：canonical UUID | 必須放行，確認收窄沒過頭 |

## Gate

```
ruby scripts/validate_*.rb（25 支）  → PASS
四支 Python schema engine            → PASS（你的 runtime 若被 uv panic 擋住可略過）
git diff --check                      → clean
兩支腳本                               → 155 / 196 行（< 400）
真人 pilot log                         → 仍 2 筆
```

## 順帶修正（非 finding，主動揭露）

檔頭註解原本把 FP-3-A 寫成「決定性字串」，沒反映 repair-01 已改成 JSON
tuple 編碼。敘述沒有變成假的，但同屬「舊敘述沒跟著新實作走」，一併補上。

## 請只判斷

這一筆 F-01 是否已關閉。真人帶 `OMOS_TASK_REF` 的實跑仍是下一步，不在本卡。
