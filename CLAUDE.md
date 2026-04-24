# Stash — 記帳 App（Monorepo）

個人記帳 app，iOS 端 + Go 後端 monorepo。**核心原則：API 只提供價格，使用者資料全部在手機內。**

## 倉庫分佈

| 路徑 | 角色 | 獨立 GitHub |
|------|------|------|
| `backend/go/` | Go + Gin 後端，聚合多家免費行情 API | `github.com/KeplerJhih/stash_go` (dev) |
| `native/ios/stash/` | SwiftUI iOS App | `github.com/KeplerJhih/stash_ios` (dev) |
| `devops/docker/` | 本機 infra（Postgres 18 + Redis 8） | — |
| `.claude/` | Skills / commands / hooks（獨立 git） | — |

`backend/go/` 與 `native/ios/stash/` 各自推送至獨立 repo 的 `dev` 分支。同步方式見各子專案的 CLAUDE.md。

## 整體架構

```
  iOS App ──────────► Backend ─────► 免費 Provider 鏈
 (SwiftUI)              (Gin)        (TWSE / Yahoo / CoinGecko …)
     │                    │
     │ 本地           ┌───┴────┐
     │ 儲存           │ Redis  │ (cache)
     ▼                │ Postgres│ (持久化報價 + User/Device)
 Documents/           └────────┘
  ledger.json
  history.json
```

**職責劃分**：
- **後端**：行情聚合（validation + 關盤短路 + 三層讀取）、匿名 device session 認證、匯率
- **iOS**：所有使用者資料（holdings / lots / history / settings）一律本地 JSON + Keychain

## 核心特性（功能總覽）

### 後端（backend/go）
- DDD 四層：`domain` → `application` → `infrastructure` → `interfaces`
- **匿名 device session**：`POST /auth/device` 冪等，同 device_id 永遠對應同 user（無密碼）
- **報價三層**：Cache → DB(fresh) → Provider（primary+fallback，逐 symbol 補齊）
- **報價驗證**：price≤0 / NaN 不寫 Cache / DB，自動 fallback 下一家
- **關盤短路**：非 CRYPTO 市場關盤時，有 DB 紀錄就直接回，不打 Provider
- Symbol 搜尋 / FX 匯率（OpenERAPI）
- `DB_AUTO_MIGRATE` 開機自動 migrate
- Swagger end-to-end（/swagger/*）

### iOS（native/ios/stash）
- **Lot-based 持倉**：同 symbol 可多批購入，點持倉進 lots 明細
- **資產震幅（Asset Range）**：依期間顯示最高/最低 + 購買 timeline
- **成長指標**：OverviewHero 可切 1D/7D/30D/90D/1Y/ALL，每分類 Δ%
- **隱私模式**：只遮總額（淨值/分類/組小計），個別品項不遮
- **數字顯示設定**：Full / Compact × 小數位 0–4
- **字體縮放**：small/normal/large/xlarge（×0.9 ~ ×1.3）長者友善
- **下拉刷新節流**：可設 5s / 1min / 5min / 10min（iOS + backend 雙層 cache）
- **報價時間戳**：API 的 `fetched_at` 流向 UI（cache 命中會顯示原始抓取時間，非「剛剛」）
- **5 語系**：zh / zhCN / en / ja / fr，in-memory 字典
- **標籤系統**：兩層 tag（Holding + Lot 都可打）、TagDetailView 含「鎖定計入」per-tag toggle
- **鎖定不計入**：兩層（整 Holding / 單一 Lot），右滑鎖、LockedView 列出
- **介面模式**：簡約（sheet 設計）vs 經典（iOS 26 Liquid Glass TabView）— 同頁設定 tab 順序與開關
- **資料備份**：JSON v2 (含 tags) / CSV 匯出 + Import + iCloud Drive 提示（Tier 1）
- **設定頁補完**：Categories 隱藏子分類 / About / Local vault 詳情

## 端點速覽

| Method | Path | 認證 |
|--------|------|-----|
| GET  | `/health` | ❌ |
| POST | `/api/v1/auth/device` | ❌ |
| POST | `/api/v1/auth/register` / `/login` | ❌ |
| POST | `/api/v1/auth/upgrade`（匿名 → 實名） | ✅ |
| GET  | `/api/v1/markets` | ❌ |
| GET  | `/api/v1/quotes` / `/quotes/batch` | ✅ |
| GET  | `/api/v1/symbols` / `/fx/rates` | ✅ |
| GET  | `/swagger/*any`（debug） | ❌ |

## 啟動流程

```bash
# 1. Infra
cd devops/docker && cp .env.example .env && docker compose up -d

# 2. Backend
cd backend/go && cp .env.example .env
make tidy && make dev    # AutoMigrate 啟動時自動跑

# 3. iOS
open native/ios/stash/stash.xcodeproj
# AppConfig.apiBaseURL DEBUG 指向 https://stash.keplerxu.com
```

## 部署現況

- **Backend**：Docker image `keplerjhih/stash_go:uat`，部署到 `stash.keplerxu.com`
- **Compose log rotation**：10MB × 10 檔（上限 ~100MB）
- **DB_AUTO_MIGRATE=true**：新 DB 部署時 server 自動建表

## 開發規範（skill）

- `/doit` 指令走 Tech Lead workflow
- 相關 skill：`backend-go`（DDD 規範、SWAGGER/LOGGING/REDIS references）、`frontend`（iOS / React 通用 RWD）、`qa`、`devops`、`deploy-remote`
- 測試指令：backend `make test` / iOS `xcodebuild` + `swift scripts/test_logic.swift`

## 其他備忘

- Compose env 跟 backend env **嚴格分離**（`devops/docker/.env` vs `backend/go/.env`）
- `.gitignore` 含 `.env copy` / `.env 2` 等 Finder 複製防呆規則
- 根目錄與 `.claude/` 為獨立 git repo（flatten 過 nested `.git`）

**詳細子專案資訊見 `backend/go/CLAUDE.md` 與 `native/ios/stash/CLAUDE.md`。**
