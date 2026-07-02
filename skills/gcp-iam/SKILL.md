---
name: gcp-iam
description: >-
  GCP IAM 權限授予與最小權限管理技能。當使用者要求「授權某帳號」、「給 XX 帳號權限」、
  「開唯讀權限」、「grant access」、「IAM 授權」、「最小權限」、「least privilege」、
  「add-iam-policy-binding」、「建立自訂角色」、「custom role」、「給 GKE 唯讀」、
  「允許看 pod log」、「kubectl logs Forbidden」、「container.pods.getLogs」、
  「權限不足排錯」、「trafficdirector.client」、「mesh 權限」、「proxyless 授權」、
  「Workload Identity principal」、「WI 綁定角色」或需要在 GCP 專案層級授予 / 檢視 / 收斂
  IAM 角色時觸發此技能。
  與 terraform、k8s、gcp-architect 技能互補：本技能聚焦「用 gcloud 進行日常 IAM 授權操作」。
version: 0.1.0
---

# GCP IAM 權限授予技能

以**最小權限（least privilege）**為核心，使用 `gcloud` 在 GCP 專案層級授予、檢視與收斂 IAM 角色。
本技能累積實戰授權範本與踩坑，每個場景優先採用「預設唯讀角色 + 必要時補最小自訂角色」的組合，避免一次給過大的 Editor/Owner。

---

## 核心原則

1. **先唯讀、後最小補強**：能用 `roles/*.viewer` 解決就不用 developer/admin；缺的單一權限用自訂角色補，而非升級到含寫入的大角色。
2. **授權前先確認三件事**：
   - 目標**專案 ID**（`gcloud config get-value project` 或明確 `--project`）
   - 成員型別前綴：`user:`、`serviceAccount:`、`group:`、`domain:`
   - 角色是否真含所需權限 —— 用 `gcloud iam roles describe <role> --format="value(includedPermissions)"` 驗證，**別假設角色名稱**就代表它涵蓋某動作。
3. **授權是低風險（修改）操作**：說明影響範圍後執行；**移除權限 / 刪除自訂角色屬高風險**，須先確認。
4. **驗證可見性**：授權後告知使用者「IAM 變更約 1–2 分鐘生效，token 會自動帶新權限」，必要時重抓憑證。

---

## 標準操作

### 授予角色
```bash
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member=user:<email> --role=roles/<role> --condition=None
```

### 檢視角色實際權限（授權前務必驗證）
```bash
gcloud iam roles describe roles/<role> --format="value(includedPermissions)"
```

### 建立最小自訂角色
```bash
gcloud iam roles create <roleId> --project=<PROJECT_ID> \
  --title=<Title_no_spaces> --description=<Desc_no_spaces> \
  --permissions=<perm1>,<perm2> --stage=GA
```
> ⚠️ 透過 gcloud-mcp 執行時，`--title` / `--description` **不可含空格**（會被再次切詞而報 UnrecognizedArgumentsError），用底線代替。

### 檢視目前綁定
```bash
gcloud projects get-iam-policy <PROJECT_ID> --format=json
```

---

## 授權範本（references/）

| 場景 | 範本檔 |
|------|--------|
| GKE 唯讀（含 `kubectl logs` / k9s 看 log 的 getLogs 踩坑） | `references/gke-readonly.md` |

> 未來新增 Cloud SQL、Storage、Pub/Sub 等授權範本時，於此表登錄並新增對應 reference 檔。

---

## Service Mesh（Cloud Service Mesh）相關 IAM

| 模式 | 需要的 IAM | 說明 |
|------|-----------|------|
| **sidecar（managed CSM）** | **不需 per-workload IAM** | 注入的 Envoy 由託管控制平面認證；fleet Workload Identity 在 membership 的 `authority{issuer}` 設定（Terraform `google_gke_hub_membership`），非逐 workload 授權 |
| **proxyless gRPC（xDS）** | `roles/trafficdirector.client` | 授予 Pod 的 KSA 對應 Workload Identity principal：`principal://iam.googleapis.com/projects/<NUM>/locations/global/workloadIdentityPools/<PROJECT_ID>.svc.id.goog/subject/ns/<NS>/sa/<KSA>` |

```bash
# proxyless client 授權範例（WI principal 直綁，免建 GSA）
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --role=roles/trafficdirector.client \
  --member="principal://iam.googleapis.com/projects/<PROJECT_NUM>/locations/global/workloadIdentityPools/<PROJECT_ID>.svc.id.goog/subject/ns/<NS>/sa/<KSA>"
```

---

## 通用排錯

- **`Forbidden` 報缺某 `*.get*` 權限** → 用 `roles describe` 確認現有角色不含該權限，建最小自訂角色補上（勿直接升級到含寫入的大角色）。
- **K8s / GKE 的 `kubectl` 報 Forbidden** → 注意 GCP **Cloud IAM ↔ K8s RBAC** 映射：`gcloud logging`/`roles/logging.viewer` 對 `kubectl logs` **無效**，因為授權路徑不同（kubectl 打 K8s API server 的子資源）。詳見 `references/gke-readonly.md`。
- **剛授權仍 Forbidden** → IAM 1–2 分鐘生效；可請對方重抓憑證 `gcloud container clusters get-credentials ...` 或重新登入刷新 token。
- **想用 IAM condition 讓使用者「只看得到部分 bucket」→ 不可行（實測 2026-07）**：
  `storage.buckets.list` 是對「專案」求值，任何 `resource.name.startsWith("projects/_/buckets/<prefix>")`
  條件在列表求值時永遠不成立 → **整個列表被拒**，Console 直接報「缺少 storage.buckets.list」。
  條件式授權只對**單一資源**操作有效（`buckets.get`、`objects.*`）。GCS 沒有「條件式列表過濾」。
  可行的兩種取捨：① 無條件給 `buckets.list/get`（名稱全可見，內容仍鎖 per-bucket object 權限）；
  ② 完全不給列表，條件式只給 `buckets.get` + object 權限，使用者靠書籤直達
  `console.cloud.google.com/storage/browser/<bucket>`（列表頁會一直顯示權限錯誤，UX 差）。
