# Redis 規範 (go-redis/v9)

本文件定義了本專案使用 `go-redis/v9` 實作緩存 (Cache)、分散式鎖 (Lock)、任務隊列 (Queue) 的完整規範。
所有 Redis 相關代碼放在 `internal/infrastructure/redis/`。

---

## 連線池初始化 (client.go)

### 配置結構 (.env)

```env
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0
REDIS_POOL_SIZE=20
REDIS_MIN_IDLE_CONNS=5
REDIS_DIAL_TIMEOUT=5s
REDIS_READ_TIMEOUT=3s
REDIS_WRITE_TIMEOUT=3s
```

### 初始化範例

```go
// internal/infrastructure/redis/client.go
package redis

import (
    "context"
    "fmt"
    "time"

    "github.com/redis/go-redis/v9"
    "github.com/spf13/viper"
)

func NewClient() (*redis.Client, error) {
    client := redis.NewClient(&redis.Options{
        Addr:         fmt.Sprintf("%s:%d", viper.GetString("REDIS_HOST"), viper.GetInt("REDIS_PORT")),
        Password:     viper.GetString("REDIS_PASSWORD"),
        DB:           viper.GetInt("REDIS_DB"),
        PoolSize:     viper.GetInt("REDIS_POOL_SIZE"),
        MinIdleConns: viper.GetInt("REDIS_MIN_IDLE_CONNS"),
        DialTimeout:  viper.GetDuration("REDIS_DIAL_TIMEOUT"),
        ReadTimeout:  viper.GetDuration("REDIS_READ_TIMEOUT"),
        WriteTimeout: viper.GetDuration("REDIS_WRITE_TIMEOUT"),
    })

    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    defer cancel()

    if err := client.Ping(ctx).Err(); err != nil {
        return nil, fmt.Errorf("failed to connect redis: %w", err)
    }
    return client, nil
}
```

**規則**：
- 整個應用程式共享**一個** `*redis.Client` 實例（連線池內建）。
- 在 `cmd/server/main.go` 初始化，透過建構式注入傳遞到 Service 層。
- Graceful shutdown 時呼叫 `client.Close()`。

---

## Cache (cache.go)

### 模式：Cache-Aside (Lazy Loading)

讀取流程：先查 Cache → Cache miss 則查 DB → 寫回 Cache。
寫入流程：先更新 DB → 再刪除 Cache（**不是更新 Cache**）。

### 封裝介面與實作

```go
// internal/infrastructure/redis/cache.go
package redis

import (
    "context"
    "encoding/json"
    "fmt"
    "time"

    "github.com/redis/go-redis/v9"
)

type CacheService struct {
    client *redis.Client
    prefix string // 應用級 key 前綴，例如 "myapp"
}

func NewCacheService(client *redis.Client, prefix string) *CacheService {
    return &CacheService{client: client, prefix: prefix}
}

// key 自動加上 prefix → "myapp:user:profile:123"
func (c *CacheService) buildKey(key string) string {
    return fmt.Sprintf("%s:%s", c.prefix, key)
}

// Get 從緩存取得資料，反序列化到 dest。
// 回傳 (found bool, err error)。Cache miss 時 found=false, err=nil。
func (c *CacheService) Get(ctx context.Context, key string, dest interface{}) (bool, error) {
    val, err := c.client.Get(ctx, c.buildKey(key)).Result()
    if err == redis.Nil {
        return false, nil // cache miss，不是錯誤
    }
    if err != nil {
        return false, fmt.Errorf("cache get %s: %w", key, err)
    }
    if err := json.Unmarshal([]byte(val), dest); err != nil {
        return false, fmt.Errorf("cache unmarshal %s: %w", key, err)
    }
    return true, nil
}

// Set 將資料序列化後寫入緩存。ttl 必須 > 0。
func (c *CacheService) Set(ctx context.Context, key string, value interface{}, ttl time.Duration) error {
    data, err := json.Marshal(value)
    if err != nil {
        return fmt.Errorf("cache marshal %s: %w", key, err)
    }
    return c.client.Set(ctx, c.buildKey(key), data, ttl).Err()
}

// Del 刪除一個或多個緩存 key。
func (c *CacheService) Del(ctx context.Context, keys ...string) error {
    fullKeys := make([]string, len(keys))
    for i, k := range keys {
        fullKeys[i] = c.buildKey(k)
    }
    return c.client.Del(ctx, fullKeys...).Err()
}

// DelByPattern 透過 SCAN 刪除匹配的 key（用於批量失效）。
// pattern 例如 "product:list:*"
func (c *CacheService) DelByPattern(ctx context.Context, pattern string) error {
    iter := c.client.Scan(ctx, 0, c.buildKey(pattern), 100).Iterator()
    var keys []string
    for iter.Next(ctx) {
        keys = append(keys, iter.Val())
    }
    if err := iter.Err(); err != nil {
        return fmt.Errorf("cache scan %s: %w", pattern, err)
    }
    if len(keys) > 0 {
        return c.client.Del(ctx, keys...).Err()
    }
    return nil
}
```

