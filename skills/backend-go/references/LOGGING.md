# 日誌規範 (log/slog)

本文件定義了本專案使用 `log/slog` 的完整規範，包含初始化配置、輸出目標、格式、級別控制。

---

## 配置結構 (.env)

```env
LOG_LEVEL=info                       # debug | info | warn | error
LOG_FORMAT=json                      # json | text
LOG_OUTPUT=stdout                    # stdout | stderr | file
LOG_FILE_PATH=storage/logs/app.log   # LOG_OUTPUT=file 時生效
```

| 環境 | level | format | output | 說明 |
|------|-------|--------|--------|------|
| dev | `debug` | `text` | `stdout` | 終端可讀，方便開發 |
| uat | `info` | `json` | `stdout` | 容器化環境，日誌收集器從 stdout 抓取 |
| prod | `info` | `json` | `stdout` | 同上，搭配 ELK/Loki 等集中收集 |
| prod (替代) | `info` | `json` | `file` | 非容器環境，寫入 `storage/logs/app.log` |

---

## 初始化範例 (pkg/logger/logger.go)

```go
package logger

import (
    "io"
    "log/slog"
    "os"
    "path/filepath"
    "strings"

    "github.com/spf13/viper"
)

// Setup 根據 config 初始化全域 slog logger。
// 在 cmd/server/main.go 中最早呼叫。
func Setup() {
    level := parseLevel(viper.GetString("LOG_LEVEL"))
    format := viper.GetString("LOG_FORMAT")
    output := viper.GetString("LOG_OUTPUT")

    writer := buildWriter(output)

    var handler slog.Handler
    opts := &slog.HandlerOptions{Level: level}

    switch strings.ToLower(format) {
    case "json":
        handler = slog.NewJSONHandler(writer, opts)
    default:
        handler = slog.NewTextHandler(writer, opts)
    }

    // 包一層 contextHandler，讓 request_id 貫穿下游日誌（見下節「Context 欄位貫穿」）
    slog.SetDefault(slog.New(contextHandler{handler}))
}

func parseLevel(s string) slog.Level {
    switch strings.ToLower(s) {
    case "debug":
        return slog.LevelDebug
    case "warn":
        return slog.LevelWarn
    case "error":
        return slog.LevelError
    default:
        return slog.LevelInfo
    }
}

func buildWriter(output string) io.Writer {
    switch strings.ToLower(output) {
    case "stderr":
        return os.Stderr
    case "file":
        path := viper.GetString("LOG_FILE_PATH")
        if path == "" {
            path = "storage/logs/app.log"
        }
        // 確保目錄存在
        if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
            slog.Error("failed to create log directory", "path", path, "error", err)
            return os.Stdout
        }
        f, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
        if err != nil {
            slog.Error("failed to open log file, fallback to stdout", "path", path, "error", err)
            return os.Stdout
        }
        return f
    default:
        return os.Stdout
    }
}
```

---

## Context 欄位貫穿 (pkg/logger/context.go)

**slog 的預設 Text/JSON handler 不會自動讀取 context values**——`slog.InfoContext(ctx, ...)` 的 ctx 只是傳遞給 handler，預設實作直接忽略。要讓 request_id 出現在下游（Service / Response）的日誌裡，必須用自訂 handler 從 context 取值附加：

```go
// pkg/logger/context.go
package logger

import (
    "context"
    "log/slog"
)

// 私有型別 key：字串 key 會觸發 go vet SA1029，且可能與其他套件衝突
type ctxKey struct{}

// WithRequestID 將 request_id 放入 context（由 Request Logger Middleware 呼叫）。
func WithRequestID(ctx context.Context, id string) context.Context {
    return context.WithValue(ctx, ctxKey{}, id)
}

// contextHandler 包裝實際 handler，把 context 中的 request_id 附加到每筆紀錄。
type contextHandler struct {
    slog.Handler
}

func (h contextHandler) Handle(ctx context.Context, r slog.Record) error {
    if id, ok := ctx.Value(ctxKey{}).(string); ok {
        r.AddAttrs(slog.String("request_id", id))
    }
    return h.Handler.Handle(ctx, r)
}

// WithAttrs / WithGroup 必須回傳包裝後的 handler，否則 logger.With(...) 派生的 logger 會失去貫穿能力
func (h contextHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
    return contextHandler{h.Handler.WithAttrs(attrs)}
}

func (h contextHandler) WithGroup(name string) slog.Handler {
    return contextHandler{h.Handler.WithGroup(name)}
}
```

---

## 使用方式

### 在 main.go 最早初始化

```go
// cmd/server/main.go
func main() {
    config.Load()       // 先載入配置
    logger.Setup()      // 再初始化日誌（之後所有 slog 呼叫都走配置好的 handler）

    slog.Info("server starting", "port", viper.GetInt("SERVER_PORT"))
    // ...
}
```

