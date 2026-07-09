---
name: devops
description: 當使用者要求「將專案容器化」、「建立 Dockerfile」、「設定 docker-compose」、「新增 Docker 支援」、「建立 .dockerignore」、「建置 Docker 映像」、「建立 Makefile」、「設定 CI/CD」、「建立部署管線」或需要有關多階段 Docker 建置、容器編排、CI/CD 管線或使用 Docker 進行生產部署的指導時，應使用此技能。
version: 1.0.0
---

# DevOps 容器化與 CI/CD

將後端與前端服務容器化，使用優化的 Docker 映像、Docker Compose 編排、生產環境就緒的 Makefile，以及 CI/CD 管線配置。

**重要**：所有 Dockerfile 檔名統一使用**小寫** `dockerfile`。

## 核心原則

- **專案目錄驅動** — 所有容器化決策必須基於實際專案目錄掃描結果，禁止憑假設生成檔案。
- **最小化映像** — 使用多階段建置；生產映像僅包含運行時必要元件。
- **安全優先** — 以非 root 使用者運行，排除機密資料，避免不必要的套件。
- **快取友善** — 將低變動步驟（依賴安裝）放在高變動步驟（程式碼複製）之前，以最大化層快取效果。
- **可觀測性** — 包含健康檢查端點與容器層級的 `HEALTHCHECK` 指令。
- **零內嵌配置** — dockerfile 中**嚴禁使用 `ENV` 設定應用程式配置**（port、mode、DB 連線等）。所有配置一律透過外部注入（docker-compose `env_file` / `environment`、`docker run -e`），確保 debug 時配置來源單一、可追蹤。
- **環境一致性** — 每個服務使用單一 dockerfile，透過 docker-compose 的 `env_file` 或 `environment` 區分 dev/UAT/production。
- **統一工作目錄** — 所有服務的最終 Runtime 階段統一在 `/app` 目錄下運行（包含前端 Nginx 服務）。
- **Makefile 為 CI/CD 唯一入口** — 所有建置、推送、掃描操作統一透過 Makefile 目標執行，CI/CD 管線僅呼叫 `make` 指令。

---

## 工作流程（必須按順序執行）

### 步驟 1：掃描專案目錄結構

**此步驟為強制前置步驟，不可跳過。**

當此 Skill 被調用時，必須先對用戶指定的專案目錄（或當前工作目錄）進行完整掃描，建立專案結構全貌：

#### 1a. 目錄樹掃描

使用 `ls`、`tree`（深度 3 層）或 Glob 工具掃描專案目錄，取得完整目錄結構：

```bash
# 取得目錄樹（排除常見非必要目錄）
tree -L 3 -I 'node_modules|vendor|.git|__pycache__|dist|build|.next' {project-dir}
```

需要辨識的目錄模式：

| 專案結構 | 特徵 | 說明 |
|----------|------|------|
| Monorepo | 根目錄下有 `backend/`、`frontend/`、`services/` 等子目錄 | 多服務專案，需個別掃描每個服務 |
| 單一後端服務 | 根目錄直接有 `go.mod`、`requirements.txt`、`package.json` 等 | 單一服務專案 |
| 單一前端服務 | 根目錄有 `package.json` + `vite.config.*` / `next.config.*` 等 | 純前端專案 |
| 微服務 | `services/` 或 `apps/` 下有多個獨立子服務 | 需逐一掃描每個子服務 |

#### 1b. 服務發現

對每個發現的服務目錄，使用 Glob 或 Read 工具讀取以下標誌檔案來判定語言與技術棧：

