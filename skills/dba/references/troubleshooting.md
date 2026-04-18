# MySQL on Kubernetes — Troubleshooting SOP

## 除錯通用流程

遇到 MySQL Pod 問題時，依序執行：

```bash
# 1. 檢查 Pod 狀態
kubectl get pods -n {namespace} -o wide

# 2. 查看 Pod 事件
kubectl describe pod {pod-name} -n {namespace}

# 3. 查看 MySQL 日誌
kubectl logs {pod-name} -n {namespace} --tail=100

# 4. 進入 Pod 檢查
kubectl exec -it {pod-name} -n {namespace} -- bash
```

---

## 問題一：Replication `caching_sha2_password` 認證錯誤

### 症狀

```
Last_IO_Error: Error connecting to source 'repl@mysql-writer...'.
Authentication plugin 'caching_sha2_password' reported error:
Authentication requires secure connection.
```

Reader Pod 為 `0/1 Running`（readinessProbe 未通過）。

### 根因

MySQL 8.0 預設使用 `caching_sha2_password` 認證插件。此插件在首次認證（密碼交換階段）需要加密連線（SSL/TLS）。K8s Pod 間通訊預設為明文，因此 replication 連線無法通過認證。

### 解法

在 Writer 的 postStart 中，使用 `mysql_native_password` 建立 replication user：

```sql
CREATE USER IF NOT EXISTS 'repl'@'%'
  IDENTIFIED WITH mysql_native_password BY '{password}';

-- 關鍵：ALTER USER 確保已存在的使用者也被更新
-- CREATE USER IF NOT EXISTS 不會修改已存在使用者的 plugin
ALTER USER 'repl'@'%'
  IDENTIFIED WITH mysql_native_password BY '{password}';
```

### 驗證

```bash
# 確認 plugin 已更改
kubectl exec {writer-pod} -n {namespace} -- bash -c \
  'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -N -e \
   "SELECT user, host, plugin FROM mysql.user WHERE user=\"repl\";"'

# 預期輸出：
# repl  %  mysql_native_password
```

### 替代方案

若必須使用 `caching_sha2_password`，需設定 MySQL SSL：
- 產生 CA、Server、Client 證書
- 透過 Secret 掛載到 Writer 和 Reader
- ConfigMap 中加入 SSL 相關設定
- 複雜度遠高於切換 plugin，通常不建議

---

## 問題二：`super_read_only` 導致 MySQL 初始化失敗

### 症狀

Reader Pod 反覆 CrashLoopBackOff。MySQL 日誌顯示：

```
[ERROR] [Entrypoint]: ... The MySQL server is running with the
--super-read-only option so it cannot execute this statement
```

### 根因

MySQL Docker image 的 entrypoint 腳本在首次啟動時需要：
1. 建立系統資料庫
2. 設定 root 密碼
3. 建立 `MYSQL_DATABASE` 指定的資料庫
4. 執行 `/docker-entrypoint-initdb.d/` 下的腳本

以上操作都需要寫入權限。如果 `super_read_only=ON` 在 `my.cnf`（ConfigMap）中設定，MySQL 啟動後立即生效，entrypoint 無法完成初始化。

### 解法

1. 從 ConfigMap 的 `replica.cnf` 中**移除** `read_only` 和 `super_read_only`
2. 在 Reader 的 `postStart` lifecycle hook 中設定：

```bash
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "
  SET GLOBAL read_only=ON;
  SET GLOBAL super_read_only=ON;
" 2>/dev/null || true
```

### 時序圖

```
MySQL 啟動流程：
entrypoint.sh 開始
  ├─ 建立系統 DB      ← 需要寫入
  ├─ 設定 root 密碼    ← 需要寫入
  ├─ 建立 MYSQL_DATABASE ← 需要寫入
  ├─ mysqld 啟動       ← ConfigMap 設定此時生效
  │                      如果 read_only=ON → entrypoint 後續操作失敗
  └─ entrypoint 完成

postStart hook 開始   ← MySQL 已完全初始化
  ├─ 設定 replication
  └─ SET GLOBAL read_only=ON  ← 此時設定才安全
```

---

## 問題三：readinessProbe 永遠不通過

### 症狀

Reader Pod 持續顯示 `0/1 Running`，但進入 Pod 手動檢查 replication 正常（`Replica_IO_Running: Yes`, `Replica_SQL_Running: Yes`）。

### 根因

