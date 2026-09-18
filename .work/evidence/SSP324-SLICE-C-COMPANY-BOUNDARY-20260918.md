# SSP-324 切片 C — evidence

日期：2026-09-18　branch：`cc/ssp324-company-boundary`　base：`9ac5de7`

## 交付

```
規格/v0.1/personal-harness-integration.yaml   +company_side_evidence_boundary
scripts/validate_company_side_evidence_boundary_contract.rb   234 行（< 400）
規格/v0.1/fixtures/company-side-evidence-boundary-{positive,negative}-fixtures.json
scripts/validate_personal_memory_contract.rb          +1 行（接入 aggregator）
```

**未修改切片 A／B、切片 1、SSP-294 任何既有契約或程式**——全部 pointer-bind。

## 設計回應

### 驗證單位：一筆公司端處理紀錄

「封包只能拿來 review／verification／audit」是**用途**問題，「封包不得被
正式 retrieval 命中」是**產出**問題。分開驗會各自留一半，所以 run 同時
包含 `purpose`、`promotion_proposal_ref`／`promotion_steps_completed`、
`retrieval_pack`、`needs_org_followup`。

### canonical 不是封包能走的捷徑

帶 `promotion_proposal_ref` 必須：用途為 `PROMOTION_REVIEW_SUPPORT`、
ref 為合法 URN、且 `promotion_steps_completed` **逐項等於上游
`promotion_flow.required_steps`**（含最後的 `canonical_single_writer`）。
少任何一步都是 `CSB_PROMOTION_STEPS_INCOMPLETE`——兩個負例分別拿掉
`review` 與 `canonical_single_writer`。契約另有斷言確認上游的
`direct_copy_to_shared_canonical` 仍是 `forbidden`，本片不加例外。

### 正式 retrieval 命不到封包（卡片 Acceptance #4）

檢查的欄位名（`selected_memories`／`source_refs`）讀自
`recall_context_pack.contract.pack_required_fields`，不是本片自創；
validator 另有斷言確認這兩個欄位確實在上游清單裡。兩條線：
本筆 `package_ref` 出現在 retrieval 裡 → `CSB_RETRIEVAL_NAMES_HANDLED_PACKAGE`；
任何其他 evidence package 出現 → `CSB_RETRIEVAL_NAMES_EVIDENCE_PACKAGE`。

### `NEEDS_ORG_FOLLOWUP` 不取得 canonical identity（Acceptance #5）

`suggested_expert` 為 `null` 或字串都合法（兩個正例各一），但 follow-up
不得帶 `canonical_record_ref`，也不得夾帶 `historical_comparison` 已封的
lifecycle 欄位——後者直接重用共用 helper 的禁列，不重抄。

### 先套用切片 A／B 的教訓

1. **封閉 allowlist**：`HANDLING_ALLOWED_FIELDS`，外加禁用輸出欄位放在
   allowlist **之前**以保留明確錯誤碼（切片 A repair-01 學到的順序）。
2. **每個值都鎖形狀**：package_ref／proposal_ref 驗 URN ＋ 前綴，
   retrieval_pack／followup 驗 map，suggested_expert 驗字串或 null。
3. **每個檢查先答「權威對照物是誰」**：見卡片的對照表。唯一自創的 purpose
   詞彙採封閉 allowlist，且每個 forbidden purpose 都必須被負例實際打過
   （斷言強制）。

## 接回總入口的實測

```
中和 CSB_RETRIEVAL_NAMES_EVIDENCE_PACKAGE（卡片 Acceptance #4 的 guard）：

直接呼叫新片   → FAIL CSB_NEG_RETRIEVAL_NAMES_OTHER_PACKAGE 預期 deny，實際通過
               → FAIL error_contract 宣告但 evaluator 不可能回傳
呼叫總入口     → 同樣的 FAIL，外加
               → FAIL personal memory contract validation :: slice
                 validate_company_side_evidence_boundary_contract exited 1
```

## 逐 return site parity（非逐 code）

15 個 return site → 15/15 全紅（第一輪就全紅），未被測到：無。

## Gate

```
ruby scripts/validate_*.rb（37 支，含新增這支）→ PASS
四支 Python schema engine                       → 環境缺 jsonschema（pre-existing）
git diff --check                                 → clean
```

## 已知邊界（主動揭露）

`evidence_package_ref_prefix` 是本片宣告的，因為上游沒有 evidence-package
的 id_template（切片 A 對 `package_id` 也只驗 generic URN）。為了讓宣告
不能漂移，validator 對每個正例額外斷言「該筆 `package_ref` 必須符合宣告的
前綴」——宣告與實際使用的封包 identity 綁在一起。若日後上游補了
evidence-package 的 id_template，這裡應改綁它。
