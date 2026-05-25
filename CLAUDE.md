# Orua — 記帳 App（Monorepo）

個人記帳 app，iOS 端 + Go 後端 monorepo。**核心原則：API 只提供價格，使用者資料全部在手機內。**
角色定位： 你現在是一個盡責的全端兼PM，做錯事或者寫錯代碼就勇於承認錯誤，不要硬凹用替代方案。

## 倉庫分佈

| 路徑 | 角色 | 獨立 GitHub |
|------|------|------|
| `backend/go/` | Go + Gin 後端，聚合多家免費行情 API | `github.com/KeplerJhih/orua_go` (dev) |
| `native/ios/orua/` | SwiftUI iOS App | `github.com/KeplerJhih/orua_ios` (dev) |
| `frontend/landing/` | Vue3 公開官網 / 隱私條款 / Support | `github.com/KeplerJhih/orua_landing` (main) |
| `frontend/admin/` | Vue3 內部 admin dashboard(owner-only) | — |
| `devops/docker/` | 本機 infra（Postgres 18 + Redis 8） | — |
| `.claude/` | Skills / commands / hooks（獨立 git） | — |

`backend/go/` 與 `native/ios/orua/` 各自推送至獨立 repo 的 `dev` 分支。同步方式見各子專案的 CLAUDE.md。

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

### iOS（native/ios/orua）
- **Lot-based 持倉**：同 symbol 可多批購入，點持倉進 lots 明細
- **資產震幅（Asset Range）**：依期間顯示最高/最低 + 購買 timeline
- **成長指標**：OverviewHero 可切 1D/7D/30D/90D/1Y/ALL，每分類 Δ%
- **隱私模式**：只遮總額（淨值/分類/組小計），個別品項不遮
- **數字顯示設定**：Full / Compact × 小數位 0–4
- **字體縮放**：small/normal/large/xlarge（×0.9 ~ ×1.3）長者友善
- **下拉刷新節流**：可設 5s / 1min / 5min / 10min（iOS + backend 雙層 cache）
- **報價時間戳**：API 的 `fetched_at` 流向 UI（cache 命中會顯示原始抓取時間，非「剛剛」）
- **6 語系**：zh / zhCN / en / ja / fr / vi，in-memory 字典
- **標籤系統**：兩層 tag（Holding + Lot 都可打）、TagDetailView 含「鎖定計入」per-tag toggle
- **鎖定不計入**：兩層（整 Holding / 單一 Lot），右滑鎖、LockedView 列出
- **介面模式**：簡約（sheet 設計）vs 經典（iOS 26 Liquid Glass TabView）— 同頁設定 tab 順序與開關
- **資料備份**：JSON v2 (含 tags) / CSV 手動匯出 + Import + iCloud Drive 手動備份
- **iCloud 自動同步**（v2.7）：走 ubiquity container 跨裝置自動同步,設定 → Vault & Sync 啟用;衝突 sheet 讓 user 選邊,備份 conflict 檔留本機
- **設定頁補完**：Categories 隱藏子分類 / About / Local vault 詳情
- **分類順序與顯示**（2026-05）：頂層 5 分類 + 投資 6 子分類皆可拖曳排序 + Toggle 顯示;設定「清單與排序」為入口;主要分類至少留 1 個（防呆 shake + 警示淡入）;舊 `hiddenInvestmentSubs` 一次性 migrate 到新 `investSubConfig`
- **主功能 Menu + 統計模塊**（2026-05-17）：左上 Logo 點擊展開 `MainMenuSheet`，集中「標籤 / 鎖定 / 統計」三入口（右上設定 gear 不變）；經典模式新增 `.stats` tab 可拖序開關；`Features/Stats/` 4 個 tab × 12 張卡片，純函式集中在 `Core/Helpers/StatsCalculator.swift`
- **應收 / 負債事件流**（v2.9）：`Holding` 加 `principal / payments[] / recurring / settled` 4 欄,只對 receivable / debt 生效。`Features/Liability/` 完整 DetailSheet + RecurringCard + InlinePaymentBar。RecurringPlan 頻率改日 / 週 / 月 / 年,settleable alert 補開放式末段超額靜默 autoSettle 黑箱
- **SideDrawer + 邊緣手勢**（v2.9）：左 MainMenu(Logo / 左滑入)+ 右 Settings 雙入口分流(gear tap = 全屏 sheet / 右滑入 = 側板 drawer)。`Core/DesignSystem/SideDrawer.swift` 通用元件,`Core/Extensions/View+EdgeSwipe.swift` 包 UIKit `UIScreenEdgePanGestureRecognizer`(自帶 cancelsTouchesInView)
- **UIModeView 全域 sheet**（v2.9）：AppRootView 層 `.sheet`,切 mode 觸發 rootContent swap 時 sheet 不被拆,user 可連續切 mode 繼續調整 tab 順序
- **投資出售方案**（v3.0, 2026-05-25）：HoldingLotsSheet 底部 sticky bar 「↗ 售出」入口 → `SellHoldingSheet`(售價 + 「使用當前報價」shortcut + `SellLotPickerSheet` 逐 lot 填股數 + deposit picker 選 liquid 入帳)+ 方案預覽 + 公式 ⓘ popover(三段 FORMULA / FEE BREAKDOWN / NOTES)。執行扣股 + `LedgerStore.creditAmount` native-first 跨幣換算入 liquid + toast「已存入 X 到 Y」。買入 fee 按 `lot.fee × (sharesSold / lot.shares)` 攤入成本,`executeSell` 同步縮 lot 殘餘 fee。詳見 `native/ios/orua/CLAUDE.md` 的「投資出售方案」段(含 8 個踩雷紀錄)
- **Home / Stats 收尾**(v3.0, 2026-05-25):`Holding.updatedAt` 新欄位 + `LedgerStore.stampUpdated` 機制(15+ 處 user mutation 自動 stamp,quote 刷新 / replaceAll 明確不 stamp);AccordionDrawer 非 tradable row 副標 fallback(note → updatedAt → firstPurchaseAt);投資 sub-group(基金 / 台股 / 美股)獨立 collapse 含手風琴垂直壓縮動畫(`maxHeight 9999↔0 + .clipped()` trick 而非 `.move(edge:)`);Stats 損益分頁 B1 hero 改 3 欄(今日損益 / 累積損益 / 股票市值),`StatsCalculator.todayPnL` 公式 `Σ (q − prev) × shares × FX`。詳見 `native/ios/orua/CLAUDE.md` 「Home / Stats 收尾」段

