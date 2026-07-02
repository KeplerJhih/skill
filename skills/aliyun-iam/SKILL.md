---
name: aliyun-iam
description: >-
  阿里雲 RAM / RBAC 權限授予與排錯指南（實戰累積）。當使用者要求「授權某帳號」、
  「給子帳號權限」、「RAM 授權」、「建 RAM user」、「AccessKey」、「最小權限」，
  或遇到權限類報錯 — 「NoPermission」、「Forbidden」、「cannot list resource」、
  「secrets is forbidden」、「MissingAuth」、「please complete the ramrole authorization」、
  「子帳號不能釋放」，或涉及 ASM / ACK 的 K8s 層授權 —
  「istio-admin」、「ASM 授權」、「GrantUserPermissions」、「DescribeUserPermissions」、
  「service_mesh_user_permission」、「kubeconfig 沒權限」、「auth can-i」、
  「ACK 唯讀帳號」、「看 pod log 權限」、「AliyunCASDefaultRole」、「SLR 授權」
  等阿里雲權限問題時，立刻觸發此 skill。
  與 aliyun-pitfalls（錯誤碼排錯）、terraform skill 互補：本 skill 聚焦「授權的操作面與權限模型」。
version: 1.0.0
---

# Aliyun IAM — RAM / RBAC 授權實戰

> 聚焦「誰能做什麼、怎麼授、授了為什麼還是不行」。錯誤碼排錯先查 `aliyun-pitfalls`；
> 本文處理授權模型與操作步驟。

## 權限模型速覽（三層，常被混為一談）

| 層 | 管什麼 | 授權工具 |
|---|---|---|
| **RAM**（雲帳號層） | 子帳號能呼叫哪些雲 API（建 ECS、查 ACK…） | RAM Policy（console / TF `alicloud_ram_*`） |
| **服務角色 SLR / ServiceRole** | 雲服務之間互相代操作（OOS 管 NodePool、CAS 部署證書到集群） | 一次性授權連結 / console，**多數要主帳號** |
| **K8s RBAC**（集群層） | 拿著 kubeconfig 能對 ACK / ASM API server 做什麼 | ACK：console 授權頁；ASM：TF `alicloud_service_mesh_user_permission` |

**排錯第一問**：報錯來自哪一層？`Code: NoPermission`（CLI/TF）→ RAM 層；
`cannot list resource ... in API group`（kubectl/helm）→ K8s RBAC 層。

## 鐵律

1. **子帳號不能釋放付費資源**（ACR EE / EIP / NAT / SLB…）— 要主帳號或 `AliyunBSSFullAccess`
2. **SLR 一次性授權必須主帳號點**（例：`AliyunOOSLifecycleHook4CSRole`，見 pitfalls #4）
3. **能進 TF 的授權就進 TF**（`alicloud_ram_*` / `alicloud_service_mesh_user_permission`），
   console 手動授權完必須 import 收斂

## RAM：跑 Terraform 的子帳號最低套餐

`AliyunVPCFullAccess` + `AliyunCSFullAccess` + `AliyunContainerRegistryFullAccess` +
`AliyunRAMFullAccess`（ACK 建 worker role 需要）+ `AliyunOSSFullAccess`（state bucket）+
`AliyunECSFullAccess` + `AliyunSLBFullAccess`。
故意不給：`AliyunBSSFullAccess`（計費 / 釋放付費資源 — 留主帳號）。

業務型子帳號（如 OSS 上傳）用自訂 Policy 鎖單一 bucket，範本見
`devops/terraform/CLAUDE.md` 的 OSS RD bucket 段。

查當前授權：`aliyun ram ListUsers`、`aliyun ram ListPoliciesForUser --UserName <name>`。

## ASM 實例 RBAC（2026-06 實戰，最容易踩）

### 授權（TF 唯一正解）

