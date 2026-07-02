---
name: secret-scan
description: 當使用者提到「掃描機敏資訊」、「hardcode」、「寫死密碼」、「secret scan」、「credential scan」、「移除密碼」、「環境變數化」、「secrets to env」、「安全掃描」、「敏感資料」、「API key 外洩」或需要將寫死的帳密、Token、IP 等機敏資訊改為環境變數注入時觸發此技能。適用於任何語言（PHP、Go、Python、Node.js/TypeScript、Java 等）。
version: 1.0.0
---

# Secret Scan & Remediation

掃描程式碼中的 hardcoded 機敏資訊，並以環境變數注入方式修復。適用於所有語言，概念統一、實作按語言適配。

## 核心原則

- **零信任原則**：密碼、Token、API Key、私鑰等機敏資訊**絕不應存在於原始碼或版控中**
- **單一來源**：所有配置由環境變數注入，debug 時配置來源單一可追蹤
- **最小暴露面**：`.env` 加入 `.gitignore`；提供 `.env.example` 作為範本（值留空或用佔位符）
- **向後相容**：修復過程中不改變功能行為，僅改變值的來源

---

## 工作流程（必須按順序執行）

### 階段 1：掃描（Scan）

使用 Grep 工具搭配 `references/scan-patterns.md` 中的正則表達式，對目標目錄進行全面掃描。

#### 1a. 自動偵測語言

掃描目標目錄，依標誌檔判定語言：

| 標誌檔 | 語言 | 配置讀取方式 |
|--------|------|-------------|
| `go.mod` | Go | `os.Getenv()` |
| `composer.json` | PHP (Laravel) | `env()` / `getenv()` |
| `requirements.txt` / `pyproject.toml` | Python | `os.environ.get()` / `os.getenv()` |
| `package.json` + `.ts` 檔 | TypeScript/Node.js | `process.env.VAR` |
| `package.json` | JavaScript/Node.js | `process.env.VAR` |
| `pom.xml` / `build.gradle` | Java | `System.getenv()` |
| `Cargo.toml` | Rust | `std::env::var()` |

#### 1b. 執行掃描

依 `references/scan-patterns.md` 的 7 大分類逐項掃描：

1. **密碼與密鑰** — password, secret, token, key 等賦值
2. **資料庫連線** — 含帳密的連線字串或個別欄位
3. **API 金鑰** — 第三方服務的 API Key / Token
4. **IP 位址與主機名** — 含 port 的伺服器連線資訊
5. **Base64 編碼的機敏值** — 通常是被「藏」起來的 Token
6. **私鑰與憑證** — PEM、PKCS 格式的私鑰
7. **註解中的機敏資訊** — 被註解掉但仍在版控中的帳密

#### 1c. 排除誤報

以下情況**不算** hardcode，應排除：

- `env()` / `os.Getenv()` / `process.env.` 等環境變數讀取
- `.env.example` 中的佔位符值（如 `your-password-here`、空字串）
- 測試檔案中的 fixture 資料（需標註為 LOW，但不列為待修項）
- 文件/README 中的範例值（需標註為 MEDIUM-INFO）
- `config/*.php` 中帶 `env()` fallback 的 localhost 預設值

#### 1d. 產出掃描報告

以結構化表格呈現，**必須等待用戶確認後**才進入階段 2：

```markdown
## 機敏資訊掃描報告

### HIGH — 必須修復
| # | 檔案 | 行號 | 類型 | 摘要 |
|---|------|------|------|------|

### MEDIUM — 建議修復
| # | 檔案 | 行號 | 類型 | 摘要 |
|---|------|------|------|------|

### LOW — 可接受（僅通知）
| # | 檔案 | 行號 | 類型 | 摘要 |
|---|------|------|------|------|

需要修復哪些項目？(all / 指定編號 / skip)
```

---

### 階段 2：修復（Remediation）

用戶確認後，依 `references/remediation-templates.md` 的語言模板執行修復。

#### 2a. 修復流程（每個 finding 重複此流程）

1. **定義環境變數名稱** — 依命名慣例：`SCREAMING_SNAKE_CASE`，前綴分類（如 `REDIS_PASSWORD`、`TQ_API_HOST`）
2. **替換 hardcode 為環境變數讀取** — 依語言使用對應的 `env()` / `os.Getenv()` / `process.env.` 等
3. **更新 `.env.example`** — 加入新變數，值留空或用佔位符
4. **更新 `.env`**（若存在且不在版控中）— 填入實際值
5. **驗證** — 搜尋確認 hardcode 已完全移除