| 偵測標誌 | 判定語言 | 需讀取的版本資訊 | 基礎映像 | 依賴快取策略 | 啟動指令 |
|----------|----------|-----------------|----------|-------------|----------|
| `go.mod` | Go | 讀取 `go.mod` 中的 `go` 版本行 | `golang:{version}-alpine` → `alpine` | 先 `COPY go.mod go.sum` → `go mod download` | 編譯後的二進位檔 |
| `requirements.txt` 或 `pyproject.toml` | Python | 讀取 `.python-version` 或 `pyproject.toml` 中的 `python` 版本 | `python:{version}-slim` | 先 `COPY requirements.txt` → `pip install` | `gunicorn` / `uvicorn` |
| `package.json` + 無 `vite.config` | Node.js (API) | 讀取 `package.json` 的 `engines.node` | `node:{version}-alpine` | 先 `COPY package*.json` → `npm ci` | `node server.js` |
| `package.json` + `vite.config.*` | 前端 (Vite) | 讀取 `package.json` 的 `engines.node` | `node:{version}-alpine` → `nginx:alpine` | 先 `COPY package*.json` → `npm ci` | `nginx -g 'daemon off;'` |
| `package.json` + `next.config.*` | 前端 (Next.js) | 讀取 `package.json` 的 `engines.node` | `node:{version}-alpine` | 先 `COPY package*.json` → `npm ci` | `node server.js` 或 `next start` |
| `composer.json` | PHP | 讀取 `composer.json` 的 `require.php` | `php:{version}-fpm-alpine` | 先 `COPY composer.*` → `composer install` | `php-fpm` |
| `Cargo.toml` | Rust | 讀取 `Cargo.toml` 的 `edition` / `rust-version` | `rust:{version}` → `debian:slim` | 先 `COPY Cargo.*` → `cargo build --release` | 編譯後的二進位檔 |
| `pom.xml` 或 `build.gradle` | Java | 讀取 `pom.xml` 的 `java.version` 或 `build.gradle` 的 `sourceCompatibility` | `eclipse-temurin:{version}` → `eclipse-temurin:{version}-jre` | 先 `COPY pom.xml` → `mvn dependency:resolve` | `java -jar app.jar` |

#### 1c. 深度分析每個服務

對每個偵測到的服務，**必須使用 Read 工具**讀取以下檔案以蒐集建置所需資訊：

1. **依賴描述檔**：讀取 `go.mod`、`package.json`、`requirements.txt` 等，確認語言版本與依賴清單
2. **進入點檔案**：讀取 `main.go`、`cmd/*/main.go`、`app.py`、`server.js`、`src/main.ts` 等，確認啟動指令與監聽埠號
3. **現有配置**：檢查是否已有 `.devops/dockerfile`、`.dockerignore`、`docker-compose.yml`、`Makefile`，避免覆蓋現有設定
4. **健康檢查端點**：搜尋程式碼中是否有 `/health`、`/healthz`、`/ready`、`/ping` 等端點定義
5. **建置腳本**：讀取 `Makefile`、`package.json` 的 `scripts` 區塊，了解現有的建置流程
6. **環境變數用法**：掃描 `.env.example`、`.env.sample` 或程式碼中的環境變數引用，了解配置需求
7. **CI/CD 配置**：檢查是否已有 `.github/workflows/`、`.gitlab-ci.yml`、`Jenkinsfile` 等 CI/CD 配置

#### 1d. 目錄命名合規性檢查（MANDATORY）

掃描完成後，**必須**比對現有目錄/檔案命名是否符合本 Skill 的輸出規格：

| 規範路徑 | 常見偏差 | 處理方式 |
|----------|---------|---------|
| `.devops/` | `devops/`（無點前綴） | 改名為 `.devops/` |
| `.devops/dockerfile` | `Dockerfile`、`dockerfile-prod` | 視情況保留或重命名 |
| `.devops/exec/autoversion/` | `devops/tools/autoversion/` | 改名至規範路徑 |

**改名操作規則**：
1. **全專案全量搜尋**：對**整個專案根目錄**（非僅服務目錄）執行 `grep -r "舊名稱"` — **不可限定檔案類型**。改名影響範圍包含但不限於：
   - 服務內部：Makefile、dockerfile（`COPY`/`ADD`）、.dockerignore
   - 服務外部：根目錄部署腳本（`devops_*.sh`）、docker-compose.yml、CI/CD 配置（`buildspec.yml`、`.github/workflows/`、`.gitlab-ci.yml`）、其他服務的交叉引用
2. **列出所有引用**：在藍圖中明確列出**所有**需要同步更新的檔案與行號（含服務外部檔案）
3. **改名後驗證**：再次對整個專案根目錄全量搜尋舊名稱，確認零殘留（已註解的行可忽略）
4. **建置驗證**：改名後必須執行 `make build-dev` 確認建置正常