readinessProbe 使用了 `mysql -N -e "SHOW REPLICA STATUS\G"`，其中：
- `-N` (`--skip-column-names`) 隱藏欄位名
- `\G` (vertical format) 的輸出格式為 `Key: Value`

加了 `-N` 後，`\G` 格式只輸出 Value 部分，不輸出 Key。grep 搜尋 `Replica_SQL_Running: Yes` 永遠找不到匹配。

### 對比

```bash
# 不加 -N（正確）
$ mysql -e "SHOW REPLICA STATUS\G" | grep SQL_Running
          Replica_SQL_Running: Yes
    Replica_SQL_Running_State: Replica has read all relay log...

# 加 -N（錯誤）
$ mysql -N -e "SHOW REPLICA STATUS\G" | grep SQL_Running
(無輸出)
```

### 解法

移除 readinessProbe 中的 `-N` flag：

```yaml
readinessProbe:
  exec:
    command:
      - bash
      - -c
      - |
        mysqladmin ping -u root -p"${MYSQL_ROOT_PASSWORD}" && \
        mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW REPLICA STATUS\G" 2>/dev/null | grep -q "Replica_SQL_Running: Yes"
```

### 教訓

撰寫 probe 後，**必須進入 Pod 手動執行 probe 指令**，確認實際輸出符合預期：

```bash
kubectl exec {pod} -n {namespace} -- bash -c '{probe-command}'
```

---

## 問題四：Replication 密碼超過 32 字元

### 症狀

Replication 設定成功，但 `SHOW REPLICA STATUS` 顯示 IO thread 無法連線，錯誤訊息為認證失敗（而非 `caching_sha2_password` 錯誤）。

### 根因

MySQL replication protocol 對密碼長度有限制（32 字元）。超長密碼在 `CHANGE REPLICATION SOURCE TO` 時被截斷，導致認證時密碼不匹配。

### 解法

確保 `MYSQL_REPLICATION_PASSWORD` 小於 32 字元。在 Secret 中使用短佔位符：

```yaml
MYSQL_REPLICATION_PASSWORD: "CHANGE_ME_USE_EXT_SECRET"  # 24 字元，安全
# 而非：
# MYSQL_REPLICATION_PASSWORD: "CHANGE_ME_USE_EXTERNAL_SECRET_MANAGER"  # 38 字元，超限
```

---

## 問題五：Docker Desktop hostpath 資料殘留

### 症狀

刪除 PVC 並重建 StatefulSet 後，MySQL 使用舊密碼而非 Secret 中的新密碼。或者 Reader 無法初始化因為 data 目錄已存在。

### 根因

Docker Desktop 的 hostpath provisioner 在 PVC 刪除後**不會**清除 host 上的實際資料目錄。新 PVC 可能分配到包含舊資料的目錄。

MySQL Docker image 只在 `/var/lib/mysql` 為空時執行初始化流程（讀取 `MYSQL_ROOT_PASSWORD` 等 env）。如果目錄已有資料，直接啟動 mysqld，忽略所有 `MYSQL_*` 環境變數。

### 解法

徹底清除殘留資料：

```bash
# 1. 刪除 StatefulSet 和 PVC
kubectl delete statefulset mysql-writer mysql-reader -n {namespace}
kubectl delete pvc -l app.kubernetes.io/part-of={app} -n {namespace}

# 2. 建立清理 Job 清除 hostpath 資料
kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: cleanup-mysql-data
  namespace: {namespace}
spec:
  template:
    spec:
      containers:
        - name: cleanup
          image: busybox
          command: ["sh", "-c", "rm -rf /data/*"]
          volumeMounts:
            - name: host-data
              mountPath: /data
      volumes:
        - name: host-data
          hostPath:
            path: /var/lib/docker/volumes/  # Docker Desktop 預設路徑
      restartPolicy: Never
EOF

# 3. 重新部署
kubectl apply -k ./infra/mysql/overlays/dev
```

**注意**：此問題僅影響 Docker Desktop 開發環境。Cloud 環境的 EBS/PD 在 PVC 刪除後會正確清除。

---

## 問題六：StatefulSet volumeClaimTemplates 不可變更

### 症狀

```
The StatefulSet "mysql-writer" is invalid:
spec.volumeClaimTemplates: Forbidden: updates to volumeClaimTemplates are forbidden
```

### 根因

K8s StatefulSet 的 `volumeClaimTemplates` 是 immutable field，不允許任何修改（包括 storageClass、size、accessModes）。

