# AWS 資料架構模式

此文件涵蓋 AWS 資料庫選型、資料管線設計與分析服務架構模式。

---

## 資料庫選型指南

### 關聯式資料庫

| 服務 | 適用場景 | 效能 | 成本 |
|------|---------|------|------|
| **Aurora MySQL/PostgreSQL** | OLTP 高可用、讀取密集 | 比標準 RDS 快 3-5x | 比 RDS 高 ~20% |
| **Aurora Serverless v2** | 流量波動大、開發環境 | 自動擴展 0.5-128 ACU | 按使用量計費 |
| **RDS MySQL/PostgreSQL** | 標準 OLTP、預算有限 | 依實例類型 | 最具成本效益 |
| **RDS Multi-AZ** | 需要自動故障轉移 | 同步複寫 | 約 2x 單 AZ |
| **Aurora Global Database** | 跨 Region 讀取、DR < 1min RPO | 跨 Region < 1s 延遲 | 較高 |

### 關聯式資料庫配置模式

```
生產環境 Aurora 典型配置：
├── Writer Instance: db.r6g.xlarge (Graviton)
├── Reader Instance: db.r6g.large x 2 (跨 AZ)
├── Encryption: KMS CMK
├── Backup: 35 天保留 + PITR
├── Monitoring: Enhanced Monitoring + Performance Insights
├── Parameter Group: 自訂（依工作負載調優）
├── Subnet Group: Isolated Subnets (無 Public Access)
├── Security Group: 僅允許 Application SG
└── IAM Authentication: 啟用（Lambda/ECS 使用）
```

### NoSQL 資料庫

| 服務 | 資料模型 | 適用場景 | 定價模式 |
|------|---------|---------|---------|
| **DynamoDB** | Key-Value / Document | 低延遲 < 10ms、任意規模 | On-Demand / Provisioned |
| **DynamoDB + DAX** | 同上 + 快取 | 需要微秒級延遲 | 額外 DAX 節點費 |
| **ElastiCache Redis** | Key-Value / 多結構 | Session、快取、排行榜 | 節點費 |
| **DocumentDB** | MongoDB 相容 | MongoDB 遷移、文件查詢 | 實例 + 儲存費 |
| **Neptune** | Graph | 社交網路、推薦、詐欺偵測 | 實例 + I/O 費 |
| **Keyspaces** | Cassandra 相容 | Cassandra 遷移、寬欄 | On-Demand / Provisioned |
| **MemoryDB** | Redis 相容 + 持久化 | 需要持久化的 Redis 工作負載 | 節點費 |

### DynamoDB 設計模式

```
單表設計 (Single-Table Design)：
├── Partition Key (PK): 高基數，均勻分佈
├── Sort Key (SK): 支援範圍查詢
├── GSI Overloading: 不同實體共用 GSI
├── 存取模式驅動設計（非正規化）
└── 常見 PK/SK 模式：
    ├── USER#<id> / PROFILE       → 用戶資料
    ├── USER#<id> / ORDER#<ts>    → 用戶訂單（時間排序）
    ├── ORDER#<id> / ITEM#<id>    → 訂單明細
    └── GSI1PK: STATUS#<status>   → 依狀態查詢

容量規劃：
├── On-Demand: 新應用、流量不可預測 → 自動擴展，無需規劃
├── Provisioned: 流量穩定、可預測 → 搭配 Auto Scaling
└── Reserved Capacity: 高流量穩定使用 → 最多省 77%
```

---

## 快取策略

### 多層快取架構

```
Client → CloudFront (CDN Cache, TTL=300s)
  → API Gateway (Response Cache, TTL=60s, 選用)
    → Application
      → ElastiCache Redis (Application Cache, TTL=300-3600s)
        → Database (Source of Truth)
```

### 快取模式

| 模式 | 說明 | 適用場景 |
|------|------|---------|
| **Cache-Aside (Lazy Loading)** | 讀取時檢查快取，Miss 時從 DB 載入並寫入快取 | 通用模式，最常見 |
| **Write-Through** | 寫入 DB 時同步寫入快取 | 讀取延遲敏感，可接受寫入延遲 |
| **Write-Behind** | 寫入快取後非同步寫入 DB | 寫入密集，可接受短暫資料不一致 |
| **TTL-based Expiry** | 設定過期時間，到期後重新載入 | 容許短暫過期資料 |

### ElastiCache Redis 配置模式

```
生產環境 Redis 典型配置：
├── Node Type: cache.r6g.large (Graviton)
├── Cluster Mode: 啟用（需要高吞吐/大資料量）或 停用（簡單場景）
├── Replicas: 2 per shard (跨 AZ)
├── Encryption: at-rest (KMS) + in-transit (TLS)
├── Auth: Redis AUTH Token (存於 Secrets Manager)
├── Subnet Group: Isolated Subnets
├── Backup: 每日自動備份，保留 7 天
├── Parameter Group: maxmemory-policy = allkeys-lru
└── CloudWatch Alarms:
    ├── CPUUtilization > 75%
    ├── EngineCPUUtilization > 75%
    ├── DatabaseMemoryUsagePercentage > 80%
    └── CurrConnections > 閾值
```

---

## 資料管線模式

### 即時串流處理