#### 2b. 環境變數命名慣例

| 分類 | 前綴 | 範例 |
|------|------|------|
| 資料庫 | `DB_` | `DB_HOST`, `DB_PASSWORD` |
| Redis | `REDIS_` | `REDIS_HOST`, `REDIS_PASSWORD` |
| 外部 API | `{SERVICE}_` | `FUGLE_API_KEY`, `TQ_API_HOST` |
| SMTP 郵件 | `MAIL_` | `MAIL_PASSWORD`, `MAIL_HOST` |
| JWT 認證 | `JWT_` | `JWT_SECRET`, `JWT_TTL` |
| 通用 | `APP_` | `APP_SECRET`, `APP_DEBUG` |

#### 2c. 集中化配置模式（建議）

對於多個相關設定（如一個外部服務有 host/port/user/pass），建議建立**配置模組**而非分散在各處：

**TypeScript/Node.js:**
```typescript
// config.ts — 所有配置由環境變數注入
export const redisConfig = {
  host: process.env.REDIS_HOST || '127.0.0.1',
  port: parseInt(process.env.REDIS_PORT || '6379'),
  password: process.env.REDIS_PASSWORD,
};
```

**Python:**
```python
# config.py
import os
REDIS_HOST = os.getenv('REDIS_HOST', '127.0.0.1')
REDIS_PASSWORD = os.getenv('REDIS_PASSWORD')
```

**Go:**
```go
// config/config.go
type RedisConfig struct {
    Host     string
    Password string
}
func LoadRedis() RedisConfig {
    return RedisConfig{
        Host:     os.Getenv("REDIS_HOST"),
        Password: os.Getenv("REDIS_PASSWORD"),
    }
}
```

**PHP (Laravel):**
```php
// config/database.php — Laravel 已內建此模式
'redis' => [
    'host' => env('REDIS_HOST', '127.0.0.1'),
    'password' => env('REDIS_PASSWORD'),
],
```

---

### 階段 3：驗證（Verify）

#### 3a. 再次掃描

修復完成後，**必須**重新執行階段 1 的掃描，確認所有 HIGH 項目已清除。

#### 3b. 確認 .gitignore

確保以下項目在 `.gitignore` 中：

```gitignore
.env
.env.local
.env.*.local
```

#### 3c. 確認 .env.example 完整

所有新增的環境變數都有對應的 `.env.example` 條目（值為空或佔位符）。

#### 3d. 功能驗證

若專案有測試套件，執行測試確認修復未破壞功能。

---

### 階段 4：完成回報

```markdown
## 修復報告

### 修復統計
| 嚴重度 | 修復數 | 略過數 |
|--------|--------|--------|

### 修復明細
| # | 檔案 | 原始問題 | 修復方式 | 環境變數名 |
|---|------|---------|---------|-----------|

### 新增/更新的檔案
- `.env.example` — 新增 N 個變數
- `config.ts` — 重構為環境變數讀取

### 驗證結果
- 二次掃描：✅ 無 HIGH 項目
- .gitignore：✅ 包含 .env
- .env.example：✅ 完整
```

---

## 特殊情境處理

### Docker 環境
若專案已容器化，額外確認：
- `docker-compose.yml` 使用 `env_file` 或 `environment` 注入
- Dockerfile 中**不含 ENV 設定應用配置**
- `.dockerignore` 排除 `.env`

### CI/CD 管線
建議用戶在 CI/CD 中使用平台的 Secret 機制（GitHub Secrets、GitLab CI Variables 等）而非 `.env` 檔案。

### 文件中的機敏資訊
CLAUDE.md、README 等文件中若包含真實 IP、密碼、Email：
- 替換為佔位符（如 `<REDIS_HOST>`、`<DB_PASSWORD>`）
- 或移至團隊內部文件（不在版控中）

---

## 參考資料

詳細的掃描正則表達式與各語言修復模板，請查閱：

- **`references/scan-patterns.md`** — 7 大分類的 Grep 掃描正則，含排除規則
- **`references/remediation-templates.md`** — 各語言的環境變數注入模板與完整範例
