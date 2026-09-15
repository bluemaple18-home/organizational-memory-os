# SSP-309／AIWR-11 Native Adapter Conformance — evidence

日期：2026-09-15　branch：`cc/ssp309-native-adapter-conformance`　base：`5e511c4`

## 研究結論：原計畫 3 條斷言縮減為 2 條

評估階段列了 C-01（`lifecycle_event_map` 綁上游）／C-02（`mapping_run` 欄位
相等）／C-03（`error_contract` 語意碼對應）。實作前重查既有 validator 原始碼：

```
scripts/validate_codex_native_adapter_contract.rb:148-170
scripts/validate_claude_code_native_adapter_contract.rb:144-163
```

兩支既有 validator **各自**已經在跑的時候讀取同一份
`規格/v0.1/ai-task-card-record.yaml`，把 `lifecycle_event_map` 的每個
target fail-closed 綁到 `lifecycle_event_to_status` 的 key——讀檔案本身
做真實 binding，不是自我宣稱。兩邊讀的是同一份實體檔案，所以「兩個
Adapter 對同一上游一致」在數學上已經是真的。原計畫的 C-01 因此**不實作**
——加一支第三方 validator 再比一次，會是「兩份手寫清單互相比對」的重複
模式（先前 review-cadence 就被指出過這個反模式）。

最終只做原 C-02／C-03，改編號為本卡的 C-01／C-02。

## 新增檔案

`scripts/validate_ssp309_native_adapter_conformance.rb`（148 行，< 400 限制）

- **C-01**：`mapping_run` 核心欄位集合／`outcomes` 列舉兩邊須相等，平台
  專屬欄位（該契約 `mapping_run` 底下有一個只在單邊出現的 `<field>_rule`
  說明鍵）例外。真實資料下：`stop_hook_active` 因為只有 Claude Code 有
  `stop_hook_active_rule` 而被正確排除；核心 5 欄位
  （`native_event_type / mapped_to / adapter_output_ref /
  native_correlation_ref / outcome`）兩邊相等；`outcomes`
  （`MAPPED / NOT_LIFECYCLE / DISABLED`）逐字相等。
- **C-02**：`error_contract` 的碼去掉 `CODEX_` / `CLAUDE_CODE_` 前綴後，
  差集只有各一筆——Codex 的 `RUNTIME_SAMPLE_UNCLASSIFIED`（SSP-308 明確
  延後 runtime probe）、Claude Code 的 `STOP_HOOK_ACTIVE_NOT_TERMINAL`
  （FP-2-A，Codex 沒有對應已知問題）——兩者在各自契約文字裡都不只出現
  一次（`error_contract` 定義之外還有 `design_note`／`*_rule` 引用），
  視為有記錄的平台差異，不是漏做。

## 沒有新增 fixture JSON 檔

這支 validator 比對的是兩份**靜態契約**本身（不是逐筆 runtime record），
所以沒有「正例／負例 fixture」這種形狀。改用兩個抽出的 pure function
（`mapping_run_conformance_failures` / `error_contract_conformance_failures`）
＋腳本內建的 self-test 區塊：在記憶體裡對兩份契約的複本注入違規（多一個
欄位、outcomes 集合不同、加一個完全沒被引用的錯誤碼、加一個被引用兩次
的錯誤碼），呼叫同一個 function 驗證它真的會抓到／真的不會誤擋——不寫
入、不碰兩份真實 adapter 契約檔案。

## Enforcement-parity 驗證（cp 備份，非 git checkout）

逐一中和兩條核心 assert，確認 self-test 會抓到「guard 被拔掉」：

```
中和 C-01 欄位相等 assert → FAIL self-test 未全部通過：...核心欄位集合不相等時必須回報，實際通過
中和 C-02 codex-only count>=2 assert → FAIL self-test 未全部通過：...完全沒被文件引用時必須回報，實際通過
```

還原後（`cp` 從備份複製回來，`diff` 確認逐位元相同）：`PASS`。

## Gate

```
ruby scripts/validate_*.rb（全部 24 支）              → PASS
document_adapter_mapping_instances.py                → PASS
cc_cross_layer_contract.py                            → PASS
jira_adapter_mapping_instances.py                     → PASS
std_schema_engine.py                                  → PASS
git diff --check                                      → clean
```

未修改任何既有契約檔案／既有 validator——只新增一支唯讀比對用的
validator（讀三份既有 YAML：兩份 Adapter + 間接透過既有 validator 已綁定
的 `ai-task-card-record.yaml`，本檔實際只直接讀兩份 Adapter 契約）。