### Service 層使用範例

```go
// internal/application/service/product_service.go

func (s *ProductService) GetByID(ctx context.Context, id uint) (*entity.Product, error) {
    cacheKey := fmt.Sprintf("product:detail:%d", id)

    // 1. 嘗試從 Cache 取得
    var product entity.Product
    found, err := s.cache.Get(ctx, cacheKey, &product)
    if err != nil {
        slog.WarnContext(ctx, "cache get failed, fallback to DB", "key", cacheKey, "error", err)
        // cache 錯誤不阻斷流程，降級到 DB
    }
    if found {
        return &product, nil
    }

    // 2. Cache miss → 查 DB
    result, err := s.productRepo.FindByID(ctx, id)
    if err != nil {
        return nil, err
    }

    // 3. 寫回 Cache (fire-and-forget，不阻斷主流程)
    if cacheErr := s.cache.Set(ctx, cacheKey, result, 15*time.Minute); cacheErr != nil {
        slog.WarnContext(ctx, "cache set failed", "key", cacheKey, "error", cacheErr)
    }

    return result, nil
}

func (s *ProductService) Update(ctx context.Context, id uint, req UpdateProductRequest) error {
    // 1. 先更新 DB
    if err := s.productRepo.Update(ctx, id, ...); err != nil {
        return err
    }

    // 2. 成功後刪除 Cache（不是更新）
    _ = s.cache.Del(ctx, fmt.Sprintf("product:detail:%d", id))
    _ = s.cache.DelByPattern(ctx, "product:list:*") // 列表快取也失效

    return nil
}
```

### Cache 規則

| 規則 | 說明 |
|------|------|
| **TTL 必設** | 所有 key 必須有 TTL。常見值：詳情 10-30min、列表 5-10min、設定類 1-24h |
| **寫入時刪除，不更新** | DB 寫入後刪除 cache，下次讀取自然回填。避免「先更新 cache 但 DB 失敗」的不一致 |
| **Cache 錯誤不阻斷** | Redis 故障時降級到 DB 直讀，記 `slog.Warn`，不返回 500 |
| **禁止 Cache 穿透** | 高頻查詢的「不存在」結果也可短暫快取 (TTL 1-5min) 防止穿透 |
| **序列化用 JSON** | 統一使用 `encoding/json`，方便調試 |

### Key 命名規範

格式：`{entity}:{type}:{identifier}`

```
product:detail:42          # 單一商品
product:list:page=1:limit=20  # 商品列表（含查詢參數）
user:profile:7             # 用戶資料
config:site:settings       # 全站設定
```

---

## 分散式鎖 (lock.go)

### 使用場景
- 防止同一訂單重複處理
- 庫存扣減的併發控制
- 支付回調的冪等處理
- 任何需要跨 instance 互斥的操作

### 封裝介面與實作

```go
// internal/infrastructure/redis/lock.go
package redis

import (
    "context"
    "fmt"
    "time"

    "github.com/google/uuid"
    "github.com/redis/go-redis/v9"
)

type Lock struct {
    client *redis.Client
    key    string
    value  string // 唯一標識，防止誤刪他人的鎖
}

type LockService struct {
    client *redis.Client
    prefix string
}

func NewLockService(client *redis.Client, prefix string) *LockService {
    return &LockService{client: client, prefix: prefix}
}

// Acquire 嘗試取得鎖。
// ttl: 鎖的最大持有時間（防止死鎖），業務完成後應主動 Release。
// 回傳 Lock（成功）或 error（已被鎖定 / Redis 錯誤）。
func (s *LockService) Acquire(ctx context.Context, resource string, ttl time.Duration) (*Lock, error) {
    key := fmt.Sprintf("%s:lock:%s", s.prefix, resource)
    value := uuid.New().String()

    ok, err := s.client.SetNX(ctx, key, value, ttl).Result()
    if err != nil {
        return nil, fmt.Errorf("lock acquire %s: %w", resource, err)
    }
    if !ok {
        return nil, fmt.Errorf("resource %s is locked", resource)
    }
    return &Lock{client: s.client, key: key, value: value}, nil
}

// Release 釋放鎖。使用 Lua script 確保只釋放自己持有的鎖。
func (l *Lock) Release(ctx context.Context) error {
    script := redis.NewScript(`
        if redis.call("GET", KEYS[1]) == ARGV[1] then
            return redis.call("DEL", KEYS[1])
        end
        return 0
    `)
    _, err := script.Run(ctx, l.client, []string{l.key}, l.value).Result()
    return err
}
```

