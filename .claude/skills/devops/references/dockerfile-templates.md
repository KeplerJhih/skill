# dockerfile 範本

以下提供各語言的 dockerfile 範本，供偵測到對應語言後參考生成。

所有檔名統一使用小寫 `dockerfile`，路徑為 `{service-dir}/.devops/dockerfile`。

> **⚠️ 禁止事項**：dockerfile 中**嚴禁使用 `ENV` 設定應用程式配置**（port、mode、DB 連線、密鑰等）。
> 所有配置一律由外部注入（docker-compose `env_file` / `environment`、`docker run -e`）。
> 這確保 debug 時配置來源單一可追蹤，不會被映像內嵌的隱藏預設值干擾。

---

## Go 後端

```dockerfile
# ---- 建置階段 ----
FROM golang:1.23-alpine AS builder
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/server ./cmd/server

# ---- 運行階段 ----
FROM alpine:3.19
RUN addgroup -S appuser && adduser -S appuser -G appuser
WORKDIR /app

COPY --from=builder /app/server .

RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 8080

CMD ["./server"]
```

### 重點說明

- **編譯型語言**：最終映像使用 `alpine`，不需語言運行時，映像極小（< 30MB）。
- **CGO_ENABLED=0**：靜態連結，確保在 alpine 上可運行。若使用 `go-sqlite3` 等 CGO 依賴，需改為 `CGO_ENABLED=1` 並在 builder 安裝 `gcc musl-dev`、runtime 安裝 `sqlite-libs`。
- **依賴快取**：先複製 `go.mod` + `go.sum` 並 `go mod download`，原始碼變更時不重新下載依賴。
- **無 ENV**：port、mode 等配置由 docker-compose `env_file` 注入，不寫在映像中。
- **HEALTHCHECK**：僅在專案已實作 `/health` 端點時才加入；若無則省略。

---

## Python 後端

```dockerfile
# ---- 建置階段 ----
FROM python:3.11-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt
COPY . .

# ---- 運行階段 ----
FROM python:3.11-slim
RUN groupadd -r appuser && useradd -r -g appuser appuser
WORKDIR /app

COPY --from=builder /install /usr/local
COPY --from=builder /build .

RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 8090

CMD ["gunicorn", "-w", "4", "-b", "0.0.0.0:8090", "wsgi:app"]
```

### 重點說明

- **Builder 階段**：將依賴安裝到 `/install` 前綴路徑，Runtime 階段僅複製已安裝套件。
- **依賴快取**：先複製 `requirements.txt` 安裝，再複製原始碼。
- **啟動指令**：依框架調整（Flask → `gunicorn`、FastAPI → `uvicorn`）。port 寫死在 CMD 中，與 `EXPOSE` 保持一致。
- **無 ENV**：所有配置（port、APP_ENV 等）由外部 `env_file` 注入。

---

## Node.js 後端（API 服務）

```dockerfile
# ---- 建置階段 ----
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --production
COPY . .

# ---- 運行階段 ----
FROM node:20-alpine
RUN addgroup -S appuser && adduser -S appuser -G appuser
WORKDIR /app

COPY --from=builder /app .

RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 3000

CMD ["node", "server.js"]
```

### 重點說明

- **依賴快取**：先複製 `package.json` + `package-lock.json`，`npm ci` 確保可重現安裝。
- **--production**：不安裝 devDependencies，減少映像大小。
- **啟動指令**：依專案入口調整（`server.js`、`dist/index.js` 等）。
- **無 ENV**：PORT 等配置由外部 `env_file` 注入，應用程式應讀取 `process.env.PORT`。

---

## 前端（Vite + Nginx）

```dockerfile
# ---- 建置階段 ----
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npx vite build

# ---- 運行階段 ----
FROM nginx:1.27-alpine
WORKDIR /app

# 非 root nginx：調整 pid 路徑，預建所有 cache 子目錄並賦權
# nginx 啟動時 master process 會 chown 這些目錄，K8s non-root 下會 Operation not permitted
# 預先建立並賦權後，nginx 發現目錄已存在且權限正確則跳過 chown
RUN sed -i 's|/run/nginx.pid|/tmp/nginx.pid|' /etc/nginx/nginx.conf \
    && mkdir -p /var/cache/nginx/client_temp \
                /var/cache/nginx/proxy_temp \
                /var/cache/nginx/fastcgi_temp \
                /var/cache/nginx/uwsgi_temp \
                /var/cache/nginx/scgi_temp \
    && chown -R nginx:nginx /var/cache/nginx /tmp /app /etc/nginx/conf.d

COPY --from=build --chown=nginx:nginx /app/dist /app
COPY --chown=nginx:nginx .devops/nginx.conf /etc/nginx/conf.d/default.conf

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:8080/health || exit 1

CMD ["nginx", "-g", "daemon off;"]
```

### 重點說明

- **統一工作目錄**：靜態檔案放在 `/app`（非預設的 `/usr/share/nginx/html`），與所有後端服務保持一致。
- **建置階段**：`npm ci` 確保可重現安裝；`npx vite build` 產出優化靜態資源到 `dist/`。
- **運行階段**：`nginx:1.27-alpine`（鎖定版本）僅提供靜態檔案，映像大小最小化。
- **非 root 運行**：使用 nginx 內建 `nginx` 使用者，需處理三個權限問題：(1) nginx.conf 改為 `listen 8080`（非 root 無法綁定 < 1024 特權端口），K8s Service 再映射 80→8080；(2) 預建 5 個 cache 子目錄（`client_temp`、`proxy_temp`、`fastcgi_temp`、`uwsgi_temp`、`scgi_temp`）並 chown，否則 K8s `runAsNonRoot` 環境下 nginx 啟動會因 `chown Operation not permitted` 失敗；(3) PID 檔案路徑從 `/run/nginx.pid` 改為 `/tmp/nginx.pid`。
- **SPA 路由**：搭配 `.devops/nginx.conf` 的 `try_files` 處理前端路由。nginx.conf 中的 `root` 須指向 `/app`。
- **健康檢查**：搭配 nginx.conf 的 `/health` 端點，供 K8s liveness probe 和 Docker HEALTHCHECK 使用。
- **日誌輸出**：nginx.conf 中設定 `access_log /dev/stdout; error_log /dev/stderr warn;`，確保日誌輸出到容器 stdout/stderr。

---

## PHP 後端

```dockerfile
# ---- 建置階段 ----
FROM composer:2 AS builder
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --prefer-dist
COPY . .
RUN composer dump-autoload --optimize

# ---- 運行階段 ----
FROM php:8.3-fpm-alpine
RUN addgroup -S appuser && adduser -S appuser -G appuser
WORKDIR /app

COPY --from=builder /app .

RUN chown -R appuser:appuser /app
USER appuser

EXPOSE 9000

CMD ["php-fpm"]
```

### 重點說明

- **Builder 階段**：使用官方 `composer` 映像安裝依賴，`--no-dev` 排除開發套件。
- **依賴快取**：先複製 `composer.json` + `composer.lock`，安裝後再複製原始碼。
- **擴充安裝**：依專案需求在 Runtime 階段安裝 PHP 擴充（`docker-php-ext-install pdo_mysql` 等）。