#### 1e. 回報掃描結果並等待確認

將掃描結果以表格形式回報用戶，**必須等待用戶確認後**才進入步驟 2：

```
## 專案掃描結果

| # | 服務路徑 | 語言/框架 | 版本 | 監聽埠號 | 健康檢查 | 現有 dockerfile | 現有 Makefile |
|---|---------|-----------|------|---------|---------|----------------|--------------|
| 1 | backend/go/ | Go | 1.23 | 8080 | /health | 無 | 無 |
| 2 | frontend/web/ | Vite + React | Node 20 | 3000→80 | N/A | 已存在 | 已存在 |

## 命名合規性檢查

| 現有路徑 | 規範路徑 | 需改名 | 受影響檔案數 |
|----------|---------|--------|-------------|
| backend/go/devops/ | backend/go/.devops/ | ✅ | 3（Makefile, dockerfile, ci.yml） |
| frontend/web/.devops/ | frontend/web/.devops/ | ❌ 已合規 | — |

需要建立/調整的檔案：
- [ ] backend/go/devops/ → 改名為 .devops/（含同步更新 3 個引用）
- [ ] backend/go/.devops/dockerfile
- [ ] backend/go/.dockerignore
- [ ] backend/go/Makefile（含完整 Docker + CI/CD 目標）
- [ ] frontend/web/Makefile（含完整 Docker + CI/CD 目標）

是否確認以上方案？
```

---

### 步驟 2：生成容器化與 CI/CD 檔案

用戶確認後，按以下順序為**每個服務**建立：

1. `{service-dir}/.devops/dockerfile` — 依偵測語言生成對應的多階段 dockerfile
2. `{service-dir}/.dockerignore` — 依語言排除不必要檔案
3. `{service-dir}/.devops/nginx.conf` — 僅前端服務需要
4. `{service-dir}/.devops/exec/autoversion/post-commit` — Git post-commit hook
5. `{service-dir}/.devops/exec/autoversion/autoversion.py` — 版本管理 Python 腳本
6. `{service-dir}/Makefile` — **完整的 Docker + CI/CD + auto-version Makefile**（若已有 Makefile 則追加相關目標）

### 步驟 3：驗證建置

```bash
cd {service-dir}

# 使用 Makefile 建置開發映像
make build-dev

# 使用 Makefile 建置生產映像
make build-prod REPO={registry}/{project}/{service}:0.1.0
```

### 步驟 4：詢問是否建立 docker-compose

所有服務的容器化檔案皆生成完畢後，**最後**詢問用戶是否需要建立 `docker-compose.yml` 來編排多個服務：

```
所有服務的 dockerfile 與 Makefile 已建立完成。

是否需要建立 docker-compose.yml 來統一編排以上 {N} 個服務？(Y/N)
```

若用戶同意，則在專案根目錄建立 `docker-compose.yml`（詳見「Docker Compose 規格」章節）。

### 步驟 5：詢問是否建立 CI/CD 管線

```
是否需要建立 CI/CD 管線配置？

1. Jenkins + AWS CodeBuild（Jenkinsfile + buildspec.yml）— 工具箱預設方案
2. 其他平台（GitHub Actions / GitLab CI 等）— 依專案現有 CI 配置討論
3. 不需要

請選擇：
```

若用戶同意，依 **`references/jenkinsfile-codebuild.md`** 生成 Jenkinsfile 與 buildspec.yml。

### 步驟 6：清理

```bash
docker compose down -v
docker image prune -f
```

---

## 輸出檔案結構

```text
{service-dir}/
├── .devops/
│   ├── dockerfile              # 多階段 dockerfile（小寫 d）
│   ├── nginx.conf              # 僅前端服務需要
│   └── exec/
│       └── autoversion/
│           ├── post-commit     # Git post-commit hook
│           └── autoversion.py  # 版本管理 Python 腳本
├── .dev/                       # make auto-version 安裝後產生（加入 .gitignore）
│   └── autoversion.py
├── .dockerignore
├── version.json                # 自動版本號（由 hook 管理）
└── Makefile                    # 完整 Docker + CI/CD + auto-version Makefile
```