### 在各層使用

```go
// Handler 層 — 記錄請求級別的錯誤
slog.ErrorContext(ctx, "failed to create order",
    "user_id", userID,
    "error", err,
)

// Service 層 — 記錄業務警告（如 cache 降級）
slog.WarnContext(ctx, "cache get failed, fallback to DB",
    "key", cacheKey,
    "error", err,
)

// 基礎設施層 — 記錄連線狀態
slog.Info("redis connected", "addr", addr)
```

---

## 日誌級別使用規範

| 級別 | 使用場景 | 範例 |
|------|---------|------|
| `Debug` | 開發除錯用，生產不輸出 | cache hit/miss、SQL 查詢細節 |
| `Info` | 正常業務事件 | server 啟動、訂單建立成功、用戶登入 |
| `Warn` | 非預期但可恢復；**安全相關拒絕**需留痕 | cache 故障降級到 DB、重試中；驗簽失敗、重放被擋、限流觸頂（一般 4xx 不記，安全敏感的是例外——上線後靠它觀測攻擊訊號） |
| `Error` | 需要關注的錯誤 | DB 寫入失敗、外部 API 錯誤 |

### 禁止事項
- **禁止** 在迴圈內使用 `slog.Error`（改用 `slog.Debug` 或在迴圈外彙總）
- **禁止** 記錄敏感資料（密碼、JWT token、完整信用卡號）
- **禁止** 在 Domain 層使用 `slog`（Domain 層零外部依賴）

### 為什麼不在 Go 程式內自動分流 stdout/stderr？

遵循 **Twelve-Factor App** 原則：應用程式只管往**單一 output** 寫日誌，路由和儲存由外部基礎設施負責。

- **容器環境**（Docker/K8s）：stdout 和 stderr 最終進同一個日誌收集器（Loki/ELK），分流沒有意義。
- **裸機部署**：在啟動指令層分流即可，不需要改程式碼：
  ```bash
  ./server 1>storage/logs/app.log 2>storage/logs/error.log
  ```
- **禁止**在 Go 程式內按日誌級別分流到不同 writer——增加複雜度且沒有實際收益。

---

## Request Logger Middleware

```go
// internal/interfaces/api/middleware/logger.go

func RequestLogger() gin.HandlerFunc {
    return func(c *gin.Context) {
        start := time.Now()
        requestID := uuid.New().String()

        // 用 logger.WithRequestID 注入（私有型別 key）。注意：光塞 context 沒有效果，
        // 必須搭配「Context 欄位貫穿」的 contextHandler，request_id 才會出現在下游日誌
        ctx := logger.WithRequestID(c.Request.Context(), requestID)
        c.Request = c.Request.WithContext(ctx)
        c.Header("X-Request-ID", requestID)

        c.Next()

        // request_id 由 contextHandler 自動附加，此處不需重複帶
        slog.InfoContext(ctx, "request completed",
            "method", c.Request.Method,
            "path", c.Request.URL.Path,
            "status", c.Writer.Status(),
            "latency_ms", time.Since(start).Milliseconds(),
            "client_ip", c.ClientIP(),
        )
    }
}
```

---

## 日誌輸出範例

### dev 環境 (format=text, output=stdout)

```
time=2025-01-15T10:30:00.000+08:00 level=INFO msg="request completed" method=POST path=/customer/orders status=200 latency_ms=45 client_ip=127.0.0.1 request_id=abc-123
time=2025-01-15T10:30:00.001+08:00 level=WARN msg="cache get failed, fallback to DB" key=product:detail:42 error="dial tcp: connection refused" request_id=abc-123
```

> `request_id` 出現在**每一行**（含下游 Service 的 WARN）且固定排在最後——它是 contextHandler 在 Handle 時附加的，不是各呼叫點手動帶的。

### prod 環境 (format=json, output=stdout)

```json
{"time":"2025-01-15T10:30:00.000+08:00","level":"INFO","msg":"request completed","method":"POST","path":"/customer/orders","status":200,"latency_ms":45,"client_ip":"203.0.113.1","request_id":"abc-123"}
{"time":"2025-01-15T10:30:00.001+08:00","level":"WARN","msg":"cache get failed, fallback to DB","key":"product:detail:42","error":"dial tcp: connection refused","request_id":"abc-123"}
```

---

## 日誌檔案管理 (output=file 時)

- 日誌檔固定寫入 `storage/logs/` 目錄（符合 skill 的資源儲存規則）
- **不在 Go 程式內實作 log rotation**——使用 OS 層級的工具：
  - Linux: `logrotate`
  - Docker: `--log-opt max-size=100m --log-opt max-file=3`
- `storage/logs/` 加入 `.gitignore`