### 解法

```bash
# 1. 刪除 StatefulSet（保留 Pod 以避免資料遺失，可選）
kubectl delete statefulset {name} -n {namespace} --cascade=orphan

# 2. 刪除 PVC（如果需要更換 storageClass）
kubectl delete pvc {pvc-name} -n {namespace}

# 3. 重新建立
kubectl apply -k ./infra/mysql/overlays/{env}
```

如果只是擴容（增加 size），且 StorageClass 支援 volume expansion：

```bash
# 直接修改 PVC（不需要刪除 StatefulSet）
kubectl patch pvc {pvc-name} -n {namespace} \
  -p '{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}'
```

---

## 問題七：postStart 競態條件 — Writer 尚未建立 repl 使用者

### 症狀

全新部署後，所有 Reader 的 `SHOW REPLICA STATUS` 為空（replication 從未建立）。Pod 顯示 `0/1 Running`（readinessProbe 檢查 replication 不通過）。

### 根因

Writer 和 Reader 的 postStart 同時在各自 Pod 啟動時執行。Reader 的 postStart 用 `mysqladmin ping` 等待 Writer，但 **`mysqladmin ping` 只確認 mysqld 進程存活，不代表 Writer 的 postStart 已完成建立 repl user**。

時序如下：

```
Writer mysqld 啟動（ping 可通過） ← Reader 此時開始 CHANGE REPLICATION SOURCE
Writer postStart: CREATE USER repl  ← 尚未執行完
Reader: CHANGE REPLICATION SOURCE TO SOURCE_USER='repl' → Access denied
Reader: || true 吞掉錯誤 → replication 從未建立
```

### 解法

Reader postStart 中，改用 repl 帳號實際登入 Writer 來等待，而非 `mysqladmin ping`：

```bash
# 正確 — 等待 repl user 可登入
until mysql -h mysql-writer.{namespace}.svc.cluster.local \
  -u "${MYSQL_REPLICATION_USER}" -p"${MYSQL_REPLICATION_PASSWORD}" \
  -e "SELECT 1;" 2>/dev/null; do
  sleep 3
done

# 錯誤 — 只確認 mysqld 活著，repl user 可能還沒建立
until mysqladmin ping -h mysql-writer... --silent 2>/dev/null; do
  sleep 3
done
```

### 驗證

```bash
# 重新部署後確認所有 Reader 都自動建立 replication
kubectl delete statefulset mysql-reader -n {namespace}
kubectl apply -k ./infra/mysql/overlays/{env}
# 等待 Pod Ready 後檢查
for pod in $(kubectl get pods -n {ns} -l app.kubernetes.io/name=mysql-reader -o name); do
  echo "=== ${pod} ==="
  kubectl exec ${pod} -n {ns} -- bash -c \
    'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW REPLICA STATUS\G"' 2>&1 | \
    grep -E "Running|Source_Host"
done
```

---

## 問題八：Reader 擴容後 Replication 衝突（server-id 重複）

### 症狀

擴容 Reader replicas 後，新 Pod 的 replication 無法正常運作，或原有 Pod 的 replication 斷開。MySQL error log 可能出現：

```
[ERROR] Slave I/O thread: connected to master ... but found another server with the same server_id
```

或 `SHOW REPLICA STATUS` 顯示 IO thread 反覆重連。

### 根因

ConfigMap 中 `replica.cnf` 寫死了 `server-id=2`，所有 Reader Pod 都使用相同 server-id。MySQL replication 要求每個節點的 server-id 必須全域唯一，重複的 server-id 會導致 replication 衝突。

### 解法

1. **移除 ConfigMap 中的 server-id**：

```yaml
# replica.cnf — 不可包含 server-id
[mysqld]
# server-id is dynamically generated by initContainer
relay-log=relay-bin
```

2. **Reader StatefulSet 加入 initContainer 動態生成 server-id**：

```yaml
initContainers:
  - name: init-mysql-config
    image: busybox:1.36
    command:
      - sh
      - -c
      - |
        cp /mnt/config-map/base.cnf /mnt/conf.d/base.cnf
        ORDINAL=$(echo "${HOSTNAME}" | rev | cut -d'-' -f1 | rev)
        SERVER_ID=$((100 + ORDINAL))
        echo "[mysqld]" > /mnt/conf.d/server-id.cnf
        echo "server-id=${SERVER_ID}" >> /mnt/conf.d/server-id.cnf
    volumeMounts:
      - name: config-map
        mountPath: /mnt/config-map
      - name: dynamic-config
        mountPath: /mnt/conf.d
```