專案根目錄（可選）：
```text
project-root/
├── docker-compose.yml          # 多服務編排
├── docker-compose.prod.yml     # 生產環境覆寫（選用）
└── .github/workflows/          # CI/CD 管線（選用）
    ├── ci.yml                  # 建置 + 測試
    └── cd.yml                  # 部署
```

> **注意**：dockerfile 路徑統一為 `.devops/dockerfile`（小寫 d）。

---

## 後端 dockerfile 規格

路徑：`{backend-dir}/.devops/dockerfile`

1. **基礎映像**：依步驟 1 偵測結果選用對應語言的官方映像，鎖定具體版本。
2. **多階段建置**：Builder 階段安裝依賴與編譯；Runtime 階段僅複製運行所需的產物。
3. **依賴快取**：先複製依賴描述檔（`go.mod`、`requirements.txt`、`package.json` 等），安裝後再複製原始碼，最大化層快取。
4. **非 root 使用者**：建立 `appuser`，以非 root 身份運行。
5. **禁止 ENV**：dockerfile 中**不得使用 `ENV`** 設定任何應用程式配置（port、mode、DB 等）。僅使用 `EXPOSE` 標記固定埠號（來自步驟 1c 掃描到的實際埠號）。所有配置由 docker-compose `env_file` 或 `environment` 在運行時注入。
6. **HEALTHCHECK**：依步驟 1c 掃描結果，若有健康檢查端點則加入 `HEALTHCHECK` 指令，否則不加。

## 前端 dockerfile 規格

路徑：`{frontend-dir}/.devops/dockerfile`

1. **多階段建置**：Node.js 階段執行 `npm ci` + 建置指令（來自 `package.json` scripts 掃描結果）；Nginx 階段僅提供 `dist/` 靜態檔案。
2. **Nginx 配置**：自訂 `nginx.conf`，包含 SPA 路由（`try_files $uri /index.html`）、日誌輸出至 stdout/stderr（`access_log /dev/stdout; error_log /dev/stderr warn;`）、安全標頭、健康檢查端點（`/health`）。
3. **非 root 使用者**：使用 Nginx 內建的 `nginx` 使用者，**必須在建置階段處理以下權限問題**（否則 K8s `runAsNonRoot` 環境會啟動失敗）：
   - **監聽端口**：非 root 無法綁定 < 1024 的特權端口，nginx.conf 必須改為 `listen 8080`（而非 80），K8s Service 再將 80 映射到 containerPort 8080
   - **PID 檔案**：預設 `/run/nginx.pid` 僅 root 可寫，必須用 `sed` 改為 `/tmp/nginx.pid`
   - **Cache 子目錄**：nginx 啟動時 master process 會 `chown` 五個 cache 子目錄（`client_temp`、`proxy_temp`、`fastcgi_temp`、`uwsgi_temp`、`scgi_temp`），在 non-root 環境下 chown 會因 `Operation not permitted` 失敗。**必須在 Dockerfile 中預先建立這五個子目錄並 chown 給 nginx**，nginx 啟動時發現目錄已存在且權限正確則跳過 chown
   - **conf.d 目錄**：entrypoint 腳本會嘗試修改 `default.conf`，目錄需 `chown` 給 nginx
   - **具體做法**：
     ```dockerfile
     RUN sed -i 's|/run/nginx.pid|/tmp/nginx.pid|' /etc/nginx/nginx.conf \
         && mkdir -p /var/cache/nginx/client_temp \
                     /var/cache/nginx/proxy_temp \
                     /var/cache/nginx/fastcgi_temp \
                     /var/cache/nginx/uwsgi_temp \
                     /var/cache/nginx/scgi_temp \
         && chown -R nginx:nginx /var/cache/nginx /tmp /app /etc/nginx/conf.d
     COPY --chown=nginx:nginx .devops/nginx.conf /etc/nginx/conf.d/default.conf
     USER nginx
     ```
4. **HEALTHCHECK**：搭配 nginx.conf 中的 `/health` 端點，加入容器層級健康檢查。
5. **運行時環境變數**：如有需要，啟動時使用 `envsubst` 注入。

