# 各語言修復模板

針對不同語言，提供將 hardcoded 機敏資訊替換為環境變數的標準模板。

---

## 通用原則

無論哪種語言，修復遵循相同的三步驟：

1. **Replace** — 將 hardcode 值替換為環境變數讀取
2. **Document** — 在 `.env.example` 加入新變數（值留空或佔位符）
3. **Populate** — 在 `.env` 填入實際值（確保 `.env` 在 `.gitignore` 中）

### .env.example 格式規範

```env
# ===== 資料庫 =====
DB_HOST=
DB_PORT=3306
DB_DATABASE=
DB_USERNAME=
DB_PASSWORD=

# ===== Redis =====
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
REDIS_PASSWORD=

# ===== 外部服務：台指期 API =====
TQ_API_HOST=
TQ_API_PORT=
TQ_API_USER=
TQ_API_PASS=

# ===== 外部服務：Fugle =====
FUGLE_API_KEY=
```

**規則**：
- 分組使用註解標題
- 有合理預設值的填入預設（如 port）
- 機敏值一律留空
- 不加引號（除非值包含空格或特殊字元）

---

## TypeScript / Node.js

### 安裝 dotenv（若尚未安裝）

```bash
npm install dotenv
```

### 進入點載入

在應用程式進入點（`src/index.ts` 或 `src/main.ts`）的**最頂部**：

```typescript
import 'dotenv/config';
```

或者不使用 dotenv，改用 Docker 的 `env_file` 注入（容器化環境建議此方式）。

### 修復模板

**修復前（hardcoded）：**
```typescript
export const redisConfig = {
  host: "52.193.249.98",
  port: 6379,
  db: 1,
  password: "Xq7#mK2$vL9@nR4w",
};

export const TQ_API_HOST = "mpx8.tvmall.com.tw";
export const TQ_API_PORT = 20001;
export const TQ_API_USER = 'LIN1';
export const TQ_API_PASS = '20231005';

export const FUGLE_API_KEY = "MjhiNWM2MjgtNmFl...";
```

**修復後（環境變數）：**
```typescript
export const redisConfig = {
  host: process.env.REDIS_HOST || '127.0.0.1',
  port: parseInt(process.env.REDIS_PORT || '6379', 10),
  db: parseInt(process.env.REDIS_DB || '1', 10),
  password: process.env.REDIS_PASSWORD,
};

export const TQ_API_HOST = process.env.TQ_API_HOST || '';
export const TQ_API_PORT = parseInt(process.env.TQ_API_PORT || '20001', 10);
export const TQ_API_USER = process.env.TQ_API_USER || '';
export const TQ_API_PASS = process.env.TQ_API_PASS || '';

export const FUGLE_API_KEY = process.env.FUGLE_API_KEY || '';
```

### 注意事項

- `parseInt()` 用於數字類型的 port
- 密碼類不設 fallback（`undefined` 即可，連線時會報錯比靜默失敗好）
- 非機敏的預設值（如 localhost port）可保留 fallback

---

## Python

### 安裝 python-dotenv（若尚未安裝）

```bash
pip install python-dotenv
```

### 進入點載入

```python
from dotenv import load_dotenv
load_dotenv()
```

或在容器化環境中，由 Docker `env_file` 注入，無需 dotenv。

### 修復模板

**修復前（hardcoded）：**
```python
SERVER_IP = "15.168.61.136"
SERVER_PORT = 58699
USERNAME = "AXAsw2S"

r = redis.Redis(host='127.0.0.1', port=6379, db=0, password='Xq7#mK2$vL9@nR4w')
```

**修復後（環境變數）：**
```python
import os

SERVER_IP = os.getenv('DATA_SERVER_IP', '')
SERVER_PORT = int(os.getenv('DATA_SERVER_PORT', '58699'))
USERNAME = os.getenv('DATA_SERVER_USER', '')

r = redis.Redis(
    host=os.getenv('REDIS_HOST', '127.0.0.1'),
    port=int(os.getenv('REDIS_PORT', '6379')),
    db=int(os.getenv('REDIS_DB', '0')),
    password=os.getenv('REDIS_PASSWORD'),
)
```

### 注意事項

- `os.getenv()` 比 `os.environ[]` 安全，缺少變數時返回 `None` 而非拋例外
- 數字用 `int()` 轉型
- `password` 的 fallback 用 `None`（Redis 客戶端在 password=None 時不認證）

---

## PHP (Laravel)

Laravel 已內建 `env()` helper，通常 config 檔已正確使用。

### 修復模板

**修復前（若在非 config 檔中 hardcode）：**
```php
$redis = new Redis();
$redis->connect('52.193.249.98', 6379);
$redis->auth('Xq7#mK2$vL9@nR4w');
```

**修復後：**
```php
$redis = new Redis();
$redis->connect(config('database.redis.default.host'), config('database.redis.default.port'));
$redis->auth(config('database.redis.default.password'));
```

或直接使用 Laravel Facade：
```php
use Illuminate\Support\Facades\Redis;
Redis::connection()->ping();
```

### config/*.php 中的寫法

```php
// config/services.php
'tq_api' => [
    'host' => env('TQ_API_HOST'),
    'port' => env('TQ_API_PORT', 20001),
    'user' => env('TQ_API_USER'),
    'pass' => env('TQ_API_PASS'),
],
```

### 注意事項

