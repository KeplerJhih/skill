# GCP Networking Architecture Patterns

常見 GCP 網路架構模式，用於架構設計參考。

---

## Pattern 1：單區域 Web 應用

適用：中小型 Web 應用，單一區域部署。

```
Internet
  │
  ▼
Cloud Armor (WAF + DDoS)
  │
  ▼
Global HTTPS Load Balancer
  │
  ▼
Cloud Run / GKE (asia-east1)
  │
  ├── Cloud SQL (Private IP, Regional HA)
  ├── Memorystore Redis (快取)
  └── Cloud Storage (靜態資源)
```

**關鍵配置**：
- Cloud Armor：OWASP Top 10 規則 + Rate Limiting
- LB：Managed SSL Certificate + HTTP→HTTPS Redirect
- Cloud Run：VPC Connector 連接私有資源
- Cloud SQL：Private IP only + Automated Backups

---

## Pattern 2：多區域高可用

適用：全球用戶、高 SLA 要求。

```
Internet
  │
  ▼
Cloud Armor
  │
  ▼
Global HTTPS Load Balancer (Anycast IP)
  │
  ├── Cloud Run (asia-east1)    ← 亞洲用戶
  │   └── Cloud SQL (Regional)
  │
  └── Cloud Run (us-central1)   ← 美洲用戶
      └── Cloud SQL (Regional)

Cloud Spanner (Multi-regional) ← 若需全球一致性
```

**關鍵配置**：
- Global LB 自動路由至最近區域
- 各區域獨立 Cloud SQL（最終一致）或 Cloud Spanner（強一致）
- Cloud CDN 快取靜態內容

---

## Pattern 3：微服務架構

適用：大型應用，多團隊協作。

```
Internet
  │
  ▼
Cloud Armor + Global LB
  │
  ▼
API Gateway / Cloud Endpoints
  │
  ├── Service A (Cloud Run)
  │   └── Cloud SQL
  │
  ├── Service B (Cloud Run)
  │   └── Firestore
  │
  └── Service C (GKE)
      └── Bigtable

Pub/Sub ← 服務間非同步通訊
Cloud Tasks ← 延遲任務
```

**關鍵配置**：
- API Gateway 統一入口、認證、限流
- 服務間使用 Pub/Sub 解耦
- 各服務獨立資料庫（Database per Service）
- Shared VPC 統一網路管理

---

## Pattern 4：資料分析管線

適用：ETL/ELT、資料倉儲、報表。

```
資料來源
  │
  ├── Cloud Storage (原始資料落地)
  │   │
  │   ▼
  │   Dataflow / Dataproc (ETL 處理)
  │   │
  │   ▼
  │   BigQuery (資料倉儲)
  │   │
  │   ▼
  │   Looker / Data Studio (視覺化)
  │
  └── Pub/Sub (串流資料)
      │
      ▼
      Dataflow Streaming
      │
      ▼
      BigQuery Streaming Insert
```

---

## VPC 設計最佳實踐

### IP 規劃

```
10.0.0.0/16 — 主 VPC
├── 10.0.1.0/24  — public subnet (asia-east1)
├── 10.0.2.0/24  — private subnet - compute (asia-east1)
├── 10.0.3.0/24  — private subnet - database (asia-east1)
├── 10.0.4.0/24  — private subnet - GKE pods (asia-east1)
├── 10.0.10.0/24 — VPC Connector (Serverless VPC Access)
└── 10.0.100.0/24 — management / bastion
```

### Shared VPC

多專案環境使用 Shared VPC：
- Host Project：管理 VPC 網路
- Service Projects：使用共享的子網
- 集中管理防火牆規則與路由

### Private Service Connect

連接 Google API 與第三方服務：
- 不經過 Internet
- 使用 Private IP 存取 Cloud SQL、Memorystore 等
- 支援 Consumer / Producer 模式

---

## Cloud CDN + GKE Gateway API

### 踩坑紀錄：GCPBackendPolicy 不支援 CDN

GKE Gateway API 自動建立的 Backend Service，**無法**透過 K8s CRD (`GCPBackendPolicy`) 設定 Cloud CDN。
`GCPBackendPolicy` 的 `spec.default` 僅支援 `securityPolicy`、`sessionAffinity`、`timeoutSec` 等欄位，沒有 `caching`/`cdn` 欄位。嘗試加入會報錯：`field not declared in schema`。

### 正確做法：gcloud 直接操作 Backend Service

```bash
# 1. 查詢 GKE Gateway 自動建立的 Backend Service 名稱
gcloud compute backend-services list \
  --filter=name~<keyword> \
  --format="table(name, enableCDN)"

# 2. 啟用 Cloud CDN
gcloud compute backend-services update <backend-service-name> \
  --global --enable-cdn --cache-mode=USE_ORIGIN_HEADERS

# 3. 停用 Cloud CDN
gcloud compute backend-services update <backend-service-name> \
  --global --no-enable-cdn
```

### Cache Mode 選擇

| Mode | 說明 | 適用場景 |
|------|------|---------|
| `USE_ORIGIN_HEADERS` | 依據 origin 的 `Cache-Control` header | 前端容器已正確設定 Cache-Control |
| `CACHE_ALL_STATIC` | 自動快取常見靜態副檔名 (js/css/png/woff2...) | 不想改 origin 設定 |
| `FORCE_CACHE_ALL` | 強制快取所有回應 | 全靜態站點 |

### 注意事項

- **GKE Gateway controller reconcile 會覆蓋**：重新部署 HTTPRoute 或 Gateway 時，controller 可能重置 Backend Service 設定，導致 CDN 被關閉。建議在 CI/CD pipeline 或 Makefile 中加入 CDN 啟用步驟。
- **WebSocket 不適用**：Socket.IO / WebSocket 的 Backend Service 不應啟用 CDN。
- **Cache-Control header**：使用 `USE_ORIGIN_HEADERS` 時，前端容器需回傳正確 header：
  - Hashed 靜態資源 (Vite build)：`Cache-Control: public, max-age=31536000, immutable`
  - `index.html`：`Cache-Control: no-cache`（確保每次取得最新版本）

---

## Cloud Armor 配置模板

```
# OWASP Core Rule Set
security_policy:
  rules:
    - priority: 1000
      action: deny(403)
      match:
        expr: "evaluatePreconfiguredExpr('sqli-v33-stable')"
    - priority: 1100
      action: deny(403)
      match:
        expr: "evaluatePreconfiguredExpr('xss-v33-stable')"
    - priority: 2000
      action: throttle
      match:
        expr: "true"
      rate_limit:
        rate: 100
        interval: 60
    - priority: 2147483647
      action: allow
      match:
        expr: "true"
```

---

## DNS 架構

### 單域名

```
example.com → Global LB IP (A Record)
*.example.com → Global LB IP (Wildcard A Record)
```

### 多環境

```
example.com          → prod Global LB
staging.example.com  → staging Cloud Run (direct mapping)
dev.example.com      → dev Cloud Run (direct mapping)
```

使用 Cloud DNS Managed Zone + 自動化 DNS Record 管理。
