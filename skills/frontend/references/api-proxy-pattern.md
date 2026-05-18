# 前端 API 同源 reverse proxy 模式

**適用**:Vue / React / 任何 SPA + nginx 部署。**不綁特定後端**或域名。

## 核心原則

**前端代碼絕不知道也不嘗試推導 backend host**。所有 API 請求一律打**相對路徑**(`/api/...`、`/health`),由 server 層(dev 用 vite proxy / prod 用 nginx)動態決定真正的 backend。

### 為什麼這樣做

| 做法 | 問題 |
|---|---|
| 前端 `VITE_API_BASE_URL=https://api.foo.com` 寫死 | 一份 image 只能部署一個域名,多環境要重 build |
| 前端 JS 從 `window.location.hostname` 推導(`admin.x` → `api.x`) | localhost / 內網域名場景推不到正確 host,本機 build 測 100% 壞;每個前端站重複實作 |
| 前端打絕對 URL + 後端 CORS | 多一層 CORS 配置維護,跨域 cookie / preflight 複雜 |
| **本模式**(前端永遠相對 + server 動態轉發) | 一份 image 部署任何域名都自動運作,零 env,零 CORS |

---

## 三層機制(dev / preview / prod)

### 1. Dev:vite `server.proxy`

`.env.development`:
```
VITE_DEV_PROXY_TARGET=http://localhost:8080
```

`vite.config.ts`:
```ts
import { defineConfig, loadEnv } from "vite";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const proxyTarget = env.VITE_DEV_PROXY_TARGET || "http://localhost:8080";
  const proxy = {
    "/api":    { target: proxyTarget, changeOrigin: true },
    "/health": { target: proxyTarget, changeOrigin: true },
  };

  return {
    server:  { host: "0.0.0.0", port: 5173, proxy },
    preview: { host: "0.0.0.0", port: 8080, proxy },  // 注意:preview 也要 proxy
  };
});
```

> **常見漏洞**:很多人忘記 preview 也要設 proxy。`npm run preview` 模擬 prod build 但跑在本機,如果只設 `server.proxy` 不設 `preview.proxy`,preview 環境登入 / API 都會 404。

### 2. Preview:同樣 vite proxy

如上,`preview` 區塊與 `server` 共用同份 proxy 規則。

### 3. Production:nginx `map $host` + 動態 `proxy_pass`

`.devops/nginx.conf`:
```nginx
# 從 Host header 自動推導 backend host
# 規則可依專案調整,例:admin.<root> → api.<root>
map $host $backend_host {
    "~^admin\.(?<root>.+)$" "api.$root";
    default                 "api.$host";
}

# 動態 proxy_pass(target 含變數)必須配 resolver
# 否則 nginx 啟動時 DNS 解析會失敗
resolver 8.8.8.8 1.1.1.1 valid=30s ipv6=off;

server {
    listen 8080 default_server;
    server_name _;

    # 隱藏 nginx 版本(Server header 改為 "nginx",不含版本號)
    server_tokens off;

    # ... 其他常規設定(gzip / security headers / root / SPA fallback)

    location /api/ {
        proxy_pass            https://$backend_host$request_uri;
        proxy_http_version    1.1;
        proxy_set_header      Host              $backend_host;
        proxy_set_header      X-Real-IP         $remote_addr;
        proxy_set_header      X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header      X-Forwarded-Proto $scheme;
        proxy_ssl_server_name on;
        proxy_read_timeout    30s;
    }

    location = /health {
        proxy_pass            https://$backend_host/health;
        proxy_http_version    1.1;
        proxy_set_header      Host              $backend_host;
        proxy_ssl_server_name on;
        access_log            off;
    }

    # 容器自己的健康檢查(HEALTHCHECK 用,不打 backend)
    location = /healthz {
        access_log off;
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }
}
```

---

## 前端 client 端代碼(極簡)

```ts
// src/api/client.ts
import axios from "axios";

// 永遠走同源相對路徑 — 由 nginx(prod)或 vite proxy(dev/preview)轉發
export const apiClient = axios.create({
  baseURL: "",
  timeout: 15_000,
});

export const API_BASE = "";  // 不繞 apiClient 的場景(login 等)也直接 import 共用
```

呼叫:
```ts
apiClient.get("/api/v1/users")  // dev 走 vite proxy / prod 走 nginx,都自動轉發
```

---

## hostname 推導規則範例

依專案實際命名習慣調整 `map $host` 規則。常見模式:

