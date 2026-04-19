# Stash — 記帳 App

記帳 app，名稱為 **Stash**。後端聚合台股 / 美股 / 日股 / 虛擬貨幣 的免費行情來源，提供統一 API 給 app 使用。

## 目錄結構

```
stash/
├── backend/go/                     # Go 後端（DDD 架構）
│   ├── cmd/
│   │   ├── server/main.go          # API server 入口（含 graceful shutdown）
│   │   └── cli/main.go             # 管理 CLI（cobra: migrate、create-admin）
│   ├── internal/
│   │   ├── domain/                 # Entity + Repository interfaces（零外部依賴）
│   │   │   ├── entity/             # User、Quote、Market
│   │   │   └── repository/         # UserRepository、PriceProvider interface
│   │   ├── application/service/    # AuthService、QuoteService（業務邏輯 + 測試）
│   │   ├── infrastructure/
│   │   │   ├── config/             # viper 讀取 .env
│   │   │   ├── persistence/        # GORM 實作（PostgreSQL）
│   │   │   ├── provider/           # 可切換數據源的核心
│   │   │   │   ├── registry.go     # Provider 註冊中心
│   │   │   │   ├── router.go       # Market → provider 鏈（含 fallback）
│   │   │   │   ├── twse/           # 台股
│   │   │   │   ├── yahoo/          # US / TW / JP
│   │   │   │   ├── stooq/          # US / JP
│   │   │   │   ├── coingecko/      # CRYPTO
│   │   │   │   └── binance/        # CRYPTO
│   │   │   └── redis/              # go-redis v9（cache / lock / queue）
│   │   ├── interfaces/api/         # handler / middleware / router
│   │   └── mocks/                  # testify mock
│   ├── pkg/                        # 可共用工具：logger / errors / response / httpclient / auth(JWT)
│   ├── .env.example
│   ├── Makefile                    # build / run / dev / test / migrate / create-admin / swagger
│   └── go.mod
│
├── devops/docker/                  # 基礎設施（env 獨立於後端）
│   ├── docker-compose.yml          # Postgres 18 + Redis 8
│   ├── .env / .env.example         # infra 專屬設定
│   └── README.md
│
└── .claude/                        # skills / commands / hooks
```

## 架構重點

- **DDD 分層**：`domain` → `application` → `infrastructure` → `interfaces`，依賴單向往內。
- **可切換數據源**：`PriceProvider` interface + `Registry` + `Router`。
  - 新增一家免費平台：實作 interface → 註冊到 registry → 改 `.env` 即可。
  - 路由配置：`MARKET_TW_PROVIDERS=twse,yahoo`（第一個為 primary，其餘為 fallback）。
- **快取**：Redis Cache-Aside，報價預設 TTL 30s，避免打爆免費 API。
- **認證**：JWT 無狀態（`pkg/auth` + `middleware/auth.go`）。
- **PostgreSQL**：GORM，透過 `cmd/cli migrate` 跑 AutoMigrate。

## 端點

| Method | Path | 認證 |
|--------|------|-----|
| GET  | `/health` | ❌ |
| POST | `/api/v1/auth/register` | ❌ |
| POST | `/api/v1/auth/login` | ❌ |
| GET  | `/api/v1/markets` | ❌ |
| GET  | `/api/v1/quotes?market=TW&symbol=2330` | ✅ |
| GET  | `/api/v1/quotes/batch?market=US&symbols=AAPL,TSLA` | ✅ |

## 啟動流程

```bash
# 1. 啟 infra（Postgres + Redis）
cd devops/docker && cp .env.example .env && docker compose up -d

# 2. 啟後端
cd backend/go && cp .env.example .env
make tidy && make migrate && make dev
```

## 技術棧

Go 1.25 + Gin + GORM + PostgreSQL 18 + go-redis v9 + Redis 8 + JWT + viper + cobra + swag + testify + miniredis
