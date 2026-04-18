# AWS Well-Architected Framework — 六大支柱完整檢查清單

此文件提供每個支柱的詳細審查項目，供架構審查時逐項確認。

---

## 1. 卓越營運 (Operational Excellence)

### 組織
- [ ] 團隊了解工作負載的業務優先順序
- [ ] 已定義 Runbook（標準操作程序）與 Playbook（故障排除指南）
- [ ] 已建立回饋機制，持續改進流程

### 準備
- [ ] 工作負載使用 IaC 管理（CloudFormation / CDK / Terraform）
- [ ] CI/CD 管線已建立（CodePipeline / GitHub Actions / GitLab CI）
- [ ] 部署策略已定義（Blue/Green、Canary、Rolling）
- [ ] 變更管理流程已建立（Code Review、Approval Gate）

### 運營
- [ ] CloudWatch Dashboards 已建立，涵蓋關鍵業務指標
- [ ] CloudWatch Alarms 已設定（CPU、記憶體、延遲、錯誤率、5xx）
- [ ] X-Ray 追蹤已啟用（分散式系統）
- [ ] CloudWatch Logs 已集中收集，設定保留期限
- [ ] Systems Manager OpsCenter 用於事件追蹤
- [ ] 已定義 On-call 輪值與升級流程

### 演進
- [ ] 定期執行 Game Day（故障演練）
- [ ] 事後分析 (Post-mortem) 流程已建立
- [ ] 持續優化自動化覆蓋率

---

## 2. 安全性 (Security)

### 身份與存取管理
- [ ] 啟用 AWS Organizations + SCPs
- [ ] 使用 IAM Identity Center (SSO) 集中管理人員存取
- [ ] IAM Policy 遵循最小權限，無 `*` wildcard
- [ ] 禁止使用 root 帳號，已啟用 MFA
- [ ] 所有 IAM User 已啟用 MFA
- [ ] 服務間通訊使用 IAM Role，非 Access Key
- [ ] 定期審查 IAM Access Analyzer 報告
- [ ] 未使用的 IAM User/Role/Policy 已清理

### 偵測控制
- [ ] CloudTrail 啟用（所有 Region + 組織層級）
- [ ] CloudTrail Logs 存入專用 S3 Bucket（啟用 MFA Delete）
- [ ] GuardDuty 啟用
- [ ] Security Hub 啟用，整合合規標準（CIS、PCI DSS）
- [ ] Config Rules 監控關鍵合規項目
- [ ] VPC Flow Logs 啟用

### 基礎設施保護
- [ ] VPC 使用多層網路架構（Public / Private / Isolated Subnet）
- [ ] Security Groups 僅開放必要端口（非 0.0.0.0/0）
- [ ] NACLs 作為額外防護層
- [ ] WAF 保護 ALB / CloudFront / API Gateway
- [ ] Shield Advanced 用於 DDoS 保護（高價值目標）
- [ ] Systems Manager Session Manager 替代 SSH Bastion

### 資料保護
- [ ] S3 啟用 Block Public Access（帳號層級）
- [ ] S3 Bucket Policy 限制存取
- [ ] 靜態加密：S3 SSE-KMS、RDS/Aurora 加密、EBS 加密
- [ ] 傳輸加密：ALB/CloudFront 強制 HTTPS、RDS SSL
- [ ] Secrets Manager 管理資料庫密碼與 API Key
- [ ] SSM Parameter Store (SecureString) 管理配置
- [ ] KMS Key Rotation 已啟用
- [ ] Macie 用於 S3 敏感資料偵測（如需合規）

### 事件回應
- [ ] 安全事件回應計畫已文件化
- [ ] EventBridge + Lambda 自動化安全回應（如自動隔離受影響 EC2）
- [ ] 安全事件通知管道已建立（SNS → Slack/PagerDuty）

---

## 3. 可靠性 (Reliability)

### 基礎設施
- [ ] Service Quotas 已審查並申請提升（如需要）
- [ ] 網路拓撲支援多 AZ（至少 2 個 AZ）
- [ ] VPC CIDR 規劃預留擴展空間
- [ ] DNS 使用 Route 53（啟用 Health Checks）