```
資料來源 → Kinesis Data Streams → Lambda / Kinesis Data Analytics
  → 處理結果 → DynamoDB / S3 / ElastiCache
  → 告警 → SNS → Slack/PagerDuty

組件選型：
├── 攝取: Kinesis Data Streams (自管分片) 或 Kinesis Data Firehose (全託管)
├── 處理: Lambda (簡單轉換) 或 Kinesis Data Analytics (SQL/Flink)
├── 儲存: S3 (原始資料) + DynamoDB (即時查詢)
└── 監控: CloudWatch Metrics (IteratorAge, GetRecords.Latency)
```

### 批次 ETL 處理

```
S3 (Raw Data) → AWS Glue Crawler (Schema Discovery)
  → Glue ETL Job (Spark) → S3 (Processed Data, Parquet 格式)
  → Glue Data Catalog → Athena (Ad-hoc 查詢) / Redshift Spectrum (倉儲查詢)

排程：
├── Glue Trigger (時間/事件觸發)
├── Step Functions (複雜工作流)
└── EventBridge Scheduler (Cron)
```

### 事件驅動資料同步

```
DynamoDB Streams → Lambda → ElastiCache (快取更新)
                         → OpenSearch (搜尋索引)
                         → S3 (資料湖歸檔)

或

DynamoDB Streams → EventBridge Pipes → 多目標扇出
```

---

## 分析服務架構

### Athena (Ad-hoc 查詢)

```
最佳實踐：
├── 資料格式: Parquet 或 ORC（列式壓縮，查詢效率高）
├── 分區: 依日期/區域分區（date=2026-04-09/region=ap-southeast-1/）
├── 壓縮: Snappy (Parquet 預設) 或 ZSTD
├── 檔案大小: 128MB-512MB 最佳（避免過多小檔案）
├── Workgroup: 獨立 Workgroup + 查詢結果 S3 位置
├── 成本控制: Workgroup 設定查詢掃描上限
└── 整合: Glue Data Catalog 統一中繼資料

典型用途：
├── 日誌分析（CloudTrail、ALB Logs、VPC Flow Logs）
├── 廣告歸因分析
├── 使用者行為分析
└── 資料探索
```

### Redshift (資料倉儲)

```
架構選型：
├── Redshift Serverless: 間歇性查詢、快速啟動 → 按使用量計費
├── Redshift Provisioned: 持續高負載查詢 → 按節點計費
└── Redshift Spectrum: 查詢 S3 資料（不需載入） → 按掃描量計費

典型配置（Provisioned）：
├── Node Type: ra3.xlplus (含 Managed Storage)
├── 節點數: 2+ (生產環境)
├── 加密: KMS
├── Snapshot: 自動 + 跨 Region 複製
├── WLM (Workload Management): 自動 WLM
└── Concurrency Scaling: 啟用（處理查詢尖峰）
```

### 資料湖架構 (Lake Formation)

```
AWS Lake Formation
├── S3 Data Lake
│   ├── Raw Zone: s3://datalake-raw/ (原始資料)
│   ├── Processed Zone: s3://datalake-processed/ (清洗後)
│   └── Curated Zone: s3://datalake-curated/ (業務可用)
├── Glue Data Catalog (統一中繼資料)
├── Glue ETL Jobs (資料轉換)
├── Lake Formation Permissions (細粒度存取控制)
└── 查詢引擎：
    ├── Athena (Ad-hoc)
    ├── Redshift Spectrum (倉儲)
    ├── EMR (大規模 Spark/Hive)
    └── SageMaker (ML)
```

---

## 資料遷移模式

### 資料庫遷移

| 來源 | 目標 | 工具 | 模式 |
|------|------|------|------|
| MySQL → Aurora MySQL | AWS DMS | 全量 + CDC |
| PostgreSQL → Aurora PostgreSQL | AWS DMS | 全量 + CDC |
| Oracle → Aurora PostgreSQL | AWS SCT + DMS | Schema 轉換 + 資料遷移 |
| MongoDB → DocumentDB | AWS DMS | 全量 + CDC |
| Cassandra → Keyspaces | AWS Glue | 批次匯入 |
| Redis → ElastiCache | 原生 replication 或 備份還原 | 線上遷移 |

### 大量資料搬遷

| 資料量 | 建議方式 | 時間 |
|--------|---------|------|
| < 10TB | AWS DataSync (Internet) | 數小時至天 |
| 10-100TB | AWS DataSync (Direct Connect) | 數天 |
| 100TB-1PB | AWS Snowball Edge | 約 1 週 |
| > 1PB | AWS Snowmobile | 數週 |

---

## 備份與災難復原

### 備份策略矩陣

| 服務 | 備份方式 | RPO | 保留策略建議 |
|------|---------|-----|------------|
| RDS/Aurora | Automated Backup + PITR | 5 min | 35 天 |
| DynamoDB | PITR + On-demand Backup | 5 min / 隨需 | PITR 35 天 |
| S3 | Versioning + Cross-Region Replication | 即時 | 依合規需求 |
| EBS | Snapshots (AWS Backup) | 依排程 | 30-90 天 |
| EFS | AWS Backup | 依排程 | 30-90 天 |
| Redshift | Automated Snapshots | 8 小時 | 35 天 |

### DR 策略對照

| 策略 | RTO | RPO | 成本 | 適用 |
|------|-----|-----|------|------|
| Backup & Restore | 24h+ | 24h | $ | 非關鍵系統 |
| Pilot Light | 1-4h | 分鐘級 | $$ | 核心系統最小運行 |
| Warm Standby | 15-60min | 秒級 | $$$ | 業務關鍵系統 |
| Multi-Region Active-Active | ~0 | ~0 | $$$$ | 零停機要求 |
