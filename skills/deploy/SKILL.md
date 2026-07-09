---
name: deploy
description: >-
  當使用者要求「部署」、「deploy」、「上版」、「更新伺服器」、「發布到伺服器」、
  「推到線上」、「部署後端」、「部署前端」、「執行 devops 腳本」或需要透過
  SSH / AWS SSM / gcloud SSH 連線遠端伺服器執行標準化部署流程時觸發此技能。
version: 1.0.0
---

# 遠端部署技能 (Remote Deploy)

透過 SSH / AWS SSM / gcloud SSH 連線遠端伺服器，按照標準化目錄結構與流程執行部署。

---

## 伺服器標準目錄結構

```
/data/htdocs/{project}/          # 專案工作目錄（docker-compose.yml, .env）

/data/dev/git/{project}/         # 部署腳本 + git publish repos
├── backend/
│   ├── __publish_php/           # 後端 PHP git repo
│   ├── __publish_node/          # Node.js data source git repo
│   ├── __publish_python/        # Python demo data git repo
│   └── devops_php.sh            # 後端部署腳本
└── frontend/
    ├── __publish_frontend/      # 前端 user-facing git repo
    ├── __publish_bgm/           # 前端 admin git repo
    ├── devops_main.sh           # 前端 web 部署腳本
    └── devops_bgm.sh            # 前端 admin 部署腳本
```

> **注意**：`__publish_*` 就是 git clone 下來的原始碼目錄（改名而來），不是另外建的。

---

## 服務類型對照表

| 服務別名 | 位置 | `__publish_*` 目錄 | 部署腳本 | 說明 |
|----------|------|-------------------|---------|------|
| `backend` / `php` | `backend/` | `__publish_php` | `devops_php.sh` | 後端 PHP 服務 |
| `frontend` / `web` / `main` | `frontend/` | `__publish_frontend` | `devops_main.sh` | 前端 User Web |
| `bgm` / `admin` | `frontend/` | `__publish_bgm` | `devops_bgm.sh` | 前端 Admin |
| `node` | `backend/` | `__publish_node` | `devops_node.sh` | Node.js 資料源 |
| `all` | — | 以上全部 | 依序執行所有腳本 | 全服務部署 |

> 不同專案可能只有部分服務，以遠端伺服器上實際存在的 `__publish_*` 目錄與 `devops_*.sh` 為準。

### 前端 vs 後端部署差異

| | 後端（PHP/Go/Node） | 前端（Web/BGM） |
|---|---|---|
| **部署腳本** | `git_pull` → `docker_build` → `update_code` | `git_pull` → `docker_build` |
| **`update_code`** | 需要（原子替換 src 到 exec 目錄） | **不需要**（build 產物打包在 image 內） |
| **`EXEC_DIR`** | 需要 | **不需要** |
| **生效方式** | 替換 exec 目錄 + compose restart | compose restart（新 image 自帶 dist） |

---

## 連線方式

根據使用者指定或專案慣例，選擇以下連線方式之一：

### 1. SSH 直連

```bash
ssh {user}@{host} "cd /data/dev/git/{project} && bash devops_{service}.sh"
```

### 2. AWS SSM (Systems Manager)

優先使用 `mcp__awslabs_aws-api__call_aws` MCP 工具（名稱以 ToolSearch 實際載回為準）：

```
service: ssm
action: SendCommand
parameters:
  InstanceIds: ["{instance-id}"]
  DocumentName: "AWS-RunShellScript"
  Parameters:
    commands: ["cd /data/dev/git/{project} && bash devops_{service}.sh"]
```

若 MCP 不可用，降級為 AWS CLI：

```bash
aws ssm send-command \
  --instance-ids "{instance-id}" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cd /data/dev/git/{project} && bash devops_{service}.sh"]' \
  --output text
```

### 3. gcloud SSH

```bash
gcloud compute ssh {instance-name} --zone={zone} --project={gcp-project} \
  --command="cd /data/dev/git/{project} && bash devops_{service}.sh"
```

---

## 部署流程（標準化步驟）

### 步驟 0：斜線調用（/deploy）參數解析

以 `/deploy [參數]` 調用時，按位置解析；缺漏部分進步驟 1 互動補全：