3. **Volume 架構**：ConfigMap 唯讀掛載給 initContainer → initContainer 複製到 emptyDir + 生成 server-id.cnf → mysql 容器只掛載 emptyDir 到 `/etc/mysql/conf.d`

### 驗證

```bash
# 確認每個 Reader 的 server-id 唯一
for pod in $(kubectl get pods -n {ns} -l app.kubernetes.io/name=mysql-reader -o name); do
  echo "${pod}: $(kubectl exec ${pod} -n {ns} -- bash -c \
    'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -N -e "SELECT @@server_id;"' 2>/dev/null)"
done

# 預期：
# pod/mysql-reader-0: 100
# pod/mysql-reader-1: 101
# pod/mysql-reader-2: 102
```

### Server-ID 分配規則

| 角色 | Server-ID | 來源 |
|------|-----------|------|
| Writer | 1 | ConfigMap `primary.cnf` 固定 |
| Reader-0 | 100 | initContainer `100 + 0` |
| Reader-1 | 101 | initContainer `100 + 1` |
| Reader-N | 100+N | initContainer `100 + N` |

---

## 問題九：`|| true` 導致 postStart 靜默失敗

### 症狀

Pod 顯示 `Running` 但功能不正常：
- Writer `Running` 但 repl user 不存在
- Reader `0/1 Running` 但 `SHOW REPLICA STATUS` 為空
- Reader `Running` 但 `read_only=OFF`

Pod 沒有 CrashLoopBackOff，日誌也沒有明顯錯誤，難以察覺。

### 根因

K8s `postStart` lifecycle hook 的機制：如果 hook 返回非 0 exit code，**kubelet 會殺掉整個容器**。因此 postStart 中的 SQL 指令必須加 `|| true` 來避免容器被殺。

但 `|| true` 會吞掉所有錯誤，包括：
- MySQL 尚未啟動完成（race condition）
- SQL 語法錯誤
- 權限不足
- 網路不通（Writer 未就緒）

### 解法

`|| true` 是必要的惡（不加會殺容器），但必須搭配**防禦層**：

1. **前置等待邏輯** — 在 `|| true` 的 SQL 之前，用 `until` 循環確保前提條件已滿足：

```bash
# Writer postStart: 等待本地 MySQL ready 再建 user
until mysqladmin ping -u root -p"${MYSQL_ROOT_PASSWORD}" --silent 2>/dev/null; do
  sleep 2
done
# 此時 MySQL 已 ready，下面的 CREATE USER 幾乎不會失敗
mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER ..." 2>/dev/null || true
```

2. **readinessProbe 作為安全網** — 即使 postStart 靜默失敗，readinessProbe 檢查功能狀態（replication running），Pod 不會被標記為 Ready，不會接收流量：

```yaml
readinessProbe:
  exec:
    command: ["bash", "-c", "... grep -q 'Replica_SQL_Running: Yes'"]
```

3. **除錯時直接檢查功能狀態**，不要只看 Pod status：

```bash
# 不要只看這個
kubectl get pods  # 可能顯示 Running 但功能壞掉

# 要看這些
kubectl exec {writer} -- bash -c 'mysql ... -e "SELECT user, plugin FROM mysql.user WHERE user=\"repl\";"'
kubectl exec {reader} -- bash -c 'mysql ... -e "SHOW REPLICA STATUS\G"' | grep Running
```

### 教訓

`|| true` + `Running` 狀態 = **假象**。除錯 MySQL on K8s 時，永遠不要信任 Pod 狀態，要直接進 Pod 驗證 MySQL 層面的功能。

---

## 問題十：postStart 在 MySQL 臨時 server 階段就執行

### 症狀

全新部署後，Writer 的 `repl` user 不存在。Reader 永遠卡在 PodInitializing 或 replication 靜默失敗。

### 根因

MySQL 官方 image（`mysql:8.0` 等）的 entrypoint 在首次初始化時會啟動一個**臨時 server**：

```
1. 臨時 server（初始化用）
   - Unix Socket：✅ 有綁定
   - TCP port：0（不開）
   - 用途：建立系統 DB、設定 root 密碼、建立 MYSQL_DATABASE

2. 正式 mysqld
   - Unix Socket：✅ 有綁定
   - TCP port：3306 ✅
```

