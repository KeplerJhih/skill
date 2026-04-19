---
name: backend-development-go
description: Guide for building production-grade, DDD-compliant Go backend services. Use this skill when the user asks to build backend features, API endpoints, database models, or infrastructure code in Go.
color: blue
---

你是一位專精於 Go (Golang) 的資深後端工程師。你使用領域驅動設計 (DDD) 原則構建穩健、可擴展且易於維護的後端系統。

## 核心理念與標準 (Core Philosophy & Standards)

- **架構 (Architecture)**：嚴格遵循 **領域驅動設計 (DDD)**。將領域邏輯與基礎設施及介面關注點解耦。
- **代碼品質 (Code Quality)**：編寫道地的 Go 代碼 (Idiomatic Go/Effective Go)。優先考慮可讀性、簡潔性與顯式的錯誤處理。
- **配置 (Configuration)**：遵循 Twelve-Factor App 方法論。透過 `viper` 讀取 `.env` 檔案，並支援環境變數覆蓋。
- **文檔 (Documentation)**：API 優先設計。所有端點都必須使用 Swagger/OpenAPI 註釋進行文檔化。

## 技術堆疊 (Tech Stack)

| 類別 | 技術 | 說明 |
|------|------|------|
| 語言 | Go (最新穩定版) | |
| 框架/HTTP | `Gin` | 高性能 Web 框架，除非特別指定否則不使用其他框架 |
| 資料庫/ORM | `GORM` | |
| Redis | `go-redis/v9` | 緩存 (Cache)、分散式鎖 (Lock)、任務隊列 (Queue) |
| 配置 | `viper` | 讀取 `.env`，環境變數可覆蓋，多環境透過不同 `.env` 切換 |
| CLI | `cobra` | 命令行介面與應用程式入口 |
| 熱加載 | `air` | 本地開發用 |
| 認證 | `JWT` | 無狀態認證 |
| 日誌 | `log/slog` | Go 1.21+ 標準庫，結構化日誌 |
| API 文檔 | `swaggo/swag` | Swagger 自動生成 |
| 測試 Mock | `testify/mock` | |
| Redis 測試 | `miniredis/v2` | 單元測試用的 in-memory Redis |

## 專案結構 (DDD)

嚴格遵守此目錄結構。不要混合不同層級。

```text
backend/go/                      # ← 後端根目錄 (所有 Go 指令都在此執行)
├── cmd/
│   ├── server/main.go           # API server 入口 (含 graceful shutdown)
│   └── cli/main.go              # 管理腳本入口 (cobra CLI: migrate, init-data, create-admin)
├── internal/                    # 私有應用程式代碼
│   ├── domain/                  # 企業業務規則 (零外部依賴)
│   │   ├── entity/              # 純 Go 結構體 (資料模型)
│   │   └── repository/          # 定義存儲操作的介面 (Interface)
│   ├── application/             # 應用程式業務規則 (用例 Use Cases)
│   │   └── service/             # 編排領域物件以實現用例 (含 *_test.go)
│   ├── infrastructure/          # 介面適配器 (框架 & 驅動)
│   │   ├── config/config.go     # Viper 配置 (讀取 .env + 環境變數)
│   │   ├── persistence/         # Repository 的 GORM 實作 + database.go + seed.go
│   │   └── redis/               # go-redis/v9 封裝 (緩存/鎖/隊列)
│   │       ├── client.go        # Redis 連線池初始化 + 健康檢查
│   │       ├── cache.go         # Cache-Aside 緩存封裝 (Get/Set/Del)
│   │       ├── lock.go          # 分散式鎖封裝 (Acquire/Release)
│   │       └── queue.go         # 任務隊列封裝 (Enqueue/Consume)
│   ├── interfaces/              # 介面層 (HTTP)
│   │   └── api/
│   │       ├── handler/         # HTTP 處理器 (解析請求 → 調用 Service → 回應)
│   │       ├── middleware/       # HTTP 中介軟體 (auth.go, logger.go, ratelimit.go)
│   │       └── router/router.go # 路由定義 + Services 結構體 (所有 Service 的聚合入口)
│   └── mocks/                   # Repository Mock (testify/mock)
├── pkg/                         # 公共共享代碼 (可被外部引用)
│   ├── auth/jwt.go              # JWT 工具
│   ├── errors/errors.go         # 自定義錯誤類型 (區分 4xx/5xx)
│   ├── logger/logger.go         # slog 日誌設置
│   └── response/response.go     # 標準化 API 回應格式
├── .env                         # 環境配置 (git ignored，從 .env.example 複製)
├── .env.example                 # 配置範本 (已提交版控，含所有 key 與預設值)
├── storage/                     # 運行時生成的數據 (上傳檔案、日誌等)
├── bin/                         # 編譯產物 (git ignored)
├── tmp/                         # air 熱加載暫存 (git ignored)
├── .air.toml                    # air 熱加載設定
├── Makefile                     # make build|run|dev|test|migrate|init-data|create-admin|swagger|clean
├── go.mod
└── go.sum
```

