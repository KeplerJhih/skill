# GKE 唯讀權限授予範本（含 pod log 踩坑）

授予某帳號「唯讀 GKE」時的標準組合與實戰踩坑。

## 核心踩坑

- `roles/container.viewer` 能 list / get / describe Pod 物件與其他 K8s 資源，但**不含 `container.pods.getLogs`**。
  → 因此 `kubectl logs`（或 k9s 看 log）會報：
  ```
  Error from server (Forbidden): pods "<pod>" is forbidden:
  User "<email>" cannot get resource "pods/log" in API group "" in the namespace "<ns>":
  requires one of ["container.pods.getLogs"] permission(s) in Cloud IAM or a Kubernetes RBAC role
  with verb "get" for resource "pods/log".
  ```
- `roles/logging.viewer` 只對 **Cloud Logging 主控台** 有效，對 `kubectl logs` **無效** —— 兩者授權路徑不同：
  - `kubectl logs` → 打 K8s API server 的 `pods/log` 子資源 → 由 Cloud IAM 映射的 RBAC 授權（需 `container.pods.getLogs`）。
  - Cloud Logging 主控台 → 讀 GCP Logging 後端（需 `roles/logging.viewer`）。
- 含 `getLogs` 的預設角色（如 `roles/container.developer`）會帶**寫入權限**，破壞唯讀原則。故採「`container.viewer` + 只含 `getLogs` 的自訂角色」最小權限組合。

## 角色對照

| 需求 | 需要的角色 | 說明 |
|------|-----------|------|
| 唯讀叢集 / K8s 物件（pods、deployments、services… list/get/describe） | `roles/container.viewer` | GKE 唯讀基礎 |
| `kubectl logs` / k9s 看 pod log | 自訂角色含 `container.pods.getLogs` | container.viewer **不含**，須額外補 |
| Cloud Logging 主控台看歷史 / container log | `roles/logging.viewer` | 走 Cloud Logging，非 K8s API |

## 標準設定流程（全唯讀）

```bash
PROJECT=<project-id>
MEMBER=user:<email>

# 1. GKE 唯讀基礎
gcloud projects add-iam-policy-binding $PROJECT \
  --member=$MEMBER --role=roles/container.viewer --condition=None

# 2. 建立「只含 getLogs」的自訂角色（首次建立，之後可重用）
#    注意：透過 gcloud-mcp 執行時，--title/--description 不可含空格（會被再次切詞），用底線代替
gcloud iam roles create gkePodLogViewer --project=$PROJECT \
  --title=GKE_Pod_Log_Viewer --description=Readonly_pod_logs \
  --permissions=container.pods.getLogs --stage=GA

# 3. 綁定自訂角色 → 讓 kubectl logs / k9s 可看 log
gcloud projects add-iam-policy-binding $PROJECT \
  --member=$MEMBER --role=projects/$PROJECT/roles/gkePodLogViewer --condition=None

# 4.（選用）Cloud Logging 主控台唯讀
gcloud projects add-iam-policy-binding $PROJECT \
  --member=$MEMBER --role=roles/logging.viewer --condition=None
```

## 驗證 / 排錯

- 確認角色不含 getLogs（佐證為何要自訂角色）：
  ```bash
  gcloud iam roles describe roles/container.viewer --format="value(includedPermissions)"
  ```
- 若 `kubectl logs` 仍 `Forbidden` → 確認步驟 2、3 已執行；IAM 變更約 1–2 分鐘生效，token 會自動帶新權限，必要時重抓憑證：
  ```bash
  gcloud container clusters get-credentials <cluster> --project $PROJECT --region <region>
  ```
- **k9s log 畫面空白但無紅字** → 多半不是權限問題，而是只 tail 當下之後的 log：進 log 畫面按 `0` 載入全部歷史、按 `a` 切換所有容器、按 `s` 開關 autoscroll。
- 對方查 log 的兩種方式：
  - kubectl（即時）：`kubectl logs <pod> -n <ns> --tail=100`
  - Cloud Logging（含歷史）：Logs Explorer filter `resource.type="k8s_container"` + `resource.labels.project_id="<project-id>"`