### Service 層使用範例

```go
func (s *OrderService) Create(ctx context.Context, req CreateOrderRequest) (*entity.Order, error) {
    // 1. 取得鎖 — 防止同一用戶重複建立訂單
    lock, err := s.lock.Acquire(ctx, fmt.Sprintf("order:create:user:%d", req.UserID), 30*time.Second)
    if err != nil {
        return nil, errors.NewBadRequest("請勿重複提交訂單")
    }
    defer lock.Release(ctx)

    // 2. 執行業務邏輯（在鎖的保護下）
    order, err := s.doCreateOrder(ctx, req)
    if err != nil {
        return nil, err
    }
    return order, nil
}
```

### Lock 規則

| 規則 | 說明 |
|------|------|
| **必須設 TTL** | 防止持有者 crash 導致死鎖。TTL 應 > 預期業務耗時的 2-3 倍 |
| **用完即放** | 業務完成後用 `defer lock.Release(ctx)` 主動釋放，不要等 TTL 過期 |
| **Lua 原子釋放** | Release 必須用 Lua script 比對 value，防止釋放他人的鎖 |
| **鎖失敗返回 4xx** | 取不到鎖表示併發衝突，返回 `400 Bad Request` 或 `409 Conflict` |
| **不可重入** | 此實作不支援同一 goroutine 重入。如需重入鎖，額外維護計數器 |

---

## 任務隊列 (queue.go)

### 使用場景
- 異步發送郵件 / 通知
- 生成報表 / 匯出文件
- Webhook 回調處理
- 任何不需要即時完成的操作

### 架構：Redis List (LPUSH + BRPOP)

```
Producer (Service) → LPUSH → [Redis List] → BRPOP → Consumer (Worker)
```

### 封裝介面與實作