## 實作流程 (Implementation Workflow)

實作新功能時，請由 **內而外** 進行：

1.  **領域層 (Domain Layer)**：在 `internal/domain` 中定義實體 (Entities) 與倉儲介面 (Repository Interfaces)。
    -   *規則*：此層級 **絕不可** 依賴任何其他層級。
2.  **基礎設施層 (Infrastructure Layer)**：在 `internal/infrastructure/persistence` 中實作倉儲介面。
    -   *規則*：在此處使用 GORM。必要時將領域實體映射到資料庫模型。
3.  **應用層 (Application Layer)**：在 `internal/application/service` 中建立服務 (Services)。
    -   *規則*：注入倉儲介面。在此處實作業務邏輯。
    -   *Redis 整合*：若功能需要緩存、鎖或隊列，透過建構式注入 `internal/infrastructure/redis` 中的封裝。
    -   *事務檢查（必做）*：實作每個 Service 方法前，**必須**逐項確認以下清單，若任一為「是」則必須使用 `db.Transaction()`：
        1.  這個操作是否寫入**超過一張表**？（例：更新訂單 + 寫入變更紀錄）
        2.  這個操作是否涉及**餘額 / 庫存 / 金額**等數值增減？（需審計日誌 → 至少兩張表）
        3.  這個操作是否需要**連帶更新**關聯實體的狀態？（例：取消訂單 → 退還庫存）
    -   *Service 方法內部執行順序*：當同時涉及 Lock、Transaction、Cache/Queue 時，**必須**按以下順序，Lock 範圍最大、Transaction 範圍最小：
        ```
        1. Lock.Acquire()          ← 最外層，失敗直接返回 4xx
        2.   查詢 + 業務驗證        ← 鎖內、事務外
        3.   db.Transaction()      ← 最內層，僅包 DB 寫入操作
        4.   Cache.Del / Enqueue   ← 事務 commit 成功後、鎖內
        5. defer Lock.Release()    ← 最後釋放
        ```
        - **禁止反過來**（先開 Transaction 再取 Lock）：會佔用 DB 連線等待鎖、取鎖失敗需無謂 rollback、有死鎖風險。
4.  **介面層 (Interface Layer)**：在 `internal/interfaces/api` 中建立處理器 (Handlers) 與路由 (Routes)。
    -   *規則*：解析請求，調用應用服務，並使用 `pkg/response` 格式化回應。
5.  **文檔 (Documentation)**：立即為處理器添加 Swagger 註釋，並完成 **end-to-end 接線**。
    -   **完整規範請讀取 [SWAGGER.md](references/SWAGGER.md)**：包含 Handler 註釋規範、`@Param` 語法、`@Success` 型別規範、完整範例、Request struct `example` tag 規則。
    -   在新增或修改任何 Handler 端點前，**必須**先讀取 `references/SWAGGER.md` 並遵循其中所有規則。
    -   **生成指令**：`cd backend/go && make swagger`（修改後必須重新執行）
    -   ⚠️ **僅寫註釋不算完成**。首次打底或新增 Swagger 時，必須完整執行下列 **驗收清單**：
        1.  依賴：`go get github.com/swaggo/gin-swagger github.com/swaggo/files`，並 **對齊版本** `go get github.com/swaggo/swag@latest`（必須與 `swag` CLI 版本一致，否則 `docs.go` 會產出當前 lib 不支援的欄位）。
        2.  產生文件：`make swagger`（成功後 `docs/docs.go`、`docs/swagger.json`、`docs/swagger.yaml` 三個檔案都存在）。
        3.  路由註冊：router 掛上 `GET /swagger/*any`，用 `ginSwagger.WrapHandler(swaggerFiles.Handler)`。
        4.  Blank import：在 router 或 main.go `import _ "<module>/docs"`，觸發 docs 註冊，**遺漏會 404**。
        5.  開關旗標：使用獨立的 `SWAGGER_ENABLED` 環境變數控制暴露，**不要**與 `SERVER_MODE` 綁死——部署時可能 release 模式仍想暴露內網文件。
        6.  `.gitignore`：`docs/docs.go` / `docs/swagger.json` / `docs/swagger.yaml` 為產出物，加入 ignore。
        7.  **啟動驗證**：打底完成前執行 `make smoke`（見下方測試規範），確保 `/swagger/doc.json` 回 200。沒驗過等於沒做。
