# Registry References 索引

本目錄存放各 Image Registry 在 AWS CodeBuild buildspec 中的差異實作片段。

主檔 `../jenkinsfile-codebuild.md` 提供共通骨架，本目錄補完各 registry 的具體段落（secrets-manager 結構、login 指令、endpoint 格式、tag/push 片段）。

---

## 選擇 Registry 的決策原則

| 部署目標 | 推薦 Registry | 理由 |
|---------|--------------|------|
| GCP GKE | GCP Artifact Registry | 同雲，內網拉取最快、無跨雲流量費 |
| Aliyun ACK | Aliyun ACR | 同雲，內網拉取最快、無跨雲流量費 |
| AWS EKS / ECS | AWS ECR | 同雲，免跨雲流量費；IAM role 整合最簡單 |
| 多雲 / 不確定 | 依「主要部署目標」選 | 跨雲拉取走 public，計入流量費 |

---

## 跨雲注意事項

當 AWS CodeBuild push 到 **非 AWS** 的 registry（例：CodeBuild → Aliyun ACR / GCP AR）時：

- 一律走 **public endpoint**，VPC 內網 endpoint（如 `registry-vpc.*`、`internal.*`）僅在同雲 VM/Pod 可達
- 流量計入 CodeBuild 的 outbound traffic（建議估算後再決定是否要 cross-cloud build）
- CodeBuild IAM role 需有 `secretsmanager:GetSecretValue` 權限存取對應 registry 的 secret

---

## 各 Registry 差異點對照表

| 項目 | GCP Artifact Registry | Aliyun ACR | AWS ECR |
|------|----------------------|-----------|---------|
| Secret 結構 | 單 JSON key（SA key）| username + password 雙 key | 不需 secret（用 IAM role）|
| Login 指令 | `_json_key` stdin | username/password stdin | `aws ecr get-login-password` |
| Public Endpoint | `<region>-docker.pkg.dev` | `registry.<region>.aliyuncs.com` | `<account>.dkr.ecr.<region>.amazonaws.com` |
| Internal Endpoint | （N/A，內外網同一個）| `registry-vpc.<region>.aliyuncs.com` | （N/A，內外網同一個，靠 IAM 限制）|
| Repo 命名 | `<project-id>/<repo>/<image>` | `<namespace>/<image>` | `<image>`（無 namespace 層）|
| 預設 tag 不可變 | 否 | 否（企業版可開啟）| 可設定為 IMMUTABLE |

---

## 新增 Registry 流程

1. 在本目錄新增 `<registry-name>.md`，照既有檔案的六段結構填寫：
   1. AWS Secrets Manager 結構
   2. Buildspec env 區段
   3. Login 指令（pre_build）
   4. Build + Tag + Push（build）
   5. Endpoint 命名
   6. 網路與權限
2. 更新本檔的「決策原則」與「差異點對照表」
3. 更新主檔 `../jenkinsfile-codebuild.md` 的「Registry 具體實作」表
