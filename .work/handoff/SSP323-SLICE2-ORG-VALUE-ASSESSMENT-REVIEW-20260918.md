# SSP-323 切片 2 — 大 review 交付包

## 鎖定

```
base    f38e82c
review  （本次 commit，待 push 後補上）
branch  cc/ssp323-org-value-assessment
```

新增三個檔案 + 修改既有 aggregator/spec 各一處：

```
規格/v0.1/personal-harness-integration.yaml         +organizational_value_assessment
scripts/validate_organizational_value_assessment_contract.rb  224 行
規格/v0.1/fixtures/organizational-value-assessment-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb        +1 行（SLICE_VALIDATORS）
```

**未修改任何既有契約區塊或既有 validator 的判斷邏輯**——唯一動到既有檔案
的地方是把新 slice 名稱加進 aggregator 的清單。

## 這張卡

`SSP-323`（EMEM-09）切片 2：Organizational Value Assessment 與
`NEEDS_ORG_FOLLOWUP`。承接切片 1 review 立下、對本卡以後每片都適用的兩項
硬要求：

1. **聚合器接回實測**：不只直接呼叫新片會紅，呼叫聚合器
   `validate_personal_memory_contract.rb` 也要同步轉紅。
2. **機器可查訊號 vs 判斷型訊號分離**：不能只驗自報一致，不驗事實。

本卡的落實方式跟切片 1 不同——九個構面（repeatability／impact_scope／
reusability／cost_of_not_knowing／decision_rationale_value／scarcity／
stability／evidence_strength／sensitivity_or_permission_constraint）本質
上都是人的價值判斷，沒有像切片 1 的 identity/hash/evidence-set 那樣的原始
訊號可以推導。所以這裡機器守住的不是「推導」，而是「完整性 + 佐證」：九
個構面一個都不能少報；HIGH 評分（唯一會驅動 `needs_org_followup` 的關鍵
主張）必須附非空 reasons 與至少一個 URN evidence_ref，不接受靠 bare label
就被信任。

## 請重播

```bash
ruby scripts/validate_organizational_value_assessment_contract.rb   # 應 PASS
ruby scripts/validate_personal_memory_contract.rb                    # 應 PASS（接回總入口）

# 接回總入口的證明：中和 OVA_FOLLOWUP_WITHOUT_ORG_VALUE 的 guard，
# 不只直接呼叫新片會紅，呼叫總入口也應該紅
# 逐 return site parity（非逐 code）→ 我的結果 18/18 全紅
```

## 請特別判斷

1. **九個構面是否該強制全部評分**：目前設計要求 `dimension_ratings`
   恰好是這九個 key，缺一個或多一個未知 key 都拒絕。理由是防止只挑喜歡
   的構面講、迴避不利的——請判斷這個「不能少報」的要求是否過嚴，或應該
   允許部分構面標記為「本次未評」而不強制打分。
2. **HIGH 才要佐證、LOW/MEDIUM 不要求，是否留了漏洞**：目前設計只有
   HIGH 評分需要 reasons + evidence_ref。如果有人想規避佐證義務，可以
   把明明是 HIGH 的東西謊報成 MEDIUM——這個 gap 評估後未修：MEDIUM 不會
   觸發 `needs_org_followup`，也不會被當成「組織價值高」的證明，所以少報
   評分等級只會讓這筆評估看起來價值較低，沒有從中得利的誘因。請判斷這個
   評估是否成立。
3. **`needs_org_followup` 是否該要求 `suggested_expert` 提供理由**：目前
   `suggested_expert` 是純 optional hint，出現與否或內容都不影響通過與否
   （只檢查型別是字串或 null）。請判斷這是否符合卡片「不要求員工先知道哪
   位同事是 expert」的原意，或該加一個弱檢查。
4. **`OVA_ANSWER_INCONSISTENT` 的雙向一致性是否足夠**：目前只檢查
   `answer_provided` 與 `unresolved_question` 是否互相矛盾，不檢查
   `unresolved_question` 的內容品質（例如全空白字串以外的其他弱內容）。
   請判斷是否需要更嚴格的內容檢查，或目前的存在性檢查已足夠。

## Gate

```
ruby scripts/validate_*.rb（32 支）  → PASS
四支 Python schema engine            → 環境缺 jsonschema（pre-existing，
                                        本卡未改動其涵蓋範圍）
git diff --check                      → clean
```

最後請以 `P0 / P1 / P2 / P3` 分級給 `GO` 或 `NO_GO`。
