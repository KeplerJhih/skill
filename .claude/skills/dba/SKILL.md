---
name: DBA (Database Administration)
description: >-
  This skill should be used when the user asks to "deploy MySQL on Kubernetes",
  "set up MySQL replication", "configure read-write splitting", "create MySQL StatefulSet",
  "debug replication error", "fix MySQL authentication", "MySQL backup on K8s",
  "database high availability", "MySQL GTID replication", "troubleshoot MySQL pod",
  "scale MySQL reader", "expand read replicas", "dynamic server-id",
  or mentions MySQL master-slave, writer-reader separation, MySQL on EKS/GKE,
  database StatefulSet, or MySQL ConfigMap/Secret management.
version: 0.1.0
---

# DBA Skill — MySQL on Kubernetes

Deploy, manage, and troubleshoot MySQL database clusters on Kubernetes with read-write separation, GTID-based replication, and high availability.

## Core Principles

- **Writer/Reader 分離** — Writer 和 Reader 使用獨立的 StatefulSet，各自擁有獨立的 Service、Headless Service、PDB，便於獨立擴縮與維護。
- **GTID Replication** — 使用 GTID (`gtid-mode=ON`) 進行 replication，避免手動管理 binlog position。
- **Lifecycle Hook 優先** — Replication 設定、使用者建立、read_only 切換等操作放在 `postStart` lifecycle hook，不放在 ConfigMap 或 initContainer。
- **動態 Server-ID** — Reader 的 `server-id` 必須透過 initContainer 根據 Pod 序號動態生成（`100 + ordinal`），不可在 ConfigMap 中寫死。否則擴容 Reader 時所有 Pod 會有相同 server-id，導致 replication 衝突。
- **驗證每一步假設** — 寫完 manifest 後進 Pod 實測每條指令的實際輸出，不依賴「應該會這樣」的假設。
- **Secret 外部化** — Secret manifest 僅作為佔位符，生產環境使用 ExternalSecrets 或 SealedSecrets。

---

## Architecture Overview

```
                    ┌─────────────┐
                    │  Application │
                    └──────┬──────┘
                     Write │ Read
               ┌───────────┼───────────┐
               ▼                       ▼
        ┌─────────────┐        ┌─────────────┐
        │ mysql-writer │        │ mysql-reader │
        │   (SVC)      │        │   (SVC)      │
        └──────┬──────┘        └──────┬──────┘
               ▼                       ▼
        ┌─────────────┐        ┌─────────────────┐
        │ StatefulSet  │ ──────▶│ StatefulSet      │
        │ writer (1)   │  GTID  │ reader (1~N)    │
        └─────────────┘  Repl  └─────────────────┘
```

## Workflow

### Step 1: Plan Resource Structure

每個 MySQL 部署需要以下資源：

| 資源 | Writer | Reader | 共用 |
|------|--------|--------|------|
| StatefulSet | `writer/statefulset.yaml` | `reader/statefulset.yaml` | — |
| Service (ClusterIP) | `writer/service.yaml` | `reader/service.yaml` | — |
| Headless Service | `writer/headless.yaml` | `reader/headless.yaml` | — |
| PDB | `writer/pdb.yaml` | `reader/pdb.yaml` | — |
| ConfigMap | — | — | `configmap.yaml` |
| Secret | — | — | `secret.yaml` |
| Namespace | — | — | `namespace.yaml` |

目錄結構遵循 Kustomize base/overlays 模式：

```
infra/mysql/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── configmap.yaml
│   ├── secret.yaml
│   ├── writer/
│   │   ├── statefulset.yaml
│   │   ├── service.yaml
│   │   ├── headless.yaml
│   │   └── pdb.yaml
│   └── reader/
│       ├── statefulset.yaml
│       ├── service.yaml
│       ├── headless.yaml
│       └── pdb.yaml
└── overlays/
    ├── dev/       # 本地 Docker Desktop
    └── cloud/     # AWS EKS / GKE
```

### Step 2: ConfigMap — 只放 mysqld 共用啟動參數

ConfigMap 包含 `primary.cnf` 和 `replica.cnf`。

**Critical Rules**:
- 絕對不要在 ConfigMap 中設定 `read_only` 或 `super_read_only`。MySQL Docker entrypoint 啟動時需要寫入（設定 root 密碼等），過早啟用 read_only 會導致初始化失敗。改為在 postStart lifecycle hook 中用 `SET GLOBAL` 設定。
- `replica.cnf` 中**不可包含 `server-id`**。server-id 必須每個 Pod 唯一，由 initContainer 動態生成。寫死會導致多 Reader 擴容時 replication 衝突。

### Step 3: Writer StatefulSet — postStart 建立 Replication User