- Laravel 的 `env()` 在 config cache 後不可用，**務必只在 config/*.php 中使用** `env()`
- 應用程式碼中使用 `config('services.tq_api.host')` 讀取
- 非 Laravel 的原生 PHP 使用 `getenv('VAR_NAME')` 或 `$_ENV['VAR_NAME']`

---

## Go

### 修復模板

**修復前（hardcoded）：**
```go
db, err := sql.Open("mysql", "root:secret@tcp(192.168.1.1:3306)/mydb")

redisClient := redis.NewClient(&redis.Options{
    Addr:     "52.193.249.98:6379",
    Password: "Xq7#mK2$vL9@nR4w",
})
```

**修復後（環境變數）：**
```go
import "os"

dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s",
    os.Getenv("DB_USERNAME"),
    os.Getenv("DB_PASSWORD"),
    os.Getenv("DB_HOST"),
    os.Getenv("DB_PORT"),
    os.Getenv("DB_DATABASE"),
)
db, err := sql.Open("mysql", dsn)

redisClient := redis.NewClient(&redis.Options{
    Addr:     fmt.Sprintf("%s:%s", os.Getenv("REDIS_HOST"), os.Getenv("REDIS_PORT")),
    Password: os.Getenv("REDIS_PASSWORD"),
})
```

### 搭配 config struct（建議）

```go
// internal/config/config.go
package config

import "os"

type Config struct {
    DB    DBConfig
    Redis RedisConfig
}

type DBConfig struct {
    Host     string
    Port     string
    User     string
    Password string
    Database string
}

type RedisConfig struct {
    Host     string
    Port     string
    Password string
}

func Load() *Config {
    return &Config{
        DB: DBConfig{
            Host:     getEnv("DB_HOST", "127.0.0.1"),
            Port:     getEnv("DB_PORT", "3306"),
            User:     getEnv("DB_USERNAME", ""),
            Password: os.Getenv("DB_PASSWORD"),
            Database: getEnv("DB_DATABASE", ""),
        },
        Redis: RedisConfig{
            Host:     getEnv("REDIS_HOST", "127.0.0.1"),
            Port:     getEnv("REDIS_PORT", "6379"),
            Password: os.Getenv("REDIS_PASSWORD"),
        },
    }
}

func getEnv(key, fallback string) string {
    if v := os.Getenv(key); v != "" {
        return v
    }
    return fallback
}
```

### 注意事項

- Go 標準庫的 `os.Getenv()` 返回空字串（非 error），需自行處理缺失
- 密碼類不設 fallback
- 可選用 `github.com/joho/godotenv` 在本地開發時載入 `.env`
- 生產環境由 K8s ConfigMap/Secret 或 Docker `env_file` 注入

---

## Java / Spring Boot

### 修復模板

**修復前（hardcoded in application.properties）：**
```properties
spring.datasource.url=jdbc:mysql://192.168.1.1:3306/mydb
spring.datasource.username=root
spring.datasource.password=secret123
```

**修復後（環境變數佔位符）：**
```properties
spring.datasource.url=jdbc:mysql://${DB_HOST:127.0.0.1}:${DB_PORT:3306}/${DB_DATABASE}
spring.datasource.username=${DB_USERNAME}
spring.datasource.password=${DB_PASSWORD}
```

**修復前（hardcoded in Java code）：**
```java
String apiKey = "sk_live_abc123...";
```

**修復後：**
```java
String apiKey = System.getenv("API_KEY");
// 或使用 Spring 的 @Value
@Value("${API_KEY}")
private String apiKey;
```

---

## Rust

### 修復模板

**修復前：**
```rust
let password = "secret123";
let redis_url = "redis://:Xq7#mK2$vL9@nR4w@52.193.249.98:6379/0";
```

**修復後：**
```rust
use std::env;

let password = env::var("DB_PASSWORD").expect("DB_PASSWORD must be set");
let redis_host = env::var("REDIS_HOST").unwrap_or_else(|_| "127.0.0.1".to_string());
let redis_password = env::var("REDIS_PASSWORD").ok();
```

### 注意事項

- `env::var()` 返回 `Result<String, VarError>`
- 必要變數用 `.expect("msg")`
- 可選變數用 `.ok()` 返回 `Option<String>`
- 可選用 `dotenvy` crate 在開發環境載入 `.env`

---

## Docker 環境整合

### docker-compose.yml

修復後的服務應透過 `env_file` 注入環境變數：

```yaml
services:
  datasource-tq:
    build:
      context: ./backend/node
      dockerfile: .devops/dockerfile
    env_file:
      - ./backend/node/.env
    command: ["npx", "ts-node", "-T", "src/tq.data.ts"]
```

### .env 檔案位置

每個服務維護獨立的 `.env`：

```
backend/node/.env          # Node.js datasource 的環境變數
backend/python/.env        # Python demo data 的環境變數
backend/futures/.env       # Laravel 的環境變數
```

### .dockerignore 排除

確保 `.dockerignore` 包含：

```
.env
.env.*
!.env.example
```

這確保 `.env` 不會被烘焙進映像，但 `.env.example` 作為範本保留。

---

## 修復後的驗證清單

對每個修復的檔案，執行以下驗證：

- [ ] hardcode 值已完全移除（Grep 搜尋確認）
- [ ] 環境變數名稱使用 `SCREAMING_SNAKE_CASE`
- [ ] `.env.example` 已新增對應條目
- [ ] `.env` 已填入實際值（若在本地開發環境）
- [ ] `.gitignore` 包含 `.env`
- [ ] docker-compose.yml 使用 `env_file` 注入（若容器化）
- [ ] 應用程式仍可正常啟動並連線
