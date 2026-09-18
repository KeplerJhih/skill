# Go（swaggo/swag）：註解規範與 OpenAPI 3.0 產生流程

本文件定義 Go 後端以 `swaggo/swag` 撰寫 API 註解、並產出 OpenAPI 3.0 契約的完整規範。
在 `handler/` 新增或修改端點時，**必須**遵循以下所有規則。

---

## 基礎設施前置檢查

首次接手專案或發現文件頁無法訪問時，確認以下項目：

- `go.mod` 有 `github.com/swaggo/swag`（產生器）與 `github.com/getkin/kin-openapi`（轉換）；**不需要** `gin-swagger`、`swaggo/files`（那是 Swagger UI，已不用）。
- `cmd/server/main.go` 有 API 元資料註解（`@title`、`@version`、`@BasePath`、`@tag.*`、`@securityDefinitions.apikey`），**不需要** `_ "<module>/docs"` 空白 import。
- `cmd/openapi3/main.go` 存在（複製自本 skill 的 `assets/openapi3-convert.go`）。
- `docs/` 只有 `openapi3.json` 與 `openapi3.go`（內嵌用）。
- `router.go` 在**非 release 模式**下掛 `r.GET("/docs/*any", handler.APIDocs())`，且路由測試的公開端點清單登記了 `GET /docs/*any`。

看到 `docs/docs.go`、`swagger.yaml`、`/swagger/*any` 路由，就是還沒遷移，依 SKILL.md「路徑 B」處理。

---

## 產生流程

### Makefile

```makefile
swagger: ## 產生 API 規格（正本 docs/openapi3.json；swag 的 2.0 中間產物丟 tmp/，不進版控）
	go tool swag init -g cmd/server/main.go -o tmp/swagger --parseInternal --requiredByDefault --outputTypes json
	go run ./cmd/openapi3
```

- `--outputTypes json`：只產 `swagger.json`，不產 `docs.go` / `swagger.yaml`。
- `-o tmp/swagger`：中間產物放 gitignored 的 `tmp/`（`.gitignore` 用 `/tmp/` 錨定根目錄，避免誤排除同名套件）。air 的 `exclude_dir` 也要含 `tmp`。
- `--requiredByDefault`：欄位預設必填，可省略的要明確標（見下方）。
- swag 以 Go tool directive 釘版本（`go tool swag`）；沒有的專案用 `go run github.com/swaggo/swag/cmd/swag@<版本>`。

### 轉換工具 `cmd/openapi3/main.go`

複製 `assets/openapi3-convert.go`。它做三件事：讀 `tmp/swagger/swagger.json` → `openapi2conv.ToV3` → 走訪所有 schema 把 `x-nullable: true` 轉成 `nullable: true` 並移除擴充 → 寫 `docs/openapi3.json`（4 空白縮排、結尾換行，diff 乾淨）。

### 內嵌檔 `docs/openapi3.go`

```go
package docs

import _ "embed"

// OpenAPI3 是 make swagger 產出的 OpenAPI 3.0 規格，內嵌進執行檔，執行期不讀檔案。
//
//go:embed openapi3.json
var OpenAPI3 []byte
```

swag 不會動這個檔（它只寫自己的輸出目錄）。

### 文件 handler 與路由

```go
// handler/apidocs.go
//go:embed apidocs/scalar.standalone.js
var scalarAsset embed.FS

const apiDocsPage = `...`   // 複製 assets/docs-page.html 的內容

func APIDocs() gin.HandlerFunc {
	js, err := scalarAsset.ReadFile("apidocs/scalar.standalone.js")
	if err != nil { panic(err) }
	return func(c *gin.Context) {
		switch c.Param("any") {
		case "", "/":
			c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(apiDocsPage))
		case "/openapi.json":
			c.Data(http.StatusOK, "application/json; charset=utf-8", docs.OpenAPI3)
		case "/scalar.standalone.js":
			c.Data(http.StatusOK, "application/javascript; charset=utf-8", js)
		default:
			c.Status(http.StatusNotFound)
		}
	}
}
```

```go
// router.go
if gin.Mode() != gin.ReleaseMode {
	r.GET("/docs/*any", handler.APIDocs())   // 文件頁與規格檔；正式環境不註冊
}
```

