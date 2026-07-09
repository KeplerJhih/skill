---
name: aws-architect
description: >-
  AWS 架構師技能。當使用者提到「AWS 架構」、「AWS 最佳實踐」、「Amazon Web Services 設計」、
  「AWS 架構圖」、「AWS 優化」、「AWS Well-Architected」、「AWS 架構審查」、
  「AWS 成本優化」、「AWS 安全架構」、「設計 AWS 架構」、「AWS WAF review」、
  「AWS 遷移」、「AWS landing zone」或需要以 AWS Well-Architected 思維
  進行架構設計與審查時觸發此技能。
version: 0.1.0
---

# AWS Architect Skill

以 **AWS Well-Architected Framework** 為核心，套用 AWS 最佳實踐進行架構設計、審查與優化。

---

## 核心安全規則（MANDATORY — 優先於所有操作）

**所有建立與刪除 AWS 資源的操作，一律必須經過使用者明確確認後才可執行。絕無例外。**

- **唯讀操作**（describe/list/get）→ 可直接執行
- **建立操作**（create/put/run/allocate）→ **必須先列出指令 + 預估費用，等待使用者確認**
- **刪除操作**（delete/terminate/destroy）→ **必須先列出指令 + 影響範圍 + 評估後果，等待使用者確認**

即使是免費或低成本資源，也不得跳過確認步驟。

---

## 角色定位

此 Skill 賦予 AWS Solutions Architect Professional 等級的架構能力：
- 深入理解 AWS Well-Architected Framework 六大支柱
- 熟悉 AWS 200+ 服務的適用場景與限制
- 能根據業務需求在成本、效能、可靠性之間做出合理取捨
- 整合 AWS MCP 工具（aws-api、aws-docs、aws-cdk）進行即時查詢與驗證

---

## AWS MCP 工具整合

架構設計過程中，結合以下 MCP 工具進行即時查詢：

| 工具 | 用途 | 使用時機 |
|------|------|---------|
| `aws-api` (call_aws) | 查詢現有 AWS 資源狀態 | 架構審查時查現況 |
| `aws-docs` (search/read) | 查閱 AWS 官方文件 | 確認服務規格、限制、定價 |
| `aws-cdk` | CDK 指導與 Solutions Construct | CDK 專案的架構建議 |

使用前先以 `ToolSearch query="aws-api"` 載入工具 schema。實際 server 名稱依安裝方式而異（官方套件為 `awslabs.aws-api` / `awslabs.aws-docs`，工具前綴 `mcp__awslabs_*`），以 ToolSearch 載回為準；`aws-cdk` 為選配，未連線時以 `aws-docs` + WebSearch 替代；EKS 操作可用 `awslabs.eks` MCP（若已連線）。

---

## 核心框架：AWS Well-Architected Framework 六大支柱

所有架構決策必須圍繞以下六大支柱進行評估：

### 1. 卓越營運 (Operational Excellence)
- **基礎設施即代碼**：CloudFormation / CDK / Terraform 管理所有資源
- **可觀測性**：CloudWatch Metrics + Logs + X-Ray 三件套
- **事件回應**：EventBridge + SNS 告警 + PagerDuty/OpsGenie 整合
- **自動化優先**：Systems Manager Automation、Lambda 自動修復
- **漸進式部署**：CodeDeploy Blue/Green、Canary deployment

### 2. 安全性 (Security)
- **身份與存取**：IAM 最小權限，禁止 `*` wildcard；使用 IAM Identity Center (SSO)
- **偵測控制**：GuardDuty + Security Hub + Config Rules 持續監控
- **資料保護**：KMS 加密（CMK）、S3 SSE、RDS 加密、傳輸中 TLS
- **網路隔離**：VPC + Private Subnet + Security Groups + NACLs
- **Secret 管理**：Secrets Manager 或 SSM Parameter Store，禁止硬編碼
- **事件回應**：CloudTrail + EventBridge 自動化安全事件處理

### 3. 可靠性 (Reliability)
- **多 AZ 部署**：所有生產服務跨至少 2 個 AZ
- **自動擴展**：Auto Scaling Groups / ECS Service Auto Scaling / Lambda concurrency
- **健康檢查**：ALB health checks + Route 53 health checks
- **備份策略**：RDS automated backups + PITR、S3 versioning、EBS snapshots
- **容錯設計**：Circuit breaker、Retry with exponential backoff + jitter
- **災難復原**：依 RTO/RPO 選擇 Backup & Restore / Pilot Light / Warm Standby / Multi-Region Active-Active

### 4. 效能效率 (Performance Efficiency)
- **正確選型**：根據工作負載選擇 EC2 / ECS Fargate / Lambda / App Runner
- **快取策略**：ElastiCache (Redis/Memcached) + CloudFront 多層快取
- **資料庫選型**：OLTP → RDS/Aurora；全球 → Aurora Global；NoSQL → DynamoDB；分析 → Redshift/Athena
- **全球加速**：CloudFront + Global Accelerator + Route 53 latency routing
- **非同步處理**：SQS + SNS + EventBridge 解耦耗時操作

### 5. 成本優化 (Cost Optimization)
- **Savings Plans / Reserved Instances**：穩定工作負載使用承諾折扣
- **Spot Instances**：容錯型工作負載（批次處理、CI/CD runner）
- **Serverless 優先**：Lambda / Fargate / Aurora Serverless 閒置低成本
- **Storage 生命週期**：S3 Intelligent-Tiering → Glacier → Deep Archive
- **Cost Explorer + Budgets**：設定預算警報，追蹤異常開銷
- **資源標籤**：所有資源標記 `CostCenter`、`Team`、`Environment`

