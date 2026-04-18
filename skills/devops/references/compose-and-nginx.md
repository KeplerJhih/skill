# Docker Compose 與 Nginx 配置範本

## Docker Compose

路徑：專案根目錄 `docker-compose.yml`

以下為通用範本，實際服務名稱、目錄與連接埠依偵測結果動態調整。

```yaml
services:
  backend:
    build:
      context: ./{backend-dir}
      dockerfile: .devops/dockerfile
    ports:
      - "${BACKEND_PORT:-8080}:8080"
    env_file:
      - ./{backend-dir}/.env
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - app-network

  frontend:
    build:
      context: ./{frontend-dir}
      dockerfile: .devops/dockerfile
    ports:
      - "${FRONTEND_PORT:-3000}:80"
    depends_on:
      backend:
        condition: service_healthy
    networks:
      - app-network

networks:
  app-network:
    driver: bridge
```

### 重點說明

- **連接埠對映**：使用環境變數（`BACKEND_PORT`、`FRONTEND_PORT`）並設定合理預設值。依偵測語言調整預設 Port。
- **健康檢查**：後端必須通過健康檢查後，前端才會啟動（`condition: service_healthy`）。
- **網路**：自訂橋接網路讓容器間可透過服務名稱互相解析。
- **env_file**：每個服務載入各自的 `.env` — 機密資料不會進入映像。
- **dockerfile 路徑**：統一使用小寫 `.devops/dockerfile`。

---

## Nginx 配置

路徑：`{frontend-dir}/.devops/nginx.conf`

僅前端服務需要此檔案。

```nginx
server {
    listen 8080;
    root /app;
    index index.html;

    # 日誌輸出至 stdout/stderr（容器標準做法）
    access_log /dev/stdout;
    error_log  /dev/stderr warn;

    # 安全標頭
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    # 壓縮
    gzip_static on;
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/javascript application/json application/wasm image/svg+xml;

    # SPA fallback
    location / {
        try_files $uri $uri/ /index.html;
    }

    # 靜態資源長期快取（Vite 打包的 hash 檔案）
    location /assets/ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # 公共資源快取
    location ~* \.(png|jpg|jpeg|gif|wav|mp3|atlas|skel|wasm)$ {
        expires 7d;
        add_header Cache-Control "public";
    }

    # 健康檢查（HEALTHCHECK 使用）
    location = /health {
        access_log off;
        return 200 "ok";
        add_header Content-Type text/plain;
    }
}
```

### 重點說明

- **日誌輸出**：`access_log /dev/stdout` 與 `error_log /dev/stderr warn` 確保日誌輸出到容器的標準輸出/錯誤，供 `docker logs`、`kubectl logs` 和日誌收集器（Fluentd/Loki）採集。
- **安全標頭**：`X-Frame-Options`、`X-Content-Type-Options`、`X-XSS-Protection`、`Referrer-Policy` 防止常見攻擊。
- **SPA 路由**：`try_files $uri $uri/ /index.html` 確保所有路由都回退到 `index.html`，以支援前端路由。
- **靜態資源快取**：`/assets/` 下的靜態資源設定長期快取標頭（`1y`、`immutable`），因為 Vite 會在檔名中加入雜湊值。
- **健康檢查**：`/health` 端點供 dockerfile HEALTHCHECK 和 K8s liveness probe 使用，關閉 access_log 避免日誌雜訊。
