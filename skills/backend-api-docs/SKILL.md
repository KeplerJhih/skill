---
name: backend-api-docs
version: 1.0.0
description: This skill should be used when the user asks to "產生 API 文件", "建立 API 契約", "把 Swagger UI 換成 Scalar", "Swagger 2.0 轉 OpenAPI 3.0", "整理 API 規格給其他開發者或 AI", or mentions swag / OpenAPI / Scalar / API docs page for a backend service. Defines OpenAPI 3.x as the single contract source, the generation pipeline, the self-hosted docs page rules, and the handover checklist. Language-neutral principles with Go (swaggo/swag) reference.
color: teal
---

# 後端 API 契約與文件（OpenAPI 3.x + Scalar）

後端負責維護 **一份** API 契約，前端型別、文件頁、交接給其他開發者或 AI 工具的都吃這一份。
本 skill 定義契約怎麼產、文件頁長什麼樣、交接要給什麼；語言專屬的註解寫法在 `references/`。

> 適用範圍：任何有 HTTP API 的後端。前端 / 行動端只是消費者，不需要載入本 skill；型別怎麼產寫在該專案的 CLAUDE.md。

---

## 核心原則

1. **正本只有一份，而且是 OpenAPI 3.x。** 進版控的規格檔只有 `docs/openapi3.json`（或該語言慣用的檔名）。產生器若只吐得出 Swagger 2.0，把它當中間產物放暫存目錄（gitignored），同一個指令接著轉成 3.0。不要同時保留 2.0 與 3.0 兩份在版控裡，也不要保留 `docs.go`、`swagger.yaml` 這類只給 Swagger UI 用的產物。
2. **註解即契約，照實寫。** 3.0 的型別產生器會照 `required` / `nullable` 產生型別：可省略的請求欄位必須標成非必填、可為 null 的欄位必須標 nullable。前端型別檢查噴出「必填但可 null」時，是後端標記該補，不在前端補假值。
3. **tag 是文件的目錄。** 命名 `<入口> - <資源>`（例如 `Admin - Orders`、`Customer - Orders`），每個 tag 都要有一句說明。文件頁依前綴自動分區，新增 tag 不用改文件頁。
4. **文件頁四條規則。** 只在非正式環境註冊；資產內嵌在後端，不連外部 CDN；需要登入的 API 要能在頁面上登入後直接試打；會把規格上傳到第三方的功能（例如 Scalar 的 Ask AI）預設關閉。
5. **一個指令。** `make swagger`（或該專案的等價目標）從註解做到 3.0 規格檔，改完註解跑一次就好；沒有第二個步驟要記。

---

## 產生流程

```
handler 註解 ──▶ 產生器 ──▶ (2.0 中間產物，暫存) ──▶ 轉換 ──▶ docs/openapi3.json（正本，進版控）
                                                                   ├─▶ 文件頁 /docs/（內嵌，非正式環境）
                                                                   ├─▶ 前端 / 行動端型別產生
                                                                   └─▶ 交接：直接把這個檔給人或 AI
```

- **Go（swaggo/swag）**：swag v1 只產 2.0，用 `assets/openapi3-convert.go`（kin-openapi）轉 3.0 並把 `x-nullable` 轉成 `nullable`。完整步驟、註解規範、踩坑見 `references/go-swag.md`。
- **原生就產 3.x 的框架**（FastAPI 等）：省略轉換，其餘規則相同。
- **Flask-RESTX**：內建的是 Swagger UI 與 2.0，文件頁與 3.0 交付改依本 skill（註解寫法仍看 `backend-python` 的 reference）。

---

## 路徑 A：新專案

1. 依 `references/go-swag.md`（或該語言的 reference）寫註解；一開始就用 `<入口> - <資源>` tag，並在 API 元資料加 `@tag.name` / `@tag.description`。
2. 複製 `assets/openapi3-convert.go` 到 `cmd/openapi3/`，Makefile 的 `swagger` 目標串起「產生 → 轉換」。
3. `docs/` 只放 `openapi3.json` 與內嵌用的 `openapi3.go`。
4. 複製 `assets/docs-page.html` 進文件 handler，掛 `/docs/*any`（非正式環境），並登記到路由測試的公開端點清單。
5. 前端 / 行動端的型別產生直接讀 3.0 檔。

## 路徑 B：既有專案遷移（多數專案在這裡）

依序做，每步都可獨立驗證：

1. **加轉換**：放入 `cmd/openapi3/`，Makefile 的產生步驟輸出改到暫存目錄並只輸出 JSON，接著跑轉換。確認 `docs/openapi3.json` 產出、路徑數與 2.0 相同。
2. **移除 Swagger UI**：文件路由、UI 相關依賴（Go：`gin-swagger`、`swaggo/files`）、`main.go` 為了註冊規格加的空白 import、`docs.go` / `swagger.yaml`。產生器本身（swag）留著。
3. **前端改讀 3.0**：型別產生指令改路徑，重新產生後跑型別檢查。所有「必填但可 null」的錯誤回後端補「非必填」標記，重新產生直到乾淨。這一步順便修掉過去被 2.0 產生器寬鬆處理而藏起來的契約錯誤。
4. **補 tag 說明**：API 元資料加 `@tag.*`（Go 的 swag 必須寫在 `@securityDefinitions` 之前，否則整段被吃掉）。
5. **掛文件頁**：`assets/docs-page.html` 改標題、登入入口、tag 前綴後掛到 `/docs/*any`；路由測試的公開清單改登記 `/docs`。
6. **文件**：專案 CLAUDE.md 的文件網址與「契約正本」說明改掉；架構文件記一條決議，寫明選型比較與代價。

---

## 文件頁必備功能

| 功能 | 做法 |
|---|---|
| 左側分區 | 依 tag 前綴在頁面算出 `x-tagGroups`（後台 / 客戶端 / 共用），不寫進規格檔 |
| API 伺服器切換 | 自動偵測（目前網址）或自行輸入，存 localStorage；讓同一份文件能指向測試站或正式站 |
| 登入取得 token | 頁面第二列直接打登入端點，token 存 sessionStorage（關分頁即失效，不存密碼），自動帶進所有端點的試打與 curl 範例 |
| 下載規格 | 連結到 `/docs/openapi.json`，交接時直接給 |
| 安全 | 只在非正式環境註冊、Ask AI / MCP 關閉、資產內嵌 |

細節與 Scalar 設定項見 `references/docs-page.md`。

---

## 交接給其他開發者或 AI

給的是 **規格檔** 加 **一頁索引**，不是文件頁截圖。清單與 `llms.txt` 寫法見 `references/handover.md`。

---

## 參考資料索引

| 檔案 | 內容 | 何時讀 |
|---|---|---|
| `references/go-swag.md` | swag 註解規範（`@Param` / `@Success` / `example` / `validate:"optional"` / `x-nullable`）、Makefile 與轉換工具接法、文件 handler、路由測試、踩坑 | Go 專案新增或修改任何 handler 前**必讀** |
| `references/docs-page.md` | 文件頁的設計、Scalar 設定、模板要改的地方、安全考量、曾比較過的替代方案 | 掛文件頁或調整它時 |
| `references/handover.md` | 交接清單、`llms.txt` 範本、什麼時候才值得做 MCP | 要把 API 交給別人或 AI 時 |
| `assets/openapi3-convert.go` | Swagger 2.0 → OpenAPI 3.0 轉換工具（kin-openapi），含 `x-nullable` 處理 | 複製到 `cmd/openapi3/` |
| `assets/docs-page.html` | Scalar 文件頁模板（分區、伺服器切換、登入列） | 複製進文件 handler |
