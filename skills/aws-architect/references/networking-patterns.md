# AWS 網路架構模式

此文件涵蓋 AWS 常見網路架構模式，供架構設計時參考。

---

## 標準三層 VPC 架構

### CIDR 規劃

```
VPC: 10.0.0.0/16 (65,536 IPs)
├── Public Subnets (ALB/NAT Gateway)
│   ├── AZ-a: 10.0.1.0/24 (256 IPs)
│   ├── AZ-b: 10.0.2.0/24
│   └── AZ-c: 10.0.3.0/24
├── Private Subnets (Application)
│   ├── AZ-a: 10.0.11.0/24
│   ├── AZ-b: 10.0.12.0/24
│   └── AZ-c: 10.0.13.0/24
└── Isolated Subnets (Database)
    ├── AZ-a: 10.0.21.0/24
    ├── AZ-b: 10.0.22.0/24
    └── AZ-c: 10.0.23.0/24
```

### 路由設計

| Subnet 類型 | 路由目標 | 用途 |
|---|---|---|
| Public | Internet Gateway | ALB、NAT Gateway、Bastion (不建議) |
| Private | NAT Gateway | Application Server、ECS Tasks、Lambda (VPC) |
| Isolated | 無 Internet 路由 | RDS、ElastiCache、內部服務 |

### NAT Gateway 配置

- **生產環境**：每個 AZ 各 1 個 NAT Gateway（高可用）
- **開發環境**：單一 NAT Gateway（節省成本）
- **成本注意**：NAT Gateway 費用 = 時間費 + 資料處理費，可用 VPC Endpoints 減少

---

## VPC Endpoints

### Gateway Endpoints（免費）

| 服務 | Endpoint 類型 | 建議 |
|------|-------------|------|
| S3 | Gateway | **必裝** — 避免 NAT Gateway 費用 |
| DynamoDB | Gateway | **必裝** — 避免 NAT Gateway 費用 |

### Interface Endpoints（按需）

| 服務 | 常見場景 |
|------|---------|
| ECR (api + dkr) | ECS/EKS 拉取映像 |
| CloudWatch Logs | 日誌推送 |
| Secrets Manager | 密碼存取 |
| SQS / SNS | 訊息佇列 |
| STS | IAM Role 假設 |
| KMS | 加解密操作 |

**決策原則**：當服務的 NAT Gateway 資料傳輸費 > Interface Endpoint 費用時，使用 Endpoint。

---

## Load Balancer 選型

### ALB (Application Load Balancer)

```
適用場景：
- HTTP/HTTPS 流量
- 基於路徑/主機名路由
- WebSocket 支援
- gRPC 支援

典型配置：
- Listener: HTTPS:443 (ACM 憑證)
- Target Group: HTTP (容器/實例)
- Health Check: /health, interval 30s
- Idle Timeout: 60s (WebSocket 可調高)
- Access Logs → S3 Bucket
```

### NLB (Network Load Balancer)

```
適用場景：
- TCP/UDP 流量
- 極低延遲需求 (< 100μs)
- 靜態 IP / Elastic IP 需求
- 每秒數百萬連線

典型配置：
- Listener: TCP:443 (TLS termination 可選)
- Target Group: TCP (IP 或 Instance)
- Cross-zone load balancing: 按需開啟
- Preserve client IP: 預設啟用
```

### 選型決策

```
需要 HTTP 路由功能？(路徑/主機名/Header)
├── 是 → ALB
└── 否 → 需要極低延遲或靜態 IP？
    ├── 是 → NLB
    └── 否 → 需要 HTTP？
        ├── 是 → ALB
        └── 否 → NLB
```

---

## CloudFront CDN 模式

### 靜態網站 + API

```
CloudFront Distribution
├── Behavior 1: /api/* → ALB Origin (動態)
│   ├── Cache Policy: CachingDisabled
│   ├── Origin Request Policy: AllViewerExceptHostHeader
│   └── Response Headers Policy: CORS
├── Behavior 2: /static/* → S3 Origin (靜態)
│   ├── Cache Policy: CachingOptimized
│   ├── OAC (Origin Access Control)
│   └── TTL: 86400s
└── Default Behavior: S3 Origin (SPA index.html)
    ├── Cache Policy: CachingOptimized
    └── Custom Error Response: 403/404 → /index.html (SPA routing)
```