### 工作負載架構
- [ ] 無狀態設計，Session 存於 ElastiCache/DynamoDB
- [ ] 使用 Elastic Load Balancing 分散流量
- [ ] Auto Scaling 已配置（Target Tracking 優先）
- [ ] 服務間使用非同步通訊（SQS/SNS/EventBridge）
- [ ] 實作 Circuit Breaker 模式
- [ ] Retry with exponential backoff + jitter
- [ ] 設定合理的 Timeout

### 變更管理
- [ ] 變更透過 CI/CD 部署，非手動操作
- [ ] 部署支援自動回滾（CodeDeploy Rollback）
- [ ] 使用 Feature Flags 控制新功能發布

### 故障管理
- [ ] RDS/Aurora 啟用 Automated Backups + PITR
- [ ] S3 啟用 Versioning
- [ ] EBS Snapshots 定期備份（AWS Backup）
- [ ] 已定義 RTO/RPO 目標
- [ ] DR 策略已實作並定期演練
- [ ] 多 Region 備援（依 RTO 需求）

---

## 4. 效能效率 (Performance Efficiency)

### 選型
- [ ] 計算服務選型合理（EC2 vs ECS vs Lambda vs App Runner）
- [ ] EC2 實例類型與工作負載匹配（Compute Optimizer 建議）
- [ ] 優先使用 Graviton (ARM) 實例
- [ ] 資料庫選型合理（OLTP vs OLAP vs NoSQL vs Cache）
- [ ] 儲存類型匹配 IOPS/吞吐量需求

### 快取
- [ ] CloudFront CDN 用於靜態資源與 API 回應快取
- [ ] ElastiCache 用於應用層快取（Session、熱資料）
- [ ] DAX 用於 DynamoDB 快取（如需要）
- [ ] API Gateway Caching（如適用）

### 網路
- [ ] 使用 VPC Endpoints 存取 AWS 服務（避免走 Internet）
- [ ] Global Accelerator 用於全球低延遲存取
- [ ] Route 53 Latency-based Routing（多 Region 場景）
- [ ] Enhanced Networking 已啟用（ENA / EFA）

### 監控與調優
- [ ] CloudWatch 自訂 Metrics 涵蓋業務關鍵指標
- [ ] X-Ray 追蹤端到端延遲瓶頸
- [ ] 定期執行負載測試
- [ ] Auto Scaling 政策經過調優（Cooldown、Step Scaling）

---

## 5. 成本優化 (Cost Optimization)

### 支出感知
- [ ] AWS Budgets 已設定（每月預算 + 異常告警）
- [ ] Cost Explorer 定期審查
- [ ] 所有資源已標記 Cost Allocation Tags
- [ ] 使用 AWS Organizations 整合帳單

### 資源規模
- [ ] Compute Optimizer 建議已審查
- [ ] 無閒置資源（未使用的 EC2、EBS、EIP、NAT Gateway）
- [ ] 開發/測試環境使用排程停機（Instance Scheduler）
- [ ] Lambda 記憶體配置已調優（Power Tuning）

### 購買選項
- [ ] 穩定工作負載使用 Savings Plans 或 Reserved Instances
- [ ] 容錯工作負載使用 Spot Instances
- [ ] RDS/ElastiCache 使用 Reserved Instances

### 儲存優化
- [ ] S3 啟用 Intelligent-Tiering 或 Lifecycle Policy
- [ ] EBS 類型匹配需求（gp3 vs io2 vs st1）
- [ ] 過期 EBS Snapshots 已清理
- [ ] CloudWatch Logs 設定保留期限（非無限保留）

---

## 6. 永續性 (Sustainability)

### 區域選擇
- [ ] 優先使用碳強度較低的 AWS Region
- [ ] 已查閱 AWS Customer Carbon Footprint Tool

### 資源效率
- [ ] 使用 Graviton 處理器（更佳能效比）
- [ ] Serverless 架構最大化利用率
- [ ] Auto Scaling 避免過度配置
- [ ] 容器化工作負載提升資源利用率

### 資料管理
- [ ] S3 Lifecycle Policy 清理不需要的資料
- [ ] CloudWatch Logs 設定合理保留期
- [ ] 資料壓縮已啟用（S3、CloudWatch）

### 軟體優化
- [ ] 使用最新 Runtime 版本（Lambda、EC2 AMI）
- [ ] 程式碼效能已優化，減少不必要的運算
- [ ] 使用 Managed Services 替代自建（減少維運開銷）