Scalar 資產：`curl -L -o internal/interfaces/api/handler/apidocs/scalar.standalone.js https://cdn.jsdelivr.net/npm/@scalar/api-reference@<版本>/dist/browser/standalone.js`（約 3.7MB，MIT），版本與更新指令寫在 handler 註解。

### 路由測試

專案若有「每個端點都要登入」的路由測試（建議要有），公開清單只登記：

```go
var publicRoutes = map[string]string{
	"POST /admin/auth/login": "後台登入",
	"POST /api/auth/login":   "前台登入",
	"GET /health":            "健康檢查",
	"GET /docs/*any":         "API 文件與規格檔，只在 GIN_MODE 非 release 時註冊",
}
```

---

## API 元資料註解（`cmd/server/main.go`）

```go
// @title <系統名稱> API
// @version 1.0
// @description 後台 API 在 /admin（admin 角色），客戶端 API 在 /api（customer 角色）。金額為字串、日期為 YYYY-MM-DD。
// @BasePath /
//
// tag 說明會顯示在文件頁的左側分類；新增 tag 時記得補一組。
// @tag.name Admin - Orders
// @tag.description 訂單、品項、費用與附件
// @tag.name Customer - Orders
// @tag.description 客戶自己的訂單；不含供應商與成本
// @tag.name Auth
// @tag.description 登入狀態，兩個入口共用
//
// @securityDefinitions.apikey BearerAuth
// @in header
// @name Authorization
// @description 格式：Bearer {token}
package main
```

**`@tag.*` 一定要寫在 `@securityDefinitions` 之前**：swag 會把安全定義之後的行都當成它的內容，`tags` 整段消失、文件頁左側就沒有說明。

---

## Handler 註解規範

每個 Handler 方法**必須**加上以下全部適用的註解：

| 註解 | 說明 | 必填 |
|------|------|------|
| `@Summary` | 一句話摘要（中文） | 必填 |
| `@Description` | 較詳細的說明（中文）；可多行 | 必填 |
| `@Tags` | `<入口> - <資源>`，例如 `Admin - Orders`、`Customer - Orders`；兩個入口共用的端點用不帶前綴的名稱（例如 `Auth`） | 必填 |
| `@Accept` | 請求格式（有 Body 時：`json` 或 `multipart/form-data`） | 有 Body 時必填 |
| `@Produce` | 回應格式（`json`；SSE 端點為 `text/event-stream`） | 必填 |
| `@Param` | **每個**路徑參數、查詢參數、請求體、表單欄位都必須各寫一行 | 有參數時必填 |
| `@Success` | 成功回應，**必須**指明 data 型別（見下方） | 必填 |
| `@Failure` | 所有可能的錯誤狀態碼（400/401/403/404/409/429/500…） | 必填 |
| `@Security BearerAuth` | 需要認證的端點必須加上（登入等公開端點不加） | 需認證時必填 |
| `@Router` | 路由路徑與方法，寫完整前綴（`@BasePath /`）；同一 handler 掛在兩個入口就寫兩行 | 必填 |

---

## `@Param` 語法

格式：`@Param 參數名 位置 型別 是否必填 "中文描述"`；每個參數都**必須**填描述。

- **位置**：`path`、`query`、`body`、`formData`
- **型別**：`integer`、`string`、`boolean`、`number`、`file`；body 用 struct 型別
- 列舉值加 `Enums(a, b)`

```go
// @Param id path int true "訂單 ID"
// @Param status query string false "狀態篩選" Enums(draft, done)
// @Param page query int false "頁碼，預設 1"
// @Param request body service.CreateOrderRequest true "建立訂單"
// @Param file formData file true "要上傳的圖片"
// @Param mode formData string false "模式" Enums(default, custom)
```

---

## `@Success` Response 型別規範

- 單一物件：`@Success 200 {object} response.Response{data=service.OrderDTO}`
- 陣列：`@Success 200 {object} response.Response{data=[]service.OrderDTO}`
- 無 data（刪除、操作類）：`@Success 200 {object} response.Response`
- 串流（SSE）：`@Success 200 {object} service.DoneEventDTO "done 事件的內容"`，並在 `@Description` 說明事件種類
- **禁止**有 data 卻只寫 `response.Response`

---

## DTO 標籤：3.0 會照實產生型別

