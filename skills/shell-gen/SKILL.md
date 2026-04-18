---
name: shell-gen
description: 當使用者貼上 shell script 要求「重構」、「標準化」、「整理腳本」，或給專案名要求「產生部署腳本」、「寫 devops shell」、「建立自動化腳本」、「寫 devops_php.sh」、「寫 devops_node.sh」、「產生 devops_xx.sh」時觸發此技能。
version: 1.0.0
---

# Shell Script 標準化產生器

將隨意撰寫的部署 shell script 重構為標準化格式，或根據專案名與需求從零產生規範化的部署腳本。

## 觸發場景

1. **重構模式** — 使用者貼上現有 shell script，要求重構/標準化
2. **產生模式** — 使用者給專案名 + 需求（前端/後端），要求產生 `devops_xx.sh`

---

## 伺服器標準目錄結構

```
/data/dev/git/{project}/
├── backend/          # 後端原始碼（git repo）
│   └── devops/       # dockerfile, configs
└── frontend/         # 前端原始碼（git repo）
    └── devops/       # dockerfile, configs

/data/dev/{project}/
├── docker-compose.yml
└── exec/
    ├── php/          # 後端執行目錄
    │   └── src/
    └── web/          # 前端執行目錄
        └── dist/
```

部署腳本位置：
- `/data/dev/git/{project}/devops_php.sh` — 後端部署
- `/data/dev/git/{project}/devops_node.sh` — 前端部署

---

## 輸出規範

所有產生的腳本必須遵循以下標準結構：

### 1. 檔頭與安全設定

```bash
#!/bin/bash
set -e
set -o pipefail
```

### 2. 變數區塊（集中宣告，禁止硬編碼）

```bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXEC_DIR=/data/dev/{project}/exec/{service}

CONTAINER_IMAGE={project}/{service}
XG_ENV=dev
```

| 變數 | 說明 | 命名規則 |
|------|------|---------|
| `DIR` | 腳本所在目錄 | 固定寫法 |
| `EXEC_DIR` | 服務執行目錄 | `/data/dev/{project}/exec/{service}` |
| `CONTAINER_IMAGE` | Docker image 名稱 | `{project}/{service}` |
| `XG_ENV` | 環境標識 | `dev` / `uat` / `prod` |

### 3. 函式化（每個步驟獨立函式）

必備函式依服務類型：

#### 後端（PHP/Go）— `devops_php.sh` / `devops_go.sh`

```bash
git_pull(){
  echo "--- cd & git pull code ---"
  git pull origin $XG_ENV
}

docker_build(){
  echo "--- image build ---"
  make build-prod REPO=$CONTAINER_IMAGE:$XG_ENV DOCKERFILE_PATH=./devops/dockerfile
}

docker_CI_TEST(){
  echo "--- CI Test ---"
  make docker-ci-test DOCKER_IMAGE_NAME=$CONTAINER_IMAGE
}

update_code(){
  echo "--- update docker compose ---"
  docker-compose -f $EXEC_DIR/../../docker-compose.yml up {service} -d

  echo "--- update exec ---"
  cp -rf $DIR/__publish_{service}/src/ $EXEC_DIR/src_temp
  mv $EXEC_DIR/src $EXEC_DIR/src_before
  mv $EXEC_DIR/src_temp $EXEC_DIR/src
  rm -rf $EXEC_DIR/src_before

  cp -rf $DIR/__publish_{service}/devops $EXEC_DIR/
}
```

#### 前端（Node/Vue）— `devops_node.sh`

```bash
git_pull(){
  echo "--- cd & git pull code ---"
  git pull origin $XG_ENV
}

docker_build(){
  echo "--- image build ---"
  make build-prod REPO=$CONTAINER_IMAGE:$XG_ENV DOCKERFILE_PATH=./devops/dockerfile
}

update_code(){
  echo "--- update docker compose ---"
  docker-compose -f $EXEC_DIR/../../docker-compose.yml up web -d

  echo "--- update exec ---"
  cp -rf $DIR/__publish_frontend/dist/ $EXEC_DIR/dist_temp
  mv $EXEC_DIR/dist $EXEC_DIR/dist_before
  mv $EXEC_DIR/dist_temp $EXEC_DIR/dist
  rm -rf $EXEC_DIR/dist_before
}
```

### 4. 原子替換模式（禁止直接覆蓋）

複製檔案時必須使用三步原子替換，避免服務中斷：

```bash
# 正確 ✅ — 原子替換
cp -rf $SOURCE $EXEC_DIR/src_temp    # 1. 複製到暫存
mv $EXEC_DIR/src $EXEC_DIR/src_before  # 2. 備份舊版
mv $EXEC_DIR/src_temp $EXEC_DIR/src    # 3. 切換新版
rm -rf $EXEC_DIR/src_before            # 4. 清除備份

# 錯誤 ❌ — 直接覆蓋
cp -rf $SOURCE $EXEC_DIR/src/
```

### 5. main() 入口統一調度