---

## Makefile 規格

路徑：`{service-dir}/Makefile`

每個服務目錄**必須**生成完整的 Makefile，作為 Docker 建置與 CI/CD 的**唯一入口**。

### 設計原則

1. **Container Runtime 自動偵測** — 優先使用 `docker`，fallback 到 `nerdctl`，自動處理 namespace 差異。
2. **REPO 參數驅動** — 生產建置使用完整的 `REPO`（含 registry + tag），而非拆分 IMAGE_NAME + TAG。
3. **彩色終端輸出** — 使用 ANSI 顏色碼提升可讀性。
4. **CI/CD 友善** — 所有目標可直接被 CI/CD 管線呼叫，無需額外腳本。

### 基本結構

若服務目錄已有 Makefile，**不可覆蓋**，應將 Docker 相關目標**追加**到現有 Makefile 中（確認無命名衝突後）。

詳細的 Makefile 範本請參閱 **`references/makefile-cicd.md`**。

### 必要目標清單

| 目標 | 說明 | 用途 |
|------|------|------|
| `help` | 顯示所有可用指令（含彩色格式化） | 預設目標 |
| `build-dev` | 建置開發環境映像 | 本地開發 |
| `build-prod` | 建置生產環境映像（需指定 `REPO`） | CI/CD 建置 |
| `push` | 推送映像至 Registry（需指定 `REPO`） | CI/CD 部署 |
| `scan` | 掃描映像安全漏洞 | CI/CD 安全檢查 |
| `lint-dockerfile` | 檢查 dockerfile 最佳實踐 | CI/CD 品質檢查 |
| `info-image` | 顯示映像詳細資訊（大小、層數） | 除錯輔助 |
| `clean` | 清理本地開發映像與懸掛映像 | 本地維護 |
| `auto-version` | 安裝自動版本管理（Git hook + Python 腳本） | 版本管理 |

### 多服務變體

若步驟 1 掃描發現服務目錄下有多個子服務（例如多個微服務共用同一個 `go.mod`），則為每個子服務生成獨立的建置目標：

```makefile
build-{sub-service}: ## 建置 {sub-service} Docker 映像（需指定 REPO）
	$(MAKE) check-repo-param REPO=$(REPO)
	$(CR) $(CR_NS) build -t $(REPO) -f .devops/dockerfile-{sub-service} .
```

### 命名規則

| 項目 | 規則 | 範例 |
|------|------|------|
| `DOCKER_IMAGE_NAME` | `{service-name}`，全小寫，用於 `build-dev` 的本地映像名 | `lottery-frontend` |
| `REPO` 參數 | 完整映像路徑（含 registry + tag），由用戶或 CI/CD 傳入 | `gcr.io/myproj/frontend:1.2.3` |
| 目標名稱 | 全小寫，以 `-` 分隔 | `build-prod`、`build-dev`、`lint-dockerfile` |

---

## CI/CD 管線規格（Jenkins + AWS CodeBuild）

工具箱預設 CI/CD 方案為 **Jenkins（調度） + AWS CodeBuild（建置） + Discord Webhook（通知）**；專案 CLAUDE.md 另有 CI 平台則從專案。

### 原則

- **Makefile 為唯一入口**：CodeBuild 的 buildspec.yml 中所有建置步驟僅呼叫 `make` 指令。
- **Tag-based 部署**：打 `*-test`、`*-prod`、`*-hotfix` tag 觸發對應環境的 CodeBuild。
- **Immutable Tag**：每次建置自動產生 `{version}-{env}-{hash}` 格式的不可變標籤。
- **Discord 即時通知**：單則訊息編輯模式，即時更新建置進度與結果。

### 詳細範本

詳見 **`references/jenkinsfile-codebuild.md`**，包含：

- 完整 Jenkinsfile 範本（含配置區 + 共用函數）
- 後端 / 前端 buildspec.yml 範本
- 新增專案 Checklist
- Tag 命名規則與 Image Tag 規則

---

## Docker Compose 規格（選用）

路徑：專案根目錄 `docker-compose.yml`