```go
// internal/infrastructure/redis/queue.go
package redis

import (
    "context"
    "encoding/json"
    "fmt"
    "log/slog"
    "time"

    "github.com/google/uuid"
    "github.com/redis/go-redis/v9"
)

// Task 代表一個隊列任務
type Task struct {
    ID        string          `json:"id"`
    Type      string          `json:"type"`       // 任務類型，例如 "email:send"
    Payload   json.RawMessage `json:"payload"`
    CreatedAt time.Time       `json:"created_at"`
    Retries   int             `json:"retries"`
}

// TaskHandler 處理特定類型任務的函數
type TaskHandler func(ctx context.Context, payload json.RawMessage) error

type QueueService struct {
    client *redis.Client
    prefix string
}

func NewQueueService(client *redis.Client, prefix string) *QueueService {
    return &QueueService{client: client, prefix: prefix}
}

func (q *QueueService) queueKey(taskType string) string {
    return fmt.Sprintf("%s:queue:%s", q.prefix, taskType)
}

func (q *QueueService) deadLetterKey(taskType string) string {
    return fmt.Sprintf("%s:queue:%s:dead", q.prefix, taskType)
}

// Enqueue 將任務推入隊列。
func (q *QueueService) Enqueue(ctx context.Context, taskType string, payload interface{}) error {
    data, err := json.Marshal(payload)
    if err != nil {
        return fmt.Errorf("queue marshal: %w", err)
    }

    task := Task{
        ID:        uuid.New().String(),
        Type:      taskType,
        Payload:   data,
        CreatedAt: time.Now(),
        Retries:   0,
    }

    taskData, err := json.Marshal(task)
    if err != nil {
        return fmt.Errorf("queue marshal task: %w", err)
    }

    return q.client.LPush(ctx, q.queueKey(taskType), taskData).Err()
}

// Consume 啟動 consumer loop，阻塞等待並處理任務。
// 在獨立的 goroutine 中呼叫。透過 ctx 取消來停止。
// maxRetries: 最大重試次數，超過則進入 dead letter queue。
func (q *QueueService) Consume(ctx context.Context, taskType string, handler TaskHandler, maxRetries int) {
    key := q.queueKey(taskType)
    slog.Info("queue consumer started", "type", taskType)

    for {
        select {
        case <-ctx.Done():
            slog.Info("queue consumer stopped", "type", taskType)
            return
        default:
        }

        // BRPOP 阻塞等待，timeout 1 秒（讓 select 有機會檢查 ctx）
        result, err := q.client.BRPop(ctx, 1*time.Second, key).Result()
        if err != nil {
            if err == redis.Nil || ctx.Err() != nil {
                continue
            }
            slog.Error("queue brpop failed", "type", taskType, "error", err)
            time.Sleep(1 * time.Second) // 避免錯誤風暴
            continue
        }

        var task Task
        if err := json.Unmarshal([]byte(result[1]), &task); err != nil {
            // 毒消息（解析失敗）不可默默丟棄——進 dead letter queue 留存待查
            slog.Error("queue unmarshal failed, moved to dead letter", "type", taskType, "error", err)
            q.client.LPush(ctx, q.deadLetterKey(taskType), result[1])
            continue
        }

        // 執行 handler
        if err := handler(ctx, task.Payload); err != nil {
            slog.Error("queue task failed", "type", taskType, "task_id", task.ID, "error", err, "retries", task.Retries)
            task.Retries++
            if task.Retries < maxRetries {
                // 重新入列前退避，避免零間隔熱循環（外部依賴故障時會瞬間燒完重試次數）；
                // 需要精細控制時改用 ZSET delayed queue
                time.Sleep(time.Duration(task.Retries) * time.Second)
                taskData, _ := json.Marshal(task)
                q.client.LPush(ctx, key, taskData)
            } else {
                // 進入 dead letter queue
                taskData, _ := json.Marshal(task)
                q.client.LPush(ctx, q.deadLetterKey(taskType), taskData)
                slog.Warn("queue task moved to dead letter", "type", taskType, "task_id", task.ID)
            }
        }
    }
}
```

### Service 層使用範例 (Producer)

```go
func (s *OrderService) Create(ctx context.Context, req CreateOrderRequest) (*entity.Order, error) {
    // 1. DB 事務建立訂單
    order, err := s.orderRepo.Create(ctx, ...)
    if err != nil {
        return nil, err
    }

    // 2. DB 成功後，將非同步任務推入隊列
    _ = s.queue.Enqueue(ctx, "email:order-confirmation", map[string]interface{}{
        "order_id": order.ID,
        "email":    req.Email,
    })

    return order, nil
}
```

### Consumer 註冊 (cmd/server/main.go)

```go
// 在 server 啟動時註冊 consumer
consumerCtx, consumerCancel := context.WithCancel(context.Background())
defer consumerCancel()

go queueService.Consume(consumerCtx, "email:order-confirmation", func(ctx context.Context, payload json.RawMessage) error {
    var data struct {
        OrderID uint   `json:"order_id"`
        Email   string `json:"email"`
    }
    if err := json.Unmarshal(payload, &data); err != nil {
        return err
    }
    return emailService.SendOrderConfirmation(ctx, data.OrderID, data.Email)
}, 3) // 最多重試 3 次

// Graceful shutdown 時先取消 consumer
// consumerCancel() ← 在 shutdown handler 中呼叫
```

### Queue 規則

| 規則 | 說明 |
|------|------|
| **DB 先於 Queue** | 先完成 DB 操作（事務提交），再 Enqueue。避免 DB 失敗但消息已發出 |
| **Enqueue 失敗不阻斷** | 主流程不因 Enqueue 失敗而回傳 500。記 `slog.Error` 並考慮補償機制 |
| **Handler 需冪等** | Consumer handler 必須設計為冪等（同一任務重複處理不會產生副作用） |
| **Dead Letter Queue** | 超過重試次數的任務**與解析失敗的毒消息**都進 dead letter queue，不可丟棄。需要人工/腳本處理 |
| **重試需退避** | 失敗任務重新入列前必須延遲（sleep / delayed queue），禁止零間隔立即重試 |
| **Graceful Shutdown** | 關閉 consumer 前先取消 context，等待當前任務完成（不中斷處理中的任務） |
| **BRPOP Timeout** | 設為 1 秒，讓 consumer loop 有機會檢查 context 取消信號 |