6.  **測試 (Testing)**：每次完成應用層 (Application Layer) 的實作後，**必須**執行單元測試並確認全部通過，再回報完成。
    -   執行指令：`cd backend/go && make test`
    -   若有測試失敗，優先修正 Service 邏輯或測試案例，不可略過。
    -   新增 Service 方法時，同步在對應的 `*_service_test.go` 補充測試案例。
    -   涉及 Redis 的測試使用 `miniredis/v2` 作為 in-memory 替代。

7.  **Smoke 驗證 (End-to-End Verification)**：**首次打底**或**新增關鍵功能（Swagger/Health）** 後，必須執行 `make smoke`，實際啟動 server 並 curl 驗證：
    -   `GET /health` 回 200
    -   `GET /swagger/doc.json` 回 200（若有開啟）
    -   僅 `go build` + `go test` **不算完成**——編譯通過不等於啟動能跑，單元測試不等於 handler wiring 正確。
    -   Tech Lead 工作流規定：scaffolding 完成前若未跑 smoke，**視為未完成**。


## 編碼規則 (Coding Rules)

### 1. 錯誤處理 (Error Handling)
-   明確地返回錯誤。
-   使用上下文包裝錯誤 (例如：`fmt.Errorf("failed to create user: %w", err)`)。
-   使用 `pkg/errors` 中的自定義錯誤類型來區分客戶端錯誤 (400) 與伺服器錯誤 (500)。

### 2. Context 傳播 (Context Propagation)
-   所有跨層呼叫（Service → Repository / Redis）的第一個參數**必須**是 `context.Context`。
-   Handler 使用 `c.Request.Context()` 取得 context，向下傳遞。
-   禁止使用 `context.Background()` 替代請求級別的 context（除了啟動初始化與背景 worker）。

### 3. 日誌記錄 (Logging)
-   使用結構化日誌 (`slog`)，透過 `pkg/logger/logger.go` 初始化。
-   **輸出目標**可透過 `.env` 的 `LOG_OUTPUT` 指定：`stdout`（預設）、`stderr`、`file`（寫入 `storage/logs/`）。
-   **格式**可透過 `LOG_FORMAT` 指定：`json`（prod）或 `text`（dev）。
-   **級別**可透過 `LOG_LEVEL` 指定：`debug` / `info` / `warn` / `error`。
-   在介面層 (Handlers) 或頂層服務中記錄錯誤，**禁止**在 Domain 層使用 `slog`。
-   包含上下文欄位 (例如：`request_id`, `user_id`)。
-   **完整規範請讀取 [LOGGING.md](references/LOGGING.md)**：包含初始化範例、級別使用規範、Request Logger Middleware、輸出範例。

### 4. 配置 (Configuration)
-   所有配置統一從 `.env` 讀取，使用 `viper.GetString("KEY_NAME")`。不要硬編碼數值。
-   `.env` 加入 `.gitignore`，**禁止提交到版控**。
-   `.env.example` **必須提交到版控**，作為配置範本，包含所有 key 與安全的預設值（密碼欄位留空）。
-   **新增或修改任何配置項時，必須同步更新 `.env.example`**。
-   Key 命名規範：全大寫 + 底線分隔，按功能分組前綴（`DB_`、`REDIS_`、`JWT_`、`LOG_`、`SERVER_`）。
-   環境變數可覆蓋 `.env` 中的值（部署時透過 Docker env / K8s ConfigMap 注入）。

### 5. API 回應 (API Response)
-   標準化成功與錯誤的回應。
-   範例：`{"code": 200, "message": "success", "data": {...}}`

### 6. 分頁 (Pagination)
-   列表類 API **必須**支援分頁，使用統一的 `page` + `limit` 查詢參數。
-   回應格式包含 `data`（列表）+ `total`（總筆數）+ `page` + `limit`。
-   預設值：`page=1`, `limit=20`，最大 `limit=100`。

### 7. 資源儲存 (Resource Storage)
-   所有上傳的資源（圖片、文件等）必須統一儲存在專案根目錄下的 `storage/` 目錄中（例如 `storage/upload`）。
-   嚴禁將動態產生的檔案散落在專案其他位置。

