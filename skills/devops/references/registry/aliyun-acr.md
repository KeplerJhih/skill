# Aliyun ACR — buildspec 差異實作

本檔補完主檔 `../jenkinsfile-codebuild.md` 的「通用骨架」中標記 `<<<REGISTRY>>>` 的段落。

---

## 1. AWS Secrets Manager 結構

建立一個 secret 存放 Aliyun ACR 的 docker 登入帳密：

| Secret 名稱（建議格式） | Keys |
|-----------------------|------|
| `aliyun_acr_<purpose>` | `ACR_USERNAME`, `ACR_PASSWORD` |

> **重要**：`ACR_USERNAME` / `ACR_PASSWORD` 在 Aliyun Console「容器鏡像服務 → 訪問憑證」設定，**不是 Aliyun 主帳號的登入密碼**。
> - 個人版 ACR：固定的「容器鏡像 docker 登入密碼」
> - 企業版 ACR：每個實例有獨立的固定密碼或臨時 token（建議用固定密碼存 Secrets Manager）

---

## 2. Buildspec env 區段

```yaml
env:
  secrets-manager:
    ACR_USERNAME: aliyun_acr_<purpose>:ACR_USERNAME
    ACR_PASSWORD: aliyun_acr_<purpose>:ACR_PASSWORD

  variables:
    ACR_REGION: "<region>"              # 例：cn-hongkong / ap-southeast-1 / cn-shanghai
    ACR_NAMESPACE: "<namespace>"
    ACR_REPO_NAME: "<namespace>/<image>"  # 例：mynamespace/backend-<service>

    SERVICE_NAME: "<service>"
    TAG_NAME: ""
    IMAGE_TAG: ""
```

---

## 3. Login 指令（pre_build）

```yaml
- echo "$ACR_PASSWORD" | docker login -u "$ACR_USERNAME" --password-stdin registry.${ACR_REGION}.aliyuncs.com
```

---

## 4. Build + Tag + Push（build）

`REPO` 完整路徑由變數組合：

```
registry.${ACR_REGION}.aliyuncs.com/$ACR_REPO_NAME
```

完整片段：

```yaml
- make build-${SERVICE_NAME} REPO=registry.${ACR_REGION}.aliyuncs.com/$ACR_REPO_NAME
- docker tag registry.${ACR_REGION}.aliyuncs.com/$ACR_REPO_NAME:latest registry.${ACR_REGION}.aliyuncs.com/$ACR_REPO_NAME:$TAG_NAME
- docker tag registry.${ACR_REGION}.aliyuncs.com/$ACR_REPO_NAME:latest registry.${ACR_REGION}.aliyuncs.com/$ACR_REPO_NAME:$IMAGE_TAG
- docker push registry.${ACR_REGION}.aliyuncs.com/$ACR_REPO_NAME:latest
- docker push registry.${ACR_REGION}.aliyuncs.com/$ACR_REPO_NAME:$TAG_NAME
- docker push registry.${ACR_REGION}.aliyuncs.com/$ACR_REPO_NAME:$IMAGE_TAG
```

---

## 5. Endpoint 命名

| 用途 | Endpoint | 何時用 |
|------|----------|--------|
| Public（外網） | `registry.<region>.aliyuncs.com` | AWS CodeBuild、本機開發、非 Aliyun VPC 環境 |
| VPC（內網） | `registry-vpc.<region>.aliyuncs.com` | Aliyun ECS / ACK 拉鏡像（**同 region** VPC 內可達）|
| 經典網路內網 | `registry-internal.<region>.aliyuncs.com` | 經典網路（已淘汰，新專案勿用）|

完整 endpoint 格式：

```
registry.<region>.aliyuncs.com/<namespace>/<image>
```

**重要**：AWS CodeBuild → Aliyun ACR **必須用 public endpoint** `registry.<region>.aliyuncs.com`，VPC 與 internal endpoint 僅 Aliyun 內部可達。

---

## 6. 網路與權限

- **跨雲流量**：AWS CodeBuild → Aliyun ACR 走 public 網路，跨雲 outbound 流量費由 CodeBuild 側計
- **Namespace 與 Repo 預先建立**：Aliyun ACR 可在 Console 開啟「自動建立 repository」省去手動建立；namespace 仍需先建立
- **ACK 端拉鏡像建議**：
  - 改用 `registry-vpc.<region>.aliyuncs.com`（同 region VPC 內網，免外網流量費）
  - 建議用 **`aliyun-acr-credential-helper`** 自動續期 imagePullSecret（避免企業版臨時 token 過期）
- **個人版 vs 企業版差異**：
  - 個人版：訪問憑證固定不變
  - 企業版：可建立多組獨立 token，支援存取控制與 IP 白名單；建議生產環境用企業版