---

## Rate Limiting (middleware 搭配 Redis)

使用 Redis 計數器實作 API 限流中介軟體：

```go
// internal/interfaces/api/middleware/ratelimit.go

// INCR 與 EXPIRE 必須原子執行（Lua）：若分兩步，INCR 後 process crash 會留下
// 永不過期的計數 key，違反「所有 Key 必須設 TTL」規則。
var rateLimitScript = redis.NewScript(`
    local count = redis.call("INCR", KEYS[1])
    if count == 1 then
        redis.call("EXPIRE", KEYS[1], ARGV[1])
    end
    return count
`)

func RateLimitMiddleware(client *redis.Client, prefix string, limit int, window time.Duration) gin.HandlerFunc {
    return func(c *gin.Context) {
        key := fmt.Sprintf("%s:ratelimit:ip:%s", prefix, c.ClientIP())

        count, err := rateLimitScript.Run(c.Request.Context(), client, []string{key}, int(window.Seconds())).Int64()
        if err != nil {
            c.Next() // Redis 故障時放行，不阻斷服務
            return
        }

        if count > int64(limit) {
            c.AbortWithStatusJSON(http.StatusTooManyRequests,
                response.Response{Code: http.StatusTooManyRequests, Message: "請求過於頻繁，請稍後再試"})
            return
        }

        c.Next()
    }
}
```

---

## 測試指導

### 使用 miniredis (不依賴真實 Redis)

```go
// internal/application/service/product_service_test.go
package service_test

import (
    "testing"

    "github.com/alicebob/miniredis/v2"
    goredis "github.com/redis/go-redis/v9"
    redispkg "yourapp/internal/infrastructure/redis"
)

func setupTestRedis(t *testing.T) (*goredis.Client, *miniredis.Miniredis) {
    t.Helper()
    mr := miniredis.RunT(t)
    client := goredis.NewClient(&goredis.Options{
        Addr: mr.Addr(),
    })
    return client, mr
}

func TestProductService_GetByID_CacheHit(t *testing.T) {
    client, _ := setupTestRedis(t)
    cache := redispkg.NewCacheService(client, "test")

    // 預先塞入 cache
    cache.Set(context.Background(), "product:detail:1", &entity.Product{ID: 1, Name: "Test"}, 5*time.Minute)

    // ... 驗證 service 從 cache 取得資料，不呼叫 repo
}

func TestProductService_GetByID_CacheMiss(t *testing.T) {
    client, _ := setupTestRedis(t)
    cache := redispkg.NewCacheService(client, "test")

    // 不塞 cache → 驗證 service 查 DB 後回填 cache
}
```

### 測試 Lock

```go
func TestOrderService_Create_ConcurrentLock(t *testing.T) {
    client, _ := setupTestRedis(t)
    lockSvc := redispkg.NewLockService(client, "test")

    // 第一次取鎖成功
    lock1, err := lockSvc.Acquire(context.Background(), "order:create:user:1", 10*time.Second)
    assert.NoError(t, err)
    assert.NotNil(t, lock1)

    // 第二次取鎖失敗（已被鎖定）
    _, err = lockSvc.Acquire(context.Background(), "order:create:user:1", 10*time.Second)
    assert.Error(t, err)

    // 釋放後可再取鎖
    lock1.Release(context.Background())
    lock2, err := lockSvc.Acquire(context.Background(), "order:create:user:1", 10*time.Second)
    assert.NoError(t, err)
    assert.NotNil(t, lock2)
}
```

---

## .env.example 完整範例（Redis 相關）

```env
# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0
REDIS_POOL_SIZE=20
REDIS_MIN_IDLE_CONNS=5
REDIS_DIAL_TIMEOUT=5s
REDIS_READ_TIMEOUT=3s
REDIS_WRITE_TIMEOUT=3s

# Cache
CACHE_KEY_PREFIX=myapp   # 應用級 key 前綴，main.go 讀取後傳入 NewCacheService / NewLockService / NewQueueService
```

> 注意：TTL 與重試次數**不做成設定項**——TTL 每類快取各異，在呼叫點指定；maxRetries 是 `Consume()` 的參數。沒有代碼讀取的 key 不要放進 `.env.example`。