## 端點速覽

| Method | Path | 認證 |
|--------|------|-----|
| GET  | `/health` | ❌ |
| POST | `/api/v1/auth/device` | ❌ |
| POST | `/api/v1/auth/register` / `/login` | ❌ |
| POST | `/api/v1/auth/upgrade`(匿名 → 實名) | ✅ |
| POST | `/api/v1/auth/change-password` | ✅ |
| GET  | `/api/v1/admin/stats`(admin only) | ✅ admin |
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
open native/ios/orua/orua.xcodeproj
# AppConfig.apiBaseURL DEBUG 指向 https://api.orua.app
```

## 部署現況

- **Backend**：Docker image `keplerjhih/orua_go:uat`，部署到 `api.orua.app`
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

**詳細子專案資訊見 `backend/go/CLAUDE.md` 與 `native/ios/orua/CLAUDE.md`。**

## 多幣別 Cost Basis（2026-04 P1）

**iOS 端**：`Lot` 加 `costCurrencyCode/costFXRate` 兩 optional 欄位，封存購買當下「源幣別 → baseCurrency」匯率。AddHoldingSheet cost 欄位加幣別 chip + 即時換算預覽 + sub-aware 量級警示。CurrencyCatalog 擴至 18 種（+ GBP/KRW/SGD/AUD/CAD/CHF/INR/THB/IDR + USDT/USDC）。FXRates 加穩定幣 alias（USDT/USDC/DAI/BUSD → USD pegged）。已驗證 v1/v2/v3 老資料完全相容。

**後端**：新增 `MarketHK` 港股市場（5 檔同步），iOS 端對應加 `QuoteMarket.HK` + `InvestmentSub.stock.allowedMarkets` 加 .HK，nativeCurrencyCode 對 .HK 回 HKD。Yahoo provider 走 `0700.HK` 格式，自動補零至 4 碼。

**支援場景**：日圓買美股 / 台幣買 BTC / USDT 買 SOL / 港股 / 韓元/英鎊/新加坡幣等使用者本國幣記帳。

詳見 `backend/go/CLAUDE.md` 的「HK market」段與 `native/ios/orua/CLAUDE.md` 的「多幣別 Cost Basis」段。

## Admin Dashboard(2026-05-16 新增)

內部 owner-only 監控站,**不對外、不放給 user 看**。三件支柱:

1. **Backend `/api/v1/admin/stats`**:5 個 collector errgroup 並行(users / devices / quotes / query_freq / active),整體 response cache 30s + singleflight 防擊穿。Active block 由 `ENABLE_ACTIVITY_TRACKING=true` 啟用 `RecordActivity` middleware 寫 Redis,提供真實 DAU / WAU / MAU / Online5min / Retention D1/D7/D30 / 24h heatmap。flag off 時整塊 `omitempty` 不出現,iOS-only 場景仍向後相容。

2. **Frontend `frontend/admin/`(新 Vue3 站)**:獨立站對齊 landing 的 OKLCH design token,三分頁(總覽 / 使用者 / 報價)切 tab 不換頁、共用單一 stats reactive,輪詢 10s 可切 30s/暫停。Email dropdown 含「變更密碼」+「登出」入口,變更後強制 logout + redirect `/login?changed=1` 顯示綠色提示(柔性吊銷,不引入 token blacklist 複雜度)。容器化跟 landing 100% 同 pattern:`.devops/dockerfile` + `nginx.conf` + `Makefile`(ECR `orua/admin:{latest,sha}`,linux/arm64,**前端容器統一 nginx :8080**,vite dev 5174 避撞 landing;同源 reverse proxy 模式見 `.claude/skills/frontend/references/api-proxy-pattern.md`)。

3. **隱私紅線(契約 §0)**:`device_id` 永遠回尾 4 碼、`email`/`password_hash`/holdings 完全不出現在 admin response。`team/contracts/admin-dashboard.api.md` 為單一 source of truth,`team/decisions/admin-dashboard.log.md` 紀錄 13+ 條設計取捨,`team/reviews/admin-dashboard.review.md` cr-admin 完整審查(220 行,0 BLOCKER)。

**對 iOS 完全 zero impact**:所有改動是 additive(新 endpoint / response 多欄位 / middleware 透明掛 / 內部優化),Swift Codable 預設忽略 unknown key,backend 單獨部署不必動 iOS。

詳見 `backend/go/CLAUDE.md` 的「Admin dashboard」+「RecordActivity」段、`frontend/admin/CLAUDE.md`。

## CLAUDE.md 維護方針

每個子專案各自有 CLAUDE.md，作為新對話開啟時最快補齊上下文的索引。當你做了**任何子專案的重大變更**（新增功能 / 改架構 / 踩過值得記的坑），請順手更新對應的 CLAUDE.md：

| 變更範圍 | 要更新的 CLAUDE.md |
|---------|-----------------|
| 純後端（service / provider / handler / DB） | `backend/go/CLAUDE.md` |
| 純 iOS（domain / store / view / i18n） | `native/ios/orua/CLAUDE.md` |
| 純官網 / landing | `frontend/landing/CLAUDE.md` |
| 跨專案的功能總覽 / 端點 / 部署 | 本檔（`.claude/CLAUDE.md`） |
| `.claude/skills/` 規範變更 | 對應 skill 的 SKILL.md（不是 CLAUDE.md）|

**準則**：
- CLAUDE.md 是**索引 + 踩坑紀錄**，不是 changelog（commit message 才是）
- 寫法：列出**為什麼**這樣設計、**碰過什麼坑**、**新檔案放哪裡**，不要列出每個 commit 的細節
- 新增段落寧短勿長 — 單一段落 ≤ 200 字。長篇 reference（例如 SWAGGER 規範）放 `.claude/skills/*/references/`