Writer 的 `postStart` lifecycle hook 負責：
1. 等待本地 MySQL ready（**必須用 `-h 127.0.0.1` 走 TCP**）
2. 建立 replication user（使用 `mysql_native_password`）

**Critical Rule 1 — TCP 等待**：postStart 中的 `mysqladmin ping` 和 `mysql -e` 必須加 `-h 127.0.0.1`。MySQL 官方 image 的 entrypoint 在初始化時會啟動一個臨時 server（僅綁 Socket，不開 TCP port）。不加 `-h` 預設走 Socket → 臨時 server 回應 → DDL 失敗或消失 → `|| true` 吞掉。加 `-h 127.0.0.1` 強制走 TCP（port 3306），只有正式 mysqld 才會回應。此行為與 Docker Desktop 無關，所有使用 MySQL 官方 image 的 K8s 環境都會發生。

**Critical Rule 2 — 認證插件**：MySQL 8.0 預設使用 `caching_sha2_password`，此 plugin 首次認證需要 SSL。K8s Pod 間通訊預設無 SSL，必須在 `CREATE USER` 時明確指定 `IDENTIFIED WITH mysql_native_password`。同時加上 `ALTER USER` 確保已存在的使用者也被更新。

### Step 4: Reader StatefulSet — initContainer + postStart

Reader 需要兩階段初始化：

**initContainer（動態 server-id）**：
1. 從 ConfigMap 複製 base replica config 到 emptyDir
2. 根據 Pod hostname 序號生成唯一 server-id（`100 + ordinal`）
3. 寫入 `server-id.cnf` 到同一 emptyDir

```
mysql-reader-0 → server-id=100
mysql-reader-1 → server-id=101
mysql-reader-N → server-id=100+N
```

**Volume 掛載架構**：
- `config-map` volume：ConfigMap 唯讀掛載到 initContainer 的 `/mnt/config-map`
- `dynamic-config` volume（emptyDir）：initContainer 寫入，mysql 容器讀取，掛載到 `/etc/mysql/conf.d`

**postStart lifecycle hook** 負責：
1. 等待本地 MySQL ready（**`-h 127.0.0.1` 走 TCP**，同 Writer 理由）
2. **等待 repl user 可登入 Writer**（不是 `mysqladmin ping`，而是用 repl 帳號實際 `mysql -e "SELECT 1"` 確認 Writer 的 postStart 已完成建立 repl user）
3. 檢查 replication 是否已在執行（冪等性，注意 `SHOW REPLICA STATUS\G` 不可加 `-N` flag，且 `mysql` 需加 `-h 127.0.0.1`）
4. 若未執行，`RESET REPLICA ALL` → `CHANGE REPLICATION SOURCE TO` → `START REPLICA`
5. 設定 `SET GLOBAL read_only=ON; SET GLOBAL super_read_only=ON;`

**Critical Rule — `|| true` 模式**：K8s postStart 若返回非 0 會殺容器，因此 SQL 指令必須加 `|| true`。但這會吞掉所有錯誤，導致靜默失敗。防禦策略：在 `|| true` 之前用 `until` 循環確保前提條件已滿足，並搭配 readinessProbe 檢查功能狀態作為安全網。

### Step 5: Readiness Probe — 驗證 Replication 狀態

Reader 的 readinessProbe 必須同時檢查：
1. `mysqladmin ping` — MySQL 進程存活
2. `SHOW REPLICA STATUS` 中 `Replica_SQL_Running: Yes`

**Critical Rule**: 使用 `mysql -e "SHOW REPLICA STATUS\G"` 時，不可加 `-N` flag。`-N` 會隱藏欄位名，但 `\G` 格式下欄位名是輸出的一部分（如 `Replica_SQL_Running: Yes`）。加了 `-N` 會導致 grep 永遠匹配不到。

### Step 6: Environment Overlays

| 環境 | StorageClass | 存儲大小 | Reader Replicas | Anti-Affinity |
|------|-------------|---------|-----------------|---------------|
| dev (本地) | `hostpath` | 5Gi | 1 | preferred |
| cloud (AWS) | `gp3` | 50Gi | 2+ | required |

Cloud overlay 額外設定：
- Reader `replicas: 2` 以上
- `requiredDuringSchedulingIgnoredDuringExecution` pod anti-affinity（按 hostname 分散）
- 加大 CPU/Memory resources

### Step 7: Validate Deployment

部署後驗證清單：

