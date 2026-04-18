# 機敏資訊掃描正則表達式

供 Grep 工具使用的掃描模式，按分類組織。每個分類包含：掃描正則、目標語言、排除規則。

> **使用方式**：以 Grep 工具的 `pattern` 參數搭配 `output_mode: "content"` 執行，搭配 `-n` 顯示行號。

---

## 1. 密碼與密鑰

### 通用密碼賦值

```
pattern: (password|passwd|pwd|secret|token|api_key|apikey|api[-_]?secret)\s*[:=]\s*['"][^'"]{4,}['"]
```

**適用語言**：ALL  
**說明**：匹配 `password = "xxx"` / `secret: 'xxx'` / `api_key = "xxx"` 等模式  
**排除**：
- `env(` / `os.Getenv(` / `process.env.` / `os.environ` 開頭的行
- `.env.example` / `.env.sample` 檔案
- `test` / `spec` / `fixture` 目錄下的檔案（標為 LOW）
- 值為 `''`（空字串）、`null`、`None`、`placeholder`、`your-*-here` 的行

### 私鑰關鍵字

```
pattern: -----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----
```

**適用語言**：ALL  
**說明**：PEM 格式私鑰，出現在原始碼中即為 HIGH  
**排除**：無（私鑰永遠不應出現在原始碼中）

### JWT / Bearer Token

```
pattern: (bearer|jwt|token)\s*[:=]\s*['"]eyJ[A-Za-z0-9_-]+\.
```

**適用語言**：ALL  
**說明**：JWT 格式的 Bearer Token（以 `eyJ` 開頭的 Base64）  
**排除**：測試 fixture

---

## 2. 資料庫連線

### 連線字串

```
pattern: (mysql|postgres|postgresql|mongodb|redis|amqp)://[^/\s'"]+:[^@\s'"]+@[^/\s'"]+
```

**適用語言**：ALL  
**說明**：匹配 `mysql://user:password@host:port/db` 格式的連線字串  
**排除**：`env(` / `os.Getenv` / `process.env` 讀取的行

### 個別欄位賦值

```
pattern: (db|database|mysql|redis|mongo)[-_.]?(host|port|user|username|password|pass|name)\s*[:=]\s*['"][^'"]{2,}['"]
```

**適用語言**：ALL  
**說明**：匹配 `db_host = "192.168.1.1"` / `redis_password: "xxx"` 等  
**排除**：
- `env(` / `os.Getenv` / `process.env` 行
- 值為 `localhost` / `127.0.0.1` / `''` / `root` / `forge` 的行（Laravel 預設）
- `config/*.php` 中帶 `env()` 的 fallback 值

---

## 3. API 金鑰

### 通用 API Key

```
pattern: (api[-_]?key|api[-_]?token|access[-_]?key|secret[-_]?key|client[-_]?secret)\s*[:=]\s*['"][A-Za-z0-9+/=_-]{8,}['"]
```

**適用語言**：ALL  
**說明**：較長的英數字串賦值給 api_key 等變數  
**排除**：`env(` / `os.Getenv` / `process.env` 行

### 已知服務的 Key 格式

| 服務 | Pattern | 說明 |
|------|---------|------|
| AWS | `(AKIA\|ASIA)[A-Z0-9]{16}` | AWS Access Key ID |
| GCP | `AIza[A-Za-z0-9_-]{35}` | Google API Key |
| Stripe | `sk_(live\|test)_[A-Za-z0-9]{24,}` | Stripe Secret Key |
| Slack | `xox[bpas]-[A-Za-z0-9-]+` | Slack Token |
| GitHub | `gh[ps]_[A-Za-z0-9]{36,}` | GitHub PAT |
| Telegram | `[0-9]{8,}:[A-Za-z0-9_-]{35}` | Telegram Bot Token |

---

## 4. IP 位址與主機名

### 帶端口的 IP 位址