1. **服務**：依步驟 1 掃描到的所有服務動態定義，每個服務的 `build.context` 與 `build.dockerfile` 須對應實際掃描路徑。
2. **網路**：自訂橋接網路供服務間通訊。
3. **掛載卷**：開發模式下掛載原始碼以支援熱載入。
4. **depends_on**：前端依賴後端，條件為健康檢查通過。
5. **env_file**：每個服務引用各自的 `.env` 檔案。
6. **埠號映射**：依步驟 1c 掃描到的實際監聽埠號設定 `ports`。

---

## 最佳實踐

- **日誌輸出至 stdout/stderr** — 容器內應用程式的日誌必須輸出到標準輸出（stdout）與標準錯誤（stderr），不寫入檔案。這是容器化的標準做法，確保 `docker logs`、`kubectl logs` 和日誌收集器（Fluentd/Loki）能正確採集。Nginx 需在 server block 中明確設定 `access_log /dev/stdout; error_log /dev/stderr warn;`。
- **絕不將 `.env` 包含在映像中。** 透過 `env_file` 或編排工具在運行時注入。
- **鎖定基礎映像版本**（例如 `golang:1.23-alpine`、`node:20-alpine`）。禁用 `latest`。
- **在 CI/CD 中使用 `docker build --no-cache`** 進行發行版建置。
- **檢查映像大小**：編譯型語言（Go/Rust）後端 < 50MB，直譯型語言後端 < 200MB，前端 < 50MB。
- **掃描安全漏洞**：使用 `docker scout` 或 `trivy`。
- **避免覆蓋**：若步驟 1c 偵測到已有 dockerfile 或 docker-compose，應先比對差異，詢問用戶是更新還是略過。
- **改名必須全專案全量掃描**：任何目錄或檔案改名操作，必須對**整個專案根目錄**（非僅服務目錄）執行無檔案類型限制的全量搜尋（`grep -r "舊名稱" {project-root}/`），因為引用可能存在於服務外部（根目錄部署腳本、CI/CD buildspec、docker-compose、其他服務的交叉引用等）。找出所有引用並一併更新，改名後再次全量搜尋確認零殘留，最後 `make build-dev` 驗證建置。

---

## 踩雷 SOP（歷史 incident 整理）

> 以下為導入 / 變更 CI/CD 時容易踩到的雷與對應修法。**任何路徑或 target 命名變動後，請對照此清單檢查**。

### 1. buildspec 路徑變動 → 必須 update CodeBuild project

CodeBuild project 的 `source.buildspec` 欄位是**寫死**在 AWS project config 內，不會跟著 repo 自動更新。

**症狀**：
```
Phase context status code: YAML_FILE_ERROR
Message: stat .../path/to/buildspec.yml: no such file or directory
```

**觸發條件**：
- 把 `devops/` 改名為 `.devops/`（或任何目錄重命名）
- 把 `buildspec.yml` 改為 `buildspec-<service>.yml`
- 把 buildspec 從 repo 根目錄搬到子目錄

**修法**：路徑變動後立即同步 AWS：
```bash
aws codebuild update-project \
  --name <project-name> \
  --region <aws-region> \
  --source type=GITLAB_SELF_MANAGED,location=<gitlab-url>,gitCloneDepth=1,buildspec=<new-buildspec-path>
```

### 2. Jenkins 創 tag 撞 local 殘留

Jenkins workspace 的 git working tree 可能繼承自舊 repo 或前次手動測試，**local 仍有殘留 tag**。

**症狀**：
```
+ git tag <tag-name>
fatal: tag '<tag-name>' already exists
```

**錯誤假設**：「Jenkins SCM 用 `--no-tags` fetch，所以 `git tag -l` 永遠是空」— 這個假設在 workspace 不純淨時會失效。

**修法**：`createAndPushTag` / `createImmutableTag` 必須無條件清 local 殘留 + 查 remote。詳見 `references/jenkinsfile-codebuild.md` 內兩個 function 的範本。

### 3. K8s `rollout restart` 1-second 限制

`kubectl rollout restart` 本質是給 deployment template 加 annotation `kubectl.kubernetes.io/restartedAt`，**精度只到秒**。1 秒內重複觸發會被 K8s 拒絕。