### CloudFront Functions vs Lambda@Edge

| 功能 | CloudFront Functions | Lambda@Edge |
|------|---------------------|-------------|
| 執行位置 | 所有 Edge | Regional Edge Cache |
| 延遲 | < 1ms | 5-30ms |
| 記憶體 | 2MB | 128-3008MB |
| 網路存取 | 否 | 是 |
| 適用 | URL rewrite、Header 操作 | 認證、A/B testing、SEO |
| 成本 | 極低 | 較高 |

---

## WAF (Web Application Firewall) 模式

### 推薦規則組合

```
WAF WebACL
├── AWS Managed Rules
│   ├── AWSManagedRulesCommonRuleSet (核心規則)
│   ├── AWSManagedRulesKnownBadInputsRuleSet (已知攻擊)
│   ├── AWSManagedRulesSQLiRuleSet (SQL 注入)
│   └── AWSManagedRulesLinuxRuleSet (Linux 漏洞，如適用)
├── Rate-based Rule
│   └── 單 IP 每 5 分鐘 > 2000 次 → Block
├── Geo Restriction (如需要)
│   └── 僅允許特定國家
└── Custom Rules (按需)
    └── Header / IP / URI 匹配
```

### 部署位置

| 資源 | 支援 WAF |
|------|---------|
| CloudFront | ✅（全球 Edge） |
| ALB | ✅（Regional） |
| API Gateway | ✅（Regional） |
| AppSync | ✅（Regional） |
| Cognito | ✅ |

---

## 多帳號網路架構 (AWS Organizations)

### Transit Gateway 模式

```
AWS Organizations
├── Network Account (Hub)
│   ├── Transit Gateway
│   ├── Shared VPC (共用服務：DNS、Proxy)
│   └── VPN / Direct Connect
├── Production Account
│   └── VPC → TGW Attachment
├── Staging Account
│   └── VPC → TGW Attachment
└── Development Account
    └── VPC → TGW Attachment
```

### 路由隔離

| 來源 | 目標 | 允許 |
|------|------|------|
| Prod → Shared | ✅ |
| Prod → Staging | ❌ |
| Prod → Dev | ❌ |
| Staging → Shared | ✅ |
| Dev → Shared | ✅ |

---

## DNS 模式 (Route 53)

### 常見路由策略

| 策略 | 適用場景 |
|------|---------|
| Simple | 單一資源 |
| Weighted | A/B testing、漸進式遷移 |
| Latency | 多 Region 最低延遲 |
| Failover | 主備切換（Active-Passive） |
| Geolocation | 依用戶地理位置路由 |
| Geoproximity | 依地理接近度 + bias 調整 |

### Private DNS

```
Route 53 Private Hosted Zone
├── 關聯至 VPC
├── 內部服務解析：api.internal.example.com → ALB
├── RDS 端點：db.internal.example.com → RDS Endpoint
└── 搭配 VPC Endpoints Private DNS
```

---

## 安全群組設計模式

### 分層引用（Security Group Chaining）

```
ALB Security Group (sg-alb)
├── Inbound: 0.0.0.0/0 → 443 (HTTPS)
└── Outbound: sg-app → Application Port

Application Security Group (sg-app)
├── Inbound: sg-alb → 8080 (僅接受 ALB)
└── Outbound: sg-db → 3306, sg-cache → 6379

Database Security Group (sg-db)
├── Inbound: sg-app → 3306 (僅接受 App)
└── Outbound: 無 (或僅限必要)

Cache Security Group (sg-cache)
├── Inbound: sg-app → 6379 (僅接受 App)
└── Outbound: 無
```

**原則**：Security Group 之間引用 SG ID（非 CIDR），確保來源明確且自動跟隨變更。
