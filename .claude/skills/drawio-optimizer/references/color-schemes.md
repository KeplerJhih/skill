# Draw.io 配色規範

## 通用架構配色（預設）

適用於非特定雲端平台的架構圖、流程圖、系統圖等。

| 層級 | 填色 | 邊框色 | 字色 |
|------|------|--------|------|
| 使用者 / 外部 | `#E8F5E9` | `#43A047` | `#1B5E20` |
| 網路 / Gateway | `#E3F2FD` | `#1E88E5` | `#0D47A1` |
| 服務 / 應用 | `#FFF3E0` | `#FB8C00` | `#E65100` |
| 資料 / 儲存 | `#F3E5F5` | `#8E24AA` | `#4A148C` |
| 安全 / 認證 | `#FFEBEE` | `#E53935` | `#B71C1C` |
| 監控 / 日誌 | `#F5F5F5` | `#757575` | `#212121` |
| 訊息 / 佇列 | `#E0F7FA` | `#00ACC1` | `#006064` |

**原則**：同層級同色系，不同層級不同色系，一眼辨識架構分層。

---

## GCP 架構圖配色

繪製 GCP 架構圖時，使用以下 GCP 官方色系（覆蓋通用配色）：

| 層級 | 填色 | 邊框色 | 用途 |
|------|------|--------|------|
| 使用者 / 外部 | `#E8F5E9` | `#43A047` | 客戶端、第三方服務 |
| 網路層 | `#E3F2FD` | `#1E88E5` | Load Balancer、CDN、DNS、VPC、Cloud NAT |
| 計算層 | `#FFF3E0` | `#FB8C00` | Cloud Run、GKE、Compute Engine |
| 資料層 | `#F3E5F5` | `#8E24AA` | Cloud SQL、Firestore、Cloud Storage、Artifact Registry |
| 安全 / IAM | `#FFEBEE` | `#E53935` | IAM、Secret Manager、VPC SC、Cloud Armor、IAP |
| 監控 / 營運 | `#F5F5F5` | `#757575` | Cloud Monitoring、Cloud Logging、Cloud Trace |

---

## AWS 架構圖配色

繪製 AWS 架構圖時，使用以下 AWS 官方色系（覆蓋通用配色）：

| 層級 | 填色 | 邊框色 | 用途 |
|------|------|--------|------|
| 使用者 / 外部 | `#E8F5E9` | `#43A047` | 客戶端、第三方服務 |
| 網路層 | `#EDE7F6` | `#7B1FA2` | VPC、ALB/NLB、CloudFront、Route 53 |
| 計算層 | `#FFF3E0` | `#FB8C00` | EC2、ECS、Lambda、EKS |
| 資料層 | `#E3F2FD` | `#1E88E5` | RDS、DynamoDB、S3、ElastiCache |
| 安全 / IAM | `#FFEBEE` | `#E53935` | IAM、WAF、Secrets Manager、KMS |
| 監控 / 營運 | `#F5F5F5` | `#757575` | CloudWatch、X-Ray、CloudTrail |
