# GCP Data Architecture Patterns

資料庫選型、資料管線與 BigQuery 設計模式。

---

## 資料庫選型指南

| 服務 | 類型 | 適用場景 | 延遲 | 擴展性 | 成本 |
|------|------|---------|------|--------|------|
| Cloud SQL | 關聯式 (PG/MySQL) | OLTP, 中小規模 | < 5ms | 垂直 + Read Replica | $$ |
| Cloud Spanner | 關聯式 (分散式) | 全球一致 OLTP | < 10ms | 水平無限 | $$$$ |
| Firestore | 文件型 NoSQL | 行動/Web 即時同步 | < 10ms | 自動水平 | $ |
| Bigtable | 寬欄型 NoSQL | 時序資料, IoT, 大量寫入 | < 10ms | 水平 (節點) | $$$ |
| BigQuery | 分析型 | OLAP, 資料倉儲, BI | 秒級 | Serverless | $ (按查詢) |
| Memorystore | 記憶體 (Redis) | 快取, Session, 排行榜 | < 1ms | 垂直 | $$ |
| AlloyDB | 關聯式 (PG 相容) | 高效能 OLTP + 分析 | < 2ms | 垂直 + 水平讀取 | $$$ |

### 選型決策流程

```
1. 資料模型是什麼？
   ├── 結構化（表格） → 2
   ├── 半結構化（JSON） → Firestore
   └── 時序 / 寬欄 → Bigtable

2. 需要全球強一致性？
   ├── 是 → Cloud Spanner
   └── 否 → 3

3. 讀寫比例？
   ├── 寫入密集 (> 70% write) → AlloyDB
   ├── 讀取密集 (> 70% read) → Cloud SQL + Read Replica
   └── 均衡 → Cloud SQL

4. 需要即時分析？
   ├── 是 → AlloyDB（HTAP）或 BigQuery 即時串流
   └── 否 → BigQuery（批次載入）
```

---

## Cloud SQL 最佳實踐

### 連線管理

```
推薦連線方式優先順序：
1. Cloud SQL Auth Proxy（Sidecar 模式）
2. Private IP + VPC Connector
3. Cloud SQL Connector Library（應用內）

❌ 禁止：Public IP + allowlisted IP
```

### 高可用配置

| 環境 | 可用性類型 | 備份 | PITR | 讀取副本 |
|------|-----------|------|------|---------|
| dev | ZONAL | 每日 | 否 | 0 |
| staging | ZONAL | 每日 | 否 | 0 |
| prod | REGIONAL | 每日 + PITR | 是 | 1-2 |

### 效能調校

- `max_connections`：根據實例大小設定，避免 OOM
- `shared_buffers`：設為可用記憶體的 25%
- `work_mem`：根據複雜查詢需求調整
- Connection Pooling：使用 PgBouncer 或 Cloud SQL Proxy 的連線池
- 慢查詢日誌：啟用 `log_min_duration_statement = 1000`

---

## BigQuery 設計模式

### 資料建模

```
Dataset 命名：{project}_{domain}_{layer}
例：gaming_user_raw, gaming_user_curated, gaming_analytics_mart

Table 命名：{entity}_{granularity}
例：user_events_daily, order_summary_monthly
```

### 分區與叢集化

```sql
-- 分區（Partitioning）：按時間欄位，減少掃描量
CREATE TABLE `project.dataset.events`
(
  event_id STRING,
  event_type STRING,
  user_id STRING,
  created_at TIMESTAMP,
  payload JSON
)
PARTITION BY DATE(created_at)
CLUSTER BY event_type, user_id;
```

**分區策略**：
- 時間分區：`PARTITION BY DATE(timestamp_column)` — 最常用
- 整數範圍分區：適用於 ID 範圍查詢
- 分區過期：設定 `partition_expiration_days` 自動清理舊資料

**叢集化策略**：
- 最多 4 個欄位，順序影響效能
- 優先放 `WHERE` / `JOIN` 常用欄位

### 成本控制

- 使用 `LIMIT` 測試查詢前，先用 `--dry_run` 估算成本
- 避免 `SELECT *`，只選需要的欄位
- 使用 Materialized Views 快取常用聚合
- 設定 Custom Quota 限制每日查詢量

---

## 資料管線模式

### 批次處理 (Batch)

```
Cloud Storage (原始資料)
  │
  ▼
Cloud Dataflow (Apache Beam)
  │  ── 清洗、轉換、驗證
  ▼
BigQuery (分析表)
  │
  ▼
Looker / Connected Sheets (視覺化)
```

排程：Cloud Scheduler → Cloud Functions → 觸發 Dataflow Job

### 串流處理 (Streaming)

```
應用程式 / IoT 裝置
  │
  ▼
Pub/Sub (訊息佇列)
  │
  ├── Dataflow Streaming → BigQuery (即時分析)
  │
  └── Cloud Functions → Firestore (即時更新)
```

### CDC (Change Data Capture)

```
Cloud SQL (來源)
  │
  ▼
Datastream (CDC)
  │
  ▼
BigQuery (即時同步)
```

---

## 快取策略

### 多層快取架構

```
Client Cache (Browser / App)
  │ Cache-Control headers
  ▼
Cloud CDN (邊緣快取)
  │ 靜態資源 + API 回應快取
  ▼
Application Cache (Memorystore Redis)
  │ 熱點資料 + Session
  ▼
Database (Cloud SQL / Firestore)
```

### 快取失效策略

| 策略 | 適用場景 | 實作方式 |
|------|---------|---------|
| TTL | 可容忍短暫過期 | `EXPIRE key seconds` |
| Write-Through | 寫入時同步更新快取 | App 層雙寫 |
| Write-Behind | 高寫入吞吐 | 非同步寫回 |
| Cache-Aside | 通用場景 | 讀取時 miss 再載入 |
| Event-Driven | 即時一致性 | Pub/Sub 通知失效 |