swag 以 `--requiredByDefault` 產生，OpenAPI 3.0 的型別產生器（swagger-typescript-api 等）依 `required` 與 `nullable` 決定 `field?: T` / `field: T | null`。Swagger 2.0 時代的產生器會把 `x-nullable` 欄位一律當選填，掩蓋了標記錯誤；改讀 3.0 後這些錯誤會浮現。標籤規則：

| 情況 | 標籤 | 3.0 產出 |
|---|---|---|
| 必填 | `binding:"required"` | `field: T` |
| 請求可省略（後端有預設或視同 null） | `validate:"optional"` | `field?: T` |
| 回應或請求可為 null（指標、`NullDecimal`、`sql.Null*`） | `extensions:"x-nullable"` → 轉換後 `nullable: true` | `field: T \| null` |
| 可省略且可為 null | 兩個都加 | `field?: T \| null` |
| `decimal` 等自訂型別 | `swaggertype:"string"`（金額一律字串） | `string` |
| 具名字串型別被誤產成列舉 | `swaggertype:"string"` | `string` |

前端型別檢查噴出「缺少屬性」時，回後端補 `validate:"optional"`，不要在前端塞 `null`。

### Request struct `example` tag（必須）

每個欄位都加 `example`，文件頁的範例請求才有意義：

```go
type CreateOrderRequest struct {
	CustomerID int64   `json:"customer_id" binding:"required" example:"2"`
	Note       *string `json:"note" example:"電話訂購" extensions:"x-nullable" validate:"optional"`
}
```

---

## 完整 Handler 範例

```go
// Create godoc
// @Summary 建立訂單
// @Description 管理員代客戶建立訂單
// @Tags Admin - Orders
// @Accept json
// @Produce json
// @Param request body service.CreateOrderRequest true "建立訂單"
// @Success 201 {object} response.Response{data=service.OrderDTO}
// @Failure 400 {object} response.Response
// @Failure 401 {object} response.Response
// @Failure 403 {object} response.Response
// @Security BearerAuth
// @Router /admin/orders [post]
func (h *OrderHandler) Create(c *gin.Context) { ... }

// Get godoc
// @Summary 訂單明細
// @Tags Admin - Orders
// @Produce json
// @Param id path int true "訂單 ID"
// @Success 200 {object} response.Response{data=service.OrderDTO}
// @Failure 404 {object} response.Response
// @Security BearerAuth
// @Router /admin/orders/{id} [get]
func (h *OrderHandler) Get(c *gin.Context) { ... }

// Me godoc — 同一 handler 掛兩個入口
// @Summary 取得目前登入者
// @Tags Auth
// @Produce json
// @Success 200 {object} response.Response{data=service.UserDTO}
// @Security BearerAuth
// @Router /admin/auth/me [get]
// @Router /api/auth/me [get]
func (h *AuthHandler) Me(c *gin.Context) { ... }
```

---

## 生成與驗證

- **生成**：`cd {BACKEND_DIR} && make swagger`（修改註解或 DTO 後必跑，之後前端 / 行動端重新產型別）。
- **檢查產物**：`docs/openapi3.json` 的 `openapi` 為 `3.0.x`，`tags` 數量等於 `@tag.name` 數量，`components.securitySchemes` 有 `BearerAuth`。
- **文件頁**：`http://localhost:<port>/docs/`（非 release）；規格 `http://localhost:<port>/docs/openapi.json`。
- **執行中的服務讀的是編進執行檔的規格**：`make swagger` 之後要重新編譯（air 會自動）才看得到新內容；正式環境在 build 時定案。

---

## 踩坑

- **`@tag.*` 放在 `@securityDefinitions` 後面**：整段被吃掉，`tags` 消失，沒有任何錯誤訊息。
- **swag v2 仍是 rc**：先不用；穩定後可改 `swag init --v3.1` 原生產 3.1，Makefile 拿掉轉換步驟即可，註解不用動。
- **2.0 → 3.0 後前端型別變嚴格**：是修契約的機會，不是回退的理由。
- **`.gitignore` 的 `tmp/` 要寫成 `/tmp/`**：否則 `internal/.../tmp` 之類的套件也會被排除。
- **文件頁只在非 release 註冊，且要進路由測試的公開清單**：漏登記會被「每個端點都要登入」的測試擋下；反過來，正式環境不該有文件頁。