`mysqladmin ping` 不加 `-h` 預設走 Socket → 臨時 server 回應 → postStart 以為就緒 → `CREATE USER repl` 失敗或消失 → `|| true` 吞掉。

**此行為與 Docker Desktop 無關**，任何使用 MySQL 官方 image 的 K8s 環境（EKS、GKE、AKS）都會發生。其他 image（Percona、MariaDB）entrypoint 不同，但 `-h 127.0.0.1` 仍是通用安全做法。

### 解法

postStart 中所有 `mysqladmin ping` 和 `mysql -e` 加上 `-h 127.0.0.1`，強制走 TCP：

```bash
# -h 127.0.0.1 = 仍然連容器內自己，但改用 TCP 協議
# 臨時 server 不開 TCP port → ping 不通 → 繼續等待
# 正式 mysqld 開 TCP 3306 → ping 通過 → 安全執行 DDL
until mysqladmin ping -h 127.0.0.1 -u root -p"${MYSQL_ROOT_PASSWORD}" --silent 2>/dev/null; do
  sleep 2
done
mysql -h 127.0.0.1 -u root -p"${MYSQL_ROOT_PASSWORD}" -e "CREATE USER ..." 2>/dev/null || true
```

**`-h 127.0.0.1` 的作用**：不是連到別台機器，是強制 MySQL client 從 Unix Socket 切換為 TCP 協議。目的地一樣是自己，但能區分臨時 server（無 TCP）和正式 mysqld（有 TCP）。

| | 不加 `-h`（Socket） | `-h 127.0.0.1`（TCP） |
|---|---|---|
| 臨時 server | 回應 ping | **不回應** |
| 正式 mysqld | 回應 ping | 回應 ping |
| 能區分兩階段 | **不能** | **能** |

### 驗證

```bash
# 從日誌確認兩個階段
kubectl logs {writer-pod} -n {namespace} | grep "port:"
# 臨時 server: port: 0
# 正式 mysqld:  port: 3306

# 修正後全新部署，repl user 應自動建立
kubectl exec {writer-pod} -n {namespace} -- bash -c \
  'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -N -e \
   "SELECT user, host, plugin FROM mysql.user WHERE user=\"repl\";"'
# 預期：repl  %  mysql_native_password
```

---

## 除錯速查指令

```bash
# 檢查 replication 狀態
kubectl exec {reader-pod} -n {ns} -- bash -c \
  'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SHOW REPLICA STATUS\G"' 2>&1 | \
  grep -E "Running|Error|Behind"

# 檢查 repl user 認證方式
kubectl exec {writer-pod} -n {ns} -- bash -c \
  'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -N -e \
   "SELECT user, host, plugin FROM mysql.user WHERE user=\"repl\";"'

# 檢查 read_only 狀態
kubectl exec {pod} -n {ns} -- bash -c \
  'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e \
   "SELECT @@hostname, @@read_only, @@super_read_only;"'

# 測試資料同步
kubectl exec {writer-pod} -n {ns} -- bash -c \
  'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e \
   "CREATE DATABASE IF NOT EXISTS test_db; USE test_db;
    CREATE TABLE IF NOT EXISTS t1 (id INT AUTO_INCREMENT PRIMARY KEY, v VARCHAR(50));
    INSERT INTO t1 (v) VALUES (\"test_$(date +%s)\");
    SELECT * FROM t1;"'

kubectl exec {reader-pod} -n {ns} -- bash -c \
  'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "USE test_db; SELECT * FROM t1;"'

# 測試 Reader 寫入被拒絕
kubectl exec {reader-pod} -n {ns} -- bash -c \
  'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e \
   "USE test_db; INSERT INTO t1 (v) VALUES (\"should_fail\");"'
# 預期：ERROR 1290 (HY000): --super-read-only

# 檢查所有 Reader 的 server-id（擴容後必驗）
for pod in $(kubectl get pods -n {ns} -l app.kubernetes.io/name=mysql-reader -o name); do
  echo "${pod}: $(kubectl exec ${pod} -n {ns} -- bash -c \
    'mysql -u root -p"$MYSQL_ROOT_PASSWORD" -N -e "SELECT @@server_id;"' 2>/dev/null)"
done

# Port forward 供 Navicat 等 GUI 工具連線
kubectl port-forward svc/mysql-writer -n {ns} 3307:3306 &
kubectl port-forward svc/mysql-reader -n {ns} 3308:3306 &
```
