# SaaS 控制平面

控制平面回答：某公司買哪些 Capability、各開到什麼 Level、哪些 Scope / 人能用、有哪些 policy/usage limit。

## 基本模型

```text
Tenant
  ↓
Capability Portfolio
  ↓
Capability
  ├─ enabled
  ├─ default_level
  ├─ scope_overrides
  ├─ users / groups
  ├─ advanced_overrides
  ├─ usage_limit
  ├─ policy
  └─ effective_configuration
```

Scope 可包含：Organization / Tenant / Department / Team / Group / User / Client / Project / Workspace。

## 與 Permission 的關係

Entitlement 決定「有沒有買 / 能不能用某 Capability」；Permission 決定「這個 identity 能不能碰某資料/動作」。兩者不可混成同一個 boolean。

## 與 Config Governance 的關係

Effective config 必須保留來源與 decision trace。Managed Policy Floor 優先於 lower-scope override；lower scope 可限縮，但不得擴張上層未授權能力。

## Dashboard 應呈現

- 公司有哪些 Capability
- 每顆 Capability 目前 Level / 可升級 Level
- 依 Team/User/Client 的 override
- Capability dependencies
- 目前使用量 / 成本 / 配額
- Permission / policy 狀態
- Connector / model / runtime 相容性
- 哪些能力因 policy 被鎖定

## 定價軸

可由 Base Price + Capability Level + Scope/Seats + Usage + Advanced Override 組成。不是固定 Basic/Pro/Enterprise 三包，也不是單純按 seat。

## 注意

Control Plane 是商業/設定 authority，不是 Knowledge Truth。不能讓 dashboard 的設定資料成為 Canonical Knowledge DB。