```
pattern: ['"](\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(:\d{2,5})?['"]
```

**適用語言**：ALL  
**說明**：匹配引號包圍的 IP 地址，可選帶 port  
**排除**：
- `127.0.0.1` / `0.0.0.0` / `localhost`（本地開發用）
- 測試 fixture 中的 mock IP
- Docker network 內部 IP（`172.x.x.x`）

### 外部主機名

```
pattern: ['"][a-z0-9][-a-z0-9]*\.[a-z]{2,}\.[a-z]{2,}(:\d{2,5})?['"]
```

**適用語言**：ALL  
**說明**：匹配 `"api.example.com:8080"` 等外部主機連線  
**排除**：
- 公開已知的服務端點（如 `smtp.gmail.com`、`registry.npmjs.org`）
- `localhost` / `host.docker.internal`

---

## 5. Base64 編碼的機敏值

```
pattern: ['"][A-Za-z0-9+/]{40,}={0,2}['"]
```

**適用語言**：ALL  
**說明**：長度 >= 40 的 Base64 字串，常被用來「隱藏」API Key 或 Token  
**排除**：
- CSS / SVG 的 data-uri（`data:image/`）
- 字型檔的 Base64 內嵌
- `hash` / `checksum` / `digest` 變數名

---

## 6. 郵件帳密

```
pattern: (mail|smtp|email)[-_.]?(user|username|password|pass|host|from)\s*[:=]\s*['"][^'"]{4,}['"]
```

**適用語言**：ALL  
**說明**：SMTP 相關的帳密設定  
**排除**：`env(` / `os.Getenv` / `process.env` 行

---

## 7. 註解中的機敏資訊

```
pattern: (//|#|/\*)\s*.*(password|token|key|secret)\s*[:=]\s*\S+
```

**適用語言**：ALL  
**說明**：被註解掉但仍包含機敏值的行  
**排除**：明顯是說明文字（如 `// password should be at least 8 chars`）

---

## 掃描執行策略

### 建議掃描順序

1. 先掃描 **分類 1（密碼與密鑰）** — 涵蓋面最廣
2. 再掃描 **分類 3（API 金鑰）** — 捕捉遺漏的 Token
3. 接著 **分類 4（IP 位址）** — 基礎設施暴露
4. 然後 **分類 2（資料庫連線）** 和 **分類 6（郵件）**
5. 最後 **分類 5（Base64）** 和 **分類 7（註解）** — 誤報率較高

### 排除目錄

掃描時應排除以下目錄（使用 Glob 的排除模式）：

```
node_modules/
vendor/
.git/
dist/
build/
__pycache__/
.venv/
*.min.js
*.map
*.lock
```

### 誤報處理

若單次掃描結果超過 50 筆，先依以下優先級分類：
1. **確定 HIGH**：包含實際的長密碼/Token/Key 值
2. **疑似 MEDIUM**：包含 IP、主機名、帳號
3. **可能 LOW**：測試資料、文件範例、短字串

對 MEDIUM/LOW 進行人工判斷後再決定是否修復。

---

## 語言特定的 env 讀取模式（排除規則用）

掃描時，以下模式表示「已正確使用環境變數」，應從結果中排除：

| 語言 | 排除模式 |
|------|---------|
| PHP (Laravel) | `env('VAR_NAME'` / `getenv('VAR_NAME'` |
| Go | `os.Getenv("VAR_NAME"` / `viper.Get` |
| Python | `os.getenv('VAR_NAME'` / `os.environ.get(` / `os.environ[` |
| TypeScript/JS | `process.env.VAR_NAME` / `process.env['VAR_NAME']` |
| Java | `System.getenv("VAR_NAME"` / `@Value("${VAR_NAME}")` |
| Rust | `std::env::var("VAR_NAME"` / `env::var(` |
| Ruby | `ENV['VAR_NAME']` / `ENV.fetch(` |
