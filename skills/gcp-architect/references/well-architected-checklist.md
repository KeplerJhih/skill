# GCP Well-Architected Review Checklist

五大支柱完整檢查清單，用於架構審查。

---

## 1. 卓越營運 (Operational Excellence)

### CI/CD
- [ ] 使用 Cloud Build / GitHub Actions 自動化建置與部署
- [ ] 部署流水線包含：lint → test → build → staging deploy → prod deploy
- [ ] 生產環境部署使用 Canary 或 Blue-Green 策略
- [ ] Rollback 機制已就位且經過測試

### 監控與可觀測性
- [ ] Cloud Monitoring 已啟用，關鍵指標已設定 Dashboard
- [ ] Cloud Logging 已啟用，日誌已設定保留策略
- [ ] Cloud Trace 已啟用（分散式追蹤）
- [ ] 自定義指標覆蓋業務關鍵路徑
- [ ] Uptime Checks 覆蓋所有外部端點

### 告警
- [ ] Alerting Policies 覆蓋：錯誤率、延遲、飽和度、流量
- [ ] 告警通知管道已設定（Email / Slack / PagerDuty）
- [ ] 嚴重等級分類（P1-P4）已定義
- [ ] On-call 輪值已建立

### 基礎設施管理
- [ ] 所有資源使用 Terraform / IaC 管理
- [ ] 資源變更透過 PR Review + Plan 審核
- [ ] 環境分離（dev / staging / prod）

---

## 2. 安全性 (Security)

### 身份與存取
- [ ] 使用 Workload Identity（GKE）或 Service Account 而非 Key File
- [ ] IAM 遵循最小權限，無 `roles/editor` 或 `roles/owner` 授予 SA
- [ ] 定期審查 IAM Policy，移除不必要權限
- [ ] MFA 啟用於所有人員帳號

### 網路安全
- [ ] VPC 使用自訂模式（非 auto mode）
- [ ] Private Google Access 啟用
- [ ] Cloud NAT 用於私有子網出站
- [ ] VPC Service Controls 保護敏感 API
- [ ] Cloud Armor 保護外部 Load Balancer（WAF + DDoS）

### 資料保護
- [ ] 靜態加密：CMEK 用於敏感資料，其餘使用 Google-managed
- [ ] 傳輸加密：所有內外部通訊使用 TLS 1.2+
- [ ] Secret Manager 管理所有憑證
- [ ] DLP API 掃描敏感資料（若處理 PII）

### 合規與審計
- [ ] Audit Logs 啟用（Admin Activity + Data Access）
- [ ] Security Command Center 啟用
- [ ] Organization Policy 已設定限制
- [ ] 定期執行滲透測試

---

## 3. 可靠性 (Reliability)

### 高可用
- [ ] 計算資源跨多可用區部署
- [ ] 資料庫使用 Regional（跨 AZ）配置
- [ ] Load Balancer 前端流量分發
- [ ] 無單點故障（SPOF）

### 擴展性
- [ ] Autoscaling 已配置（HPA / Cloud Run scaling）
- [ ] 擴展上限合理設定，避免成本失控
- [ ] 資料庫連線池已配置

### 備份與災難恢復
- [ ] 資料庫自動備份啟用
- [ ] PITR（Point-in-Time Recovery）啟用於生產環境
- [ ] RTO / RPO 已定義且 DR 方案已驗證
- [ ] 定期 DR 演練

### 容錯設計
- [ ] 服務間通訊實作 Retry + Exponential Backoff
- [ ] Circuit Breaker 保護下游服務
- [ ] Graceful Degradation 策略已定義
- [ ] Health Check 配置正確（startup / liveness / readiness）

---

## 4. 效能效率 (Performance Efficiency)

### 計算
- [ ] 工作負載類型匹配正確的計算服務
- [ ] Machine Type 根據實際用量選擇（非過度配置）
- [ ] CPU/Memory 使用率監控已就位

### 資料庫
- [ ] 讀寫分離（Read Replica）用於讀取密集場景
- [ ] 連線池配置合理
- [ ] Query 效能監控已啟用
- [ ] 索引策略已優化

### 網路
- [ ] Cloud CDN 快取靜態資源
- [ ] Global Load Balancer 用於多區域部署
- [ ] Memorystore 快取熱點資料
- [ ] gRPC 用於服務間高頻通訊

### 非同步處理
- [ ] 耗時操作使用 Pub/Sub / Cloud Tasks 非同步處理
- [ ] 批次處理與即時處理分離

---

## 5. 成本優化 (Cost Optimization)

### 資源管理
- [ ] 所有資源已標記 labels（project、environment、team、cost-center）
- [ ] Billing Alerts 已設定
- [ ] 開發/測試環境下班時間自動關閉或縮減
- [ ] 未使用的資源定期清理

### 折扣與優惠
- [ ] 穩定工作負載已購買 CUD
- [ ] 容錯工作負載使用 Spot VM
- [ ] Cloud Run / Cloud Functions 設定 min=0（開發環境）

### 儲存優化
- [ ] Storage Lifecycle Policy 已設定（自動降級冷資料）
- [ ] 舊版本 / 舊備份自動清理
- [ ] BigQuery 使用分區表與叢集化

### 架構優化
- [ ] 服務粒度合理（非過度微服務化）
- [ ] 共用資源（如 VPC、NAT）跨服務共享
- [ ] Rightsizing Recommender 建議已審查