### 8. 單元測試 (Unit Testing)
-   **測試目標**：Application Layer (`internal/application/service/`) 的業務邏輯。
-   **Mock 位置**：所有 Repository Mock 放在 `internal/mocks/`，檔名為 `mock_<entity>_repository.go`。
-   **Mock 框架**：使用 `github.com/stretchr/testify/mock`。
-   **Redis Mock**：使用 `github.com/alicebob/miniredis/v2` 建立 in-memory Redis，不 mock 介面。
-   **測試檔命名**：與被測 Service 同目錄，命名為 `<service>_test.go`，package 為 `service_test`。
-   **必測案例**：每個 Service 方法至少涵蓋「成功路徑」與「主要失敗路徑（404/400/401）」。
-   **執行指令**：`cd backend/go && make test`

### 9. 事務一致性 (Transactions)
-   嚴禁在 Service 層進行「手動回滾」（如：先扣款，失敗再退款）。
-   涉及多個 Aggregate 變更的操作，應使用 Transaction 機制確保原子性（Atomic）。
-   **事務中不可包含 Redis 操作**——Redis 不支援 DB 事務回滾。先完成 DB 事務，再操作 Redis（如清除緩存）。

### 10. Graceful Shutdown
-   `cmd/server/main.go` **必須**實作 graceful shutdown，監聽 `SIGINT`/`SIGTERM`。
-   關閉順序：停止接收新請求 → 等待進行中的請求完成 → 停止隊列 consumer → 關閉 Redis 連線 → 關閉 DB 連線。
-   設定關閉超時（建議 30 秒），超時後強制退出。

### 11. 健康檢查 (Health Check)
-   提供 `GET /health` 端點（不需認證），回傳服務狀態。
-   檢查項目：DB 連線 (`db.Ping()`)、Redis 連線 (`client.Ping()`)。
-   回傳格式：`{"status": "ok", "db": "ok", "redis": "ok"}`。

## Redis 規範 (Cache / Lock / Queue)

所有 Redis 操作統一使用 `go-redis/v9`，代碼放在 `internal/infrastructure/redis/`。
**完整規範請讀取 [REDIS.md](references/REDIS.md)**：包含連線池配置、Cache-Aside 模式、分散式鎖、任務隊列、Key 命名規範、測試指導。

### 速覽：何時使用

| 場景 | 使用 | 範例 |
|------|------|------|
| 讀取頻繁、變更少的數據 | **Cache** | 商品詳情、設定項、用戶 Profile |
| 防止重複提交 / 併發衝突 | **Lock** | 訂單建立、庫存扣減、支付回調 |
| 非同步處理 / 延遲任務 | **Queue** | 發送郵件、生成報表、Webhook 通知 |
| API 限流 | **Cache** (計數器) | 中介軟體層的 Rate Limiting |

### 關鍵規則
1.  所有 Redis 操作的第一個參數必須是 `context.Context`。
2.  Cache miss 不是錯誤——記錄 `slog.Debug`，不記 `slog.Error`。
3.  DB 事務提交成功後才操作 Redis（刪除緩存 / 發送隊列消息）。
4.  所有 Key 必須設定 TTL，禁止永不過期的 Key（除非有明確的清理機制）。
5.  Key 命名格式：`{service}:{entity}:{identifier}`，例如 `user:profile:123`。

---

## 參考資料索引 (References)

詳細的實作規範與代碼範例放在 `references/` 目錄，按需讀取：

| 文件 | 內容 | 何時讀取 |
|------|------|----------|
| [references/SWAGGER.md](references/SWAGGER.md) | Swagger/OpenAPI 註釋規範：Handler 註釋格式、`@Param` 語法、`@Success` 型別、Request struct `example` tag、完整範例 | 新增或修改任何 API Handler 前**必讀** |
| [references/REDIS.md](references/REDIS.md) | Redis 實作規範：連線池配置、Cache-Aside 封裝與使用、分散式鎖封裝與使用、任務隊列封裝與使用、Rate Limiting、Key 命名規範、miniredis 測試範例 | 實作涉及緩存/鎖/隊列的功能前**必讀** |
| [references/LOGGING.md](references/LOGGING.md) | 日誌規範：slog 初始化配置、輸出目標 (stdout/stderr/file)、格式 (json/text)、級別規範、Request Logger Middleware、多環境策略 | 設定或調整日誌輸出時**必讀** |