```bash
main(){
  cd $DIR/__publish_{service}
  git_pull
  docker_build
  #docker_CI_TEST
  update_code
  docker exec nginx nginx -s reload
}

main
```

- `main()` 是唯一執行入口
- 函式呼叫順序清晰可見
- 可快速註解/取消註解步驟（如 CI test）

### 6. Nginx reload（如需要）

若服務有 Nginx 反向代理，在 `main()` 最後加入：

```bash
docker exec nginx nginx -s reload
```

---

## 重構規則

當使用者貼上現有腳本時，依以下規則轉換：

| 原始寫法 | 標準化寫法 |
|----------|-----------|
| 命令平鋪，無函式 | 拆分為 `git_pull`、`docker_build`、`update_code` 等函式 |
| 硬編碼路徑 (`/data/htdocs/141/...`) | 提取為 `EXEC_DIR` 變數 |
| 硬編碼 image (`141/php:dev`) | 提取為 `CONTAINER_IMAGE` + `XG_ENV` |
| `docker build` 裸命令 | 改用 `make build-prod REPO=... DOCKERFILE_PATH=...` |
| `cp -rf src/ dest/` 直接覆蓋 | 三步原子替換 |
| 無入口函式 | 包裹在 `main()` 中 |
| `echo "--- xxx ---"` 訊息不一致 | 統一格式 `echo "--- {動作描述} ---"` |
| `BRANCH_NAME` 變數名 | 統一改為 `XG_ENV` |

---

## 產生模式工作流

當使用者給專案名要求產生腳本時：

### 步驟 1：確認資訊

詢問使用者（如未提供）：

| 資訊 | 預設值 | 說明 |
|------|--------|------|
| 專案名 | （必填） | 如 `141`、`california` |
| 服務類型 | 前端+後端 | `backend` / `frontend` / 兩者 |
| 後端語言 | PHP | `php` / `go` |
| 環境 | `dev` | `dev` / `uat` / `prod` |
| 是否需要 CI test | 否 | 加入 `docker_CI_TEST` 函式 |
| 是否需要 nginx reload | 是 | 結尾加入 reload |

### 步驟 2：產生腳本

根據上述資訊，套用標準模板產生：
- `devops_php.sh` 或 `devops_go.sh`（後端）
- `devops_node.sh`（前端）

### 步驟 3：輸出位置

腳本預設產生在：
```
/data/dev/git/{project}/devops_php.sh
/data/dev/git/{project}/devops_node.sh
```

---

## 完整範例

### 後端 `devops_php.sh`

```bash
#!/bin/bash
set -e
set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXEC_DIR=/data/dev/california/exec/php

CONTAINER_IMAGE=california/php
XG_ENV=dev

git_pull(){
  echo "--- cd & git pull code ---"
  git pull origin $XG_ENV
}

docker_build(){
  echo "--- image build ---"
  make build-prod REPO=$CONTAINER_IMAGE:$XG_ENV DOCKERFILE_PATH=./devops/dockerfile
}

docker_CI_TEST(){
  echo "--- CI Test ---"
  make docker-ci-test DOCKER_IMAGE_NAME=$CONTAINER_IMAGE
}

update_code(){
  echo "--- update docker compose ---"
  docker-compose -f $EXEC_DIR/../../docker-compose.yml up php -d

  echo "--- update exec ---"
  cp -rf $DIR/__publish_php/src/ $EXEC_DIR/src_temp
  mv $EXEC_DIR/src $EXEC_DIR/src_before
  mv $EXEC_DIR/src_temp $EXEC_DIR/src
  rm -rf $EXEC_DIR/src_before

  cp -rf $DIR/__publish_php/devops $EXEC_DIR/
}

main(){
  cd $DIR/__publish_php
  git_pull
  docker_build
  #docker_CI_TEST
  update_code
  docker exec nginx nginx -s reload
}

main
```

### 前端 `devops_node.sh`

```bash
#!/bin/bash
set -e
set -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXEC_DIR=/data/dev/california/exec/web

CONTAINER_IMAGE=california/web
XG_ENV=dev

git_pull(){
  echo "--- cd & git pull code ---"
  git pull origin $XG_ENV
}

docker_build(){
  echo "--- image build ---"
  make build-prod REPO=$CONTAINER_IMAGE:$XG_ENV DOCKERFILE_PATH=./devops/dockerfile
}

update_code(){
  echo "--- update docker compose ---"
  docker-compose -f $EXEC_DIR/../../docker-compose.yml up web -d

  echo "--- update exec ---"
  cp -rf $DIR/__publish_frontend/dist/ $EXEC_DIR/dist_temp
  mv $EXEC_DIR/dist $EXEC_DIR/dist_before
  mv $EXEC_DIR/dist_temp $EXEC_DIR/dist
  rm -rf $EXEC_DIR/dist_before
}

main(){
  cd $DIR/__publish_frontend
  git_pull
  docker_build
  update_code
  docker exec nginx nginx -s reload
}

main
```