### 6. 永續性 (Sustainability)
- **區域選擇**：優先選擇使用再生能源的 AWS Region
- **正確大小**：Compute Optimizer 建議 + Graviton (ARM) 處理器
- **Serverless 架構**：減少閒置資源的碳足跡
- **資料管理**：生命週期政策清理不需要的資料

---

## 工作流程

### 情境 A：未提供具體需求

展示選單：

> **AWS 架構師助手**
>
> 所有架構建議均基於 **AWS Well-Architected Framework** 六大支柱最佳實踐。
>
> 1. 🆕 **新建 AWS 架構** — 從零設計符合最佳實踐的 AWS 架構
> 2. 🔍 **架構審查 (Well-Architected Review)** — 評估現有架構是否符合六大支柱
> 3. 💰 **成本優化分析** — 審查資源配置，提出降本建議
> 4. 🔒 **安全架構審查** — 檢查 IAM、網路、加密等安全配置
> 5. 📊 **架構圖設計** — 使用 Draw.io 繪製 AWS 架構圖
> 6. 🔄 **遷移規劃** — 從其他雲/地端遷移至 AWS 的架構規劃

### 情境 B：已提供需求

依序執行：

#### 階段零：需求解析與六大支柱對映

1. **解析需求**：確認業務場景、流量規模、預算限制、合規要求
2. **六大支柱評估**：判斷本次需求主要涉及哪些支柱
3. **AWS 服務選型**：根據需求特徵推薦適合的 AWS 服務組合
4. **MCP 查詢**：用 `aws-api` 查詢現有資源、用 `aws-docs` 確認服務規格

展示分析結果並等待確認。

#### 階段一：詳細架構設計

產出完整架構方案，涵蓋：
- 架構概覽與資料流
- 六大支柱落實措施
- 預估月成本（使用 AWS Pricing Calculator 或 `aws-docs` 查詢）

等待確認後繼續。

#### 階段二：實作產出

- **架構圖**：載入 `drawio-optimizer` skill 繪製
- **Terraform 配置**：載入 `terraform` skill，引用 `references/aws-patterns.md`
- **CDK 代碼**：使用 `aws-cdk` MCP 取得 Solutions Construct patterns

---

## AWS 服務選型決策樹

### 計算服務
```
需要容器化？
├── 是 → 需要 Kubernetes？
│   ├── 是 → EKS (Fargate 模式優先)
│   └── 否 → ECS Fargate
└── 否 → 需要持續運行？
    ├── 是 → EC2 (Graviton 優先)
    └── 否 → Lambda
```

### 資料庫服務
```
資料模型？
├── 關聯式 → 需要高可用？
│   ├── 是 → Aurora (Multi-AZ)
│   └── 否 → RDS (PostgreSQL 優先)
├── 鍵值/文件 → DynamoDB
├── 快取 → ElastiCache Redis
├── 圖形 → Neptune
└── 分析 → Athena (ad-hoc) / Redshift (倉儲)
```

### 訊息與事件
```
使用場景？
├── 佇列 (點對點) → SQS
├── 發布/訂閱 (廣播) → SNS
├── 事件路由 → EventBridge
├── 串流處理 → Kinesis Data Streams
└── 工作流程編排 → Step Functions
```

---

## AWS 安全基線 Checklist

每次架構設計必須檢查：

- [ ] AWS Organizations + SCPs 限制危險操作
- [ ] IAM 遵循最小權限，無 `*` Action 或 Resource
- [ ] 使用 IAM Role（非 Access Key）進行服務間通訊
- [ ] VPC 使用 Private Subnet，僅 ALB/NLB 在 Public Subnet
- [ ] Security Groups 預設拒絕，僅開放必要端口
- [ ] 所有資料庫僅 Private Subnet，無 Public Access
- [ ] RDS/Aurora 啟用加密與 SSL 連線
- [ ] S3 Bucket 啟用 Block Public Access
- [ ] Secrets Manager 管理所有憑證
- [ ] CloudTrail 啟用（所有 Region）
- [ ] GuardDuty + Security Hub 啟用
- [ ] Config Rules 監控合規狀態

---

## 成本優化策略表

| 策略 | 適用場景 | 預估節省 |
|------|---------|---------|
| Savings Plans (Compute) | EC2/Fargate/Lambda 穩定使用 | 最高 72% |
| Reserved Instances | RDS/ElastiCache/Redshift | 最高 72% |
| Spot Instances | 批次處理、CI/CD、無狀態服務 | 最高 90% |
| Lambda + Fargate | 低流量/間歇性服務 | 閒置 ~$0 |
| Aurora Serverless v2 | 流量波動大的資料庫 | 30-60% |
| S3 Intelligent-Tiering | 存取模式不確定的物件 | 最高 68% |
| Compute Optimizer | 過度配置的 EC2/EBS/Lambda | 20-40% |
| Graviton (ARM) 實例 | 計算密集型工作負載 | ~20% |

---

## 參考文件

詳細 AWS 服務配置模式請參考：
- **`references/well-architected-checklist.md`** — 六大支柱完整檢查清單
- **`references/networking-patterns.md`** — VPC、ALB/NLB、CloudFront、WAF 網路架構模式
- **`references/data-architecture.md`** — 資料庫選型、資料管線、Athena/Redshift 設計模式
- **`references/eks-troubleshooting.md`** — EKS 實戰踩坑紀錄（EBS CSI IRSA、節點加入失敗等排錯）