| 前端站域名規則 | nginx map 規則 |
|---|---|
| `admin.<root>` → `api.<root>` | `"~^admin\.(?<root>.+)$" "api.$root"` |
| `<sub>.<root>` 任意子域 → `api.<root>` | `"~^[^.]+\.(?<root>.+)$" "api.$root"` |
| 完全同域(`foo.com/api` proxy 到內網 backend) | `default "internal-backend.local:8080"` |
| 路徑前綴判斷(多 backend) | 用多個 `location /api/v1/` `location /api/v2/` 各自 `proxy_pass` |

---

## 踩坑提醒

### 1. 動態 `proxy_pass` 必須有 `resolver`

`proxy_pass` 的 target 含**變數**時,nginx 不會在 config load 時解析 DNS,而是每次請求時去問 resolver。**沒設 `resolver` → nginx 啟動或請求時報 `no resolver defined to resolve ...`**。

```nginx
resolver 8.8.8.8 1.1.1.1 valid=30s ipv6=off;
```

- AWS VPC 內:可改用 `169.254.169.253`(AWS provided DNS)
- K8s 內:可改用 `kube-dns.kube-system.svc.cluster.local`
- `valid=30s` 設快取 TTL,避免每次都打 DNS

### 2. HTTPS backend 必須 `proxy_ssl_server_name on`

backend 用 HTTPS 且共用 IP(SaaS、Cloudflare 等)時,需要 SNI。沒設會收到 wrong cert error。

```nginx
proxy_ssl_server_name on;
```

### 3. `Host` header 必須改寫成 backend host

```nginx
proxy_set_header Host $backend_host;
```

不改的話 backend 收到原始 `admin.foo.com` 而非 `api.foo.com`,backend 端的 host-based routing 會失效。

### 4. `proxy_pass` URL 含 `$request_uri`

```nginx
proxy_pass https://$backend_host$request_uri;
```

target 帶變數時 nginx 不做 URI 改寫,需自己附 `$request_uri` 保留原始路徑 + query。**不能** `proxy_pass https://$backend_host;`(會丟失 path)。

### 5. SPA fallback 順序

`location /` 的 `try_files` 必須在 `location /api/` 之後或同級。`/api/` 是 prefix match,nginx 用 longest prefix wins,正常不會衝突,但人工排序仍建議 API location 寫在 SPA fallback 之前以利閱讀。

### 6. localhost 場景的限制

本機 docker run 容器、開 `http://localhost:8080` 測登入,nginx 從 Host=`localhost` 推導出 backend=`api.localhost`,**這通常無法解析**。本機測 build 請改用:
- `npm run dev`(走 vite proxy 到本機 backend)
- 或在 hosts file 加 `127.0.0.1 admin.local api.local` + backend 配對應 cert
- 或對 `localhost` 加特例 map(回 `host.docker.internal:8080`)

### 7. 不要混用「前端 env 寫死 API host」與本模式

兩種方案二擇一。若同時存在 `VITE_API_BASE_URL=https://api.foo.com` + nginx proxy,前端會繞過 nginx 直接打絕對 URL,失去動態轉發優勢且引入 CORS。

---

## 對應的「前端慣例」清單

- 前端代碼**禁止**出現任何 backend host(完整 URL、`localhost:PORT`、env 變數拼接皆禁)
- API 路徑統一前綴(`/api/...`、`/health` 等),方便 vite / nginx 一條 rule 覆蓋
- `vite.config.ts` 的 `server.proxy` 與 `preview.proxy` **共用同份** 規則,避免漏配
- `.env.development` 只設 `VITE_DEV_PROXY_TARGET`(dev / preview 用),**不存在 `.env.production`**(prod 不需任何前端 env)
- 容器 nginx 配 `map $host` + `resolver`,版本號隱藏 `server_tokens off;`

---

## 部署驗證 checklist

- [ ] `curl https://admin.foo.com/health` 回應正常(經 nginx proxy 到 backend)
- [ ] `curl https://admin.foo.com/api/v1/...` 通(同上)
- [ ] 瀏覽器 DevTools Network 看到請求都打 `admin.foo.com/api/...`(同源),不是 `api.foo.com/...`
- [ ] 換另一個域名 `admin.bar.com` 部署同份 image,不需 rebuild,API 自動轉到 `api.bar.com`
- [ ] Response header 沒有 `Server: nginx/1.27.x`(只有 `Server: nginx`)