```bash
# 1. 檢查 Pod 狀態
kubectl get pods -n {namespace}

# 2. 確認 Writer 可寫
kubectl exec {writer-pod} -n {namespace} -- bash -c \
  'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT @@read_only, @@super_read_only;"'

# 3. 確認 Reader 唯讀
kubectl exec {reader-pod} -n {namespace} -- bash -c \
  'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT @@read_only, @@super_read_only;"'

# 4. 確認 Replication 正常
kubectl exec {reader-pod} -n {namespace} -- bash -c \
  'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW REPLICA STATUS\G"' | \
  grep -E "Running|Error|Behind"

# 5. 資料同步測試
# Writer 寫入 → Reader 查詢 → 確認資料一致
# Reader 寫入 → 確認被拒絕 (ERROR 1290: super-read-only)
```

---

## Reader Scaling (擴容)

擴容 Reader 只需修改 `replicas` 數字。每個新 Pod 會自動透過 initContainer 生成唯一 server-id，postStart 自動設定 replication。

```bash
# 方法一：修改 base 或 overlay 的 replicas，重新 apply
kubectl apply -k ./infra/mysql/overlays/{env}

# 方法二：臨時擴容（不改 manifest）
kubectl scale statefulset mysql-reader -n {namespace} --replicas=3
```

擴容後驗證：
```bash
# 確認每個 Reader 的 server-id 唯一
for pod in $(kubectl get pods -n {namespace} -l app.kubernetes.io/name=mysql-reader -o name); do
  echo "=== ${pod} ==="
  kubectl exec ${pod} -n {namespace} -- bash -c \
    'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -N -e "SELECT @@server_id;"' 2>/dev/null
done
```

**注意**：StatefulSet 是有序部署（OrderedReady），Pod N+1 必須等 Pod N 的 readinessProbe 通過後才會啟動。

---

## Secret Management

Replication 密碼長度**必須小於 32 字元**。MySQL replication protocol 對密碼長度有限制，超過會導致靜默失敗。

Secret manifest 中使用 `CHANGE_ME_USE_EXT_SECRET` 作為佔位符，提醒生產環境必須替換為真實密碼管理方案。

---

## Backup Strategy

MySQL 備份作為獨立的 Kustomize 資源管理（`infra/mysql-backup/`），與主 MySQL 部署分離：
- CronJob 從 Reader 執行 `mysqldump`，避免影響 Writer 效能
- 設定保留天數（預設 7 天）
- Cloud overlay 使用更大的 PVC

---

## Common Pitfalls Quick Reference

| 問題 | 根因 | 解法 |
|------|------|------|
| Replication `caching_sha2_password` 錯誤 | MySQL 8.0 預設 plugin 需 SSL | `IDENTIFIED WITH mysql_native_password` |
| `super_read_only` 導致初始化失敗 | ConfigMap 中過早設定 read_only | 移至 postStart `SET GLOBAL` |
| readinessProbe 永遠不通過 | `mysql -N -e "...\G"` 隱藏欄位名 | 移除 `-N` flag（postStart 的 `is_running` 檢查同理） |
| Replication 密碼失敗 | 密碼超過 32 字元 | 縮短至 32 字元以內 |
| Docker Desktop hostpath 資料殘留 | hostpath provisioner 不清理舊資料 | 刪除 PVC 後用 Job 清理目錄 |
| `MYSQL_ROOT_PASSWORD` 無效 | MySQL 只在首次初始化時讀取此 env | 清除 data 目錄重新初始化 |
| StatefulSet 更新失敗 | `volumeClaimTemplates` 不可變 | 刪除 StatefulSet + PVC 後重建 |
| Reader 擴容後 replication 衝突 | ConfigMap 寫死 `server-id=2` | initContainer 動態生成（`100 + ordinal`） |
| postStart 競態條件 | Reader 用 `mysqladmin ping` 等 Writer，ping 通過但 repl user 未建立 | 改用 `mysql -u repl -e "SELECT 1"` 等待 repl user 實際可登入 |
| `\|\| true` 靜默失敗 | postStart 非 0 exit 會殺容器，`\|\| true` 必要但吞掉所有錯誤 | 前置 `until` 確保前提條件 + readinessProbe 作為安全網 |
| postStart 打到臨時 server | MySQL 官方 image entrypoint 的臨時 server 僅綁 Socket 不開 TCP，`mysqladmin ping` 預設走 Socket 會誤判為 ready | 所有 `mysqladmin ping` 和 `mysql -e` 加 `-h 127.0.0.1` 強制走 TCP |

---

## Additional Resources

### Reference Files

For detailed templates and troubleshooting guides, consult:
- **`references/mysql-k8s-patterns.md`** — Complete StatefulSet, ConfigMap, Service YAML templates for MySQL writer/reader deployment
- **`references/troubleshooting.md`** — Detailed troubleshooting SOP with step-by-step debugging for replication errors, authentication issues, and Docker Desktop quirks
