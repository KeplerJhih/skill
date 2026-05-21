# GCP Artifact Registry — buildspec 差異實作

本檔補完主檔 `../jenkinsfile-codebuild.md` 的「通用骨架」中標記 `<<<REGISTRY>>>` 的段落。

---

## 1. AWS Secrets Manager 結構

建立一個 secret 存放 GCP Service Account 的 JSON key：

| Secret 名稱（建議格式） | Key | 值 |
|-----------------------|-----|----|
| `gcp_<purpose>_artifact` | `GCP_SA_KEY` | Service Account JSON 完整內容（單行 escaped）|

> Secret 名稱可依組織規則調整，**但同組織內保持一致命名慣例**，避免不同專案各自取名。

---

## 2. Buildspec env 區段

```yaml
env:
  secrets-manager:
    GCP_SA_KEY: gcp_<purpose>_artifact:GCP_SA_KEY

  variables:
    GCP_REGION: "<region>"              # 例：asia-southeast1 / asia-east1 / us-central1
    GCP_PROJECT_ID: "<gcp-project-id>"
    GCP_REPO_NAME: "<repo>/<image>"     # 例：myteam/backend-<service>

    SERVICE_NAME: "<service>"
    TAG_NAME: ""
    IMAGE_TAG: ""
```

---

## 3. Login 指令（pre_build）

```yaml
- echo "$GCP_SA_KEY" | docker login -u _json_key --password-stdin https://${GCP_REGION}-docker.pkg.dev
```

---

## 4. Build + Tag + Push（build）

`REPO` 完整路徑由變數組合：

```
${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME
```

完整片段：

```yaml
- make build-${SERVICE_NAME} REPO=${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME
- docker tag ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:latest ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:$TAG_NAME
- docker tag ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:latest ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:$IMAGE_TAG
- docker push ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:latest
- docker push ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:$TAG_NAME
- docker push ${GCP_REGION}-docker.pkg.dev/$GCP_PROJECT_ID/$GCP_REPO_NAME:$IMAGE_TAG
```

---

## 5. Endpoint 命名

| Region | Endpoint |
|--------|----------|
| asia-east1 | `asia-east1-docker.pkg.dev` |
| asia-southeast1 | `asia-southeast1-docker.pkg.dev` |
| asia-northeast1 | `asia-northeast1-docker.pkg.dev` |
| us-central1 | `us-central1-docker.pkg.dev` |
| europe-west1 | `europe-west1-docker.pkg.dev` |

完整 endpoint 格式：

```
<region>-docker.pkg.dev/<gcp-project-id>/<repo>/<image>
```

GCP AR **內外網共用同一個 endpoint**，靠 SA 權限與 VPC Service Controls 控管存取。

---

## 6. 網路與權限

- **跨雲流量**：AWS CodeBuild → GCP AR 走 public 網路，跨雲 outbound 流量費由 CodeBuild 側計
- **SA 權限**：用於 push 的 SA 需有 `roles/artifactregistry.writer`；只 pull 用 `roles/artifactregistry.reader`
- **替代驗證方式**：若 CodeBuild 已在 GCP 環境（罕見），改用 Workload Identity Federation（WIF）+ `roles/iam.workloadIdentityUser` 替代 SA JSON key 更安全（不需存 secret）
- **Repo 預先建立**：GCP AR 預設**不自動建立 repo**，首次 push 前需在 Console 或用 `gcloud artifacts repositories create` 建好