**症狀**：
```
error: failed to create patch for <deployment>: if restart has already been triggered 
within the past second, please wait before attempting to trigger another
```

**觸發條件**：
- Jenkins 同時跑兩個 build（如 `*-feat` push 同時觸發了 `Auto Tag dev` + `Deploy dev tag` 雙 job）
- 兩個 build 各自的 ansible playbook 幾乎同時抵達 rollout 階段

**修法**（擇一）：
- 在部署腳本對 `kubectl rollout restart` 加 `sleep 2` 後再執行
- 或加 retry 機制（失敗 sleep 2s 重試 2–3 次）
- 或改用 `kubectl patch` 自定義 annotation 並用毫秒精度 timestamp

### 4. nerdctl build → K8s pod 拉不到 image

**症狀**：image build 成功，但 `kubectl get pod` 顯示 `ImagePullBackOff` / `ErrImageNeverPull`。

**根因**：nerdctl 預設用 containerd `default` namespace，但 K8s 只看 `k8s.io` namespace。

**修法**：地端 nerdctl build 必須帶 `NAMESPACE=k8s.io`，或在 Makefile 把 `NAMESPACE ?=` 預設改為 `k8s.io`（限「主要部署場景是地端 nerdctl → K8s」的服務）。docker runtime 不受影響（`docker` 沒有 namespace 概念）。

### 5. CodeBuild buildspec 路徑讀取

CodeBuild 讀 buildspec 有三種來源，**寫死 vs 隨 repo 走** 各有 trade-off：

| 來源 | 行為 | 改路徑要動哪裡 |
|---|---|---|
| project source.buildspec（**目前範本採用**）| 寫死在 AWS project | `aws codebuild update-project` |
| repo 根目錄預設 `buildspec.yml` | CodeBuild 自動找 | 改檔名 / 路徑即可（AWS 無需動）|
| `start-build --buildspec-override` | Jenkinsfile 動態傳 | 改 Jenkinsfile（AWS 無需動）|

預設用第一種（明確、清晰）；若不希望「改路徑要兩邊同步」可考慮第二/三種。

### 6. Discord embed 模板的 `stripIndent()` 被多行插值破功

Groovy `"""...""".stripIndent()` 剝的是「**全部行的最小縮排**」。模板內插值若展開成多行
（如 `${detailLines.join('\n')}`），第 2 行起是**頂格**插入 → 最小縮排 = 0 → 整段一格都不剝。

**症狀**：一般文字 Discord 渲染會忽略行首空格、看不出異狀；但 ``` code block 內空格**原樣保留**
—— 一鍵複製內容前面多 4 空格、Copy 按鈕連空格一起複製。單服務 repo（插值只有 1 行）正常，
多服務 repo 一上多行就露餡 —— 同一份代碼、資料量不同結果不同，很難在單服務 repo 測出來。

**修法**：code block 區段移到 `stripIndent()` **之後**頂格串接
（`.stripIndent() + "\n📋 **一鍵複製**\n\`\`\`\n${copyText}\n\`\`\`"`），不寫進縮排模板內。
範本見 `references/jenkinsfile-codebuild.md` 的 `updateDiscordWithFinalResults`。

---

## 參考資料

如需詳細範本與配置，請查閱：

- **`references/jenkinsfile-codebuild.md`** — Jenkinsfile + AWS CodeBuild buildspec.yml 範本（工具箱預設 CI/CD 方案）
- **`references/makefile-cicd.md`** — 完整 Makefile 範本（含 Container Runtime 偵測、CI/CD 目標、auto-version、彩色輸出）
- **`references/dockerfile-templates.md`** — 各語言的 dockerfile 範本（含註解）
- **`references/compose-and-nginx.md`** — Docker Compose 與 Nginx 配置範本
- **`references/dockerignore-gitignore.md`** — 各語言的 .dockerignore 與 .gitignore 範本
- **`references/registry/`** — 各雲 Container Registry 對接（`aliyun-acr.md`、`gcp-artifact-registry.md`：認證、免密拉鏡像、命名慣例）
- **`references/auto-version.md`** — 自動版本管理系統（Git hook + Python 腳本、前綴對照表、完整範本）