```hcl
# 新 ASM 實例預設只有主帳號有 RBAC，子帳號 kubeconfig 拿到手也是 0 權限
resource "alicloud_service_mesh_user_permission" "subaccount" {
  sub_account_user_id = "<RAM UserId>"   # aliyun ram ListUsers 查
  permissions {
    role_name       = "istio-admin"      # istio-admin / istio-ops / istio-readonly
    service_mesh_id = module.asm[0].service_mesh_id
    role_type       = "custom"
    is_custom       = true
  }
}
```

⚠️ 此 resource 管理「**該子帳號的全部 mesh 授權清單**」— 多 mesh 時要在同一個
resource 內列齊所有 `permissions` block，分開寫會互相覆蓋。

### 關鍵認知：istio-admin ≠ cluster-admin

子帳號的 istio-admin **只開放 Istio CRD + Namespace**；core 資源（secrets / configmaps /
clusterrolebindings）一律 Forbidden — **這是設計，不是授權失敗**。直接後果：
helm 無法對 ASM API server 部署（存不了 release Secret），一律改
`helm template | kubectl apply`。詳見 pitfalls #33。

### 驗證與排錯

```bash
aliyun servicemesh DescribeUserPermissions --SubAccountUserId <id>   # 雲端記錄了什麼
KUBECONFIG=<asm> kubectl auth whoami        # 憑證身分 = <RAM UserId>-<憑證序號>
KUBECONFIG=<asm> kubectl auth can-i create destinationrules.networking.istio.io -n <ns>
```

- 授權寫入成功但 can-i 仍 no → RBAC 同步有**數分鐘延遲**；先等，再重新下載 kubeconfig
  （`aliyun servicemesh DescribeServiceMeshKubeconfig`），最後才懷疑授權內容
- can-i core 資源（secrets / configmaps）永遠 no → 正常（見上），別當成授權壞了排查

## ACK 集群 RBAC

- kubeconfig 取得：`aliyun cs DescribeClusterUserKubeconfig --ClusterId <id>`
  — **拿得到 kubeconfig ≠ 有 RBAC**，RAM 授權與集群 RBAC 是兩件事
- 子帳號集群授權：ACK console「授權管理」按 cluster × namespace 授
  admin / ops / dev / restricted，或自訂 ClusterRole 綁定
- 唯讀案例（給 RD 看 pod log）：cluster 級 readonly + 自訂 ClusterRole 補
  `pods/log` get 權限（`kubectl logs` 報 Forbidden 多半缺這個）
- 本專案現役唯讀帳號：`rd-siou-ack`（見 `devops/terraform/CLAUDE.md` shared 層）

## 服務角色（SLR / ServiceRole）— 用到才授，主帳號操作

| 角色 | 何時需要 | 觸發症狀 |
|---|---|---|
| `AliyunOOSLifecycleHook4CSRole` | 第一次建 ACK NodePool | `MissingAuth ... ramrole authorization`（pitfalls #4 有一鍵連結） |
| `AliyunCASDefaultRole` | CAS 證書「部署任務」推到 ACK/ASM 集群 | 部署任務建立失敗 / 無目標集群可選 |
| `AliyunCSManagedXxxRole` 系列 | ACK 託管組件 | 建集群時 console 引導，通常已存在 |

## 排錯 SOP

```
1. 分層：報錯來自 CLI/TF（RAM 層）還是 kubectl/helm（K8s RBAC 層）？
2. RAM 層 → aliyun ram ListPoliciesForUser --UserName <name> 看缺哪個 Policy
3. K8s 層 → kubectl auth whoami + auth can-i <verb> <resource> -n <ns> 定位缺口
4. ASM 層 → DescribeUserPermissions 看雲端記錄 → 等同步 → 重抓 kubeconfig
5. 都對還不行 → 換主帳號操作試一次，分辨「子帳號限制」vs「真 bug」
```

## 與其他 skill 的關聯

- **`aliyun-pitfalls`** — 錯誤碼排錯總表（#3 RAM 套餐、#4 SLR、#33-35 ASM 系列的完整現場）
- **`terraform`** — `alicloud_ram_*` / `alicloud_service_mesh_user_permission` 的 IaC 寫法
- **`k8s`** — kubectl RBAC 通用概念（Role / ClusterRole / auth can-i）