```
/deploy {project}                                    → 其餘資訊互動詢問
/deploy {project} {service}                          → 詢問環境與連線資訊
/deploy {project} {service} {env} {method} {target}  → 完整參數，直接進摘要確認
```

| 位置 | 參數 | 範例 |
|------|------|------|
| 1 | 專案名 | `demo` |
| 2 | 服務類型 | `backend` / `frontend` / `node` / `all` |
| 3 | 環境 | `dev` / `uat` / `prod` |
| 4 | 連線方式 | `ssh` / `ssm` / `gcloud` |
| 5+ | 連線目標 | `root@1.2.3.4`、`i-0abc123`、`my-vm --zone=asia-east1-b` |

### 步驟 1：收集部署資訊

若使用者未提供完整資訊，互動式詢問：

| 資訊 | 必填 | 預設值 | 說明 |
|------|------|--------|------|
| 專案名 (`project`) | 是 | — | 如 `demo`、`shop` |
| 服務類型 (`service`) | 是 | `all` | `backend` / `frontend` / `node` / `all` |
| 環境 (`env`) | 否 | `dev` | `dev` / `uat` / `prod` |
| 連線方式 (`method`) | 是 | — | `ssh` / `ssm` / `gcloud` |
| 連線目標 | 是 | — | SSH: `user@host`；SSM: `instance-id`；gcloud: `instance-name + zone` |

### 步驟 2：顯示部署摘要並等待確認

**⚠️ 嚴禁未經確認直接執行部署。**

顯示格式：

```
## 部署摘要

| 項目 | 值 |
|------|-----|
| 專案 | {project} |
| 服務 | {service} |
| 環境 | {env} |
| 連線方式 | {method} |
| 目標 | {connection-target} |

### 將執行的操作

1. 連線至 {connection-target}
2. cd /data/dev/git/{project}/
3. cd __publish_{publish_dir} && git pull origin {env}
4. cd .. && bash devops_{script}.sh

確認執行？(Y/N)
```

### 步驟 3：執行部署

確認後，依序執行：

#### 3a. 連線並檢查目錄存在

```bash
# 檢查部署目錄是否存在
ls -la /data/dev/git/{project}/
```

若目錄不存在，**停止並回報**，不嘗試建立。

#### 3b. Git Pull（拉取最新代碼）

```bash
cd /data/dev/git/{project}/__publish_{publish_dir}
git pull origin {env}
```

顯示 git pull 結果，讓使用者確認拉取了哪些 commit。

#### 3c. 執行部署腳本

```bash
cd /data/dev/git/{project}
bash devops_{script}.sh
```

即時輸出腳本執行過程。

#### 3d. 多服務部署（`all`）

當 service 為 `all` 時，依以下順序執行：

1. `backend` / `php`（若存在）
2. `node`（若存在）
3. `frontend` / `web`（若存在）

每個服務獨立完成 git pull + 腳本執行，一個失敗則停止後續。

### 步驟 4：驗證與回報

部署完成後回報：

```
## 部署結果

| 服務 | Git Pull | 腳本執行 | 狀態 |
|------|----------|---------|------|
| {service} | ✅ {commit_count} commits | ✅ 成功 | 完成 |

部署完成時間：{timestamp}
```

---

## 安全規則

1. **確認先行**：所有部署操作在執行前必須顯示摘要並獲得使用者明確確認
2. **生產環境雙重確認**：當 `env=prod` 時，額外提示「⚠️ 您即將部署到 **生產環境**，請再次確認」
3. **不建立不存在的目錄**：若遠端目錄不存在，停止並回報，不自動建立
4. **即時輸出**：腳本執行過程需即時顯示，不可靜默等待
5. **失敗即停**：任一步驟失敗立即停止，回報錯誤原因

---

## 與其他 Skill 的關係

| Skill | 關係 |
|-------|------|
| `shell-gen` | shell-gen 負責「產生」devops_xxx.sh 腳本；deploy 負責「執行」部署 |
| `devops` | devops 負責容器化設定（Dockerfile、docker-compose）；deploy 負責遠端部署執行 |

---

## 腳本範本

> 部署腳本的標準格式與完整範本（函式結構、原子替換、main() 調度）由 `shell-gen` skill 擁有，本 skill 只負責「執行」。
