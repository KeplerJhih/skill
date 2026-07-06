# Swagger/OpenAPI 註釋規範 (swaggo/swag)

本文件定義了本專案使用 `swaggo/swag` 撰寫 Swagger 註釋的完整規範。
當你在 `handler/` 中新增或修改端點時，**必須**遵循以下所有規則。

---

## 基礎設施前置檢查

首次接手專案或發現 Swagger 無法訪問時，確認以下項目：

- `go.mod` 包含 `github.com/swaggo/swag`、`github.com/swaggo/gin-swagger`、`github.com/swaggo/files`
- `cmd/server/main.go` 有 `_ "<module>/docs"` side-effect import（`<module>` 為該專案 go.mod 宣告的 module 名）與 API 元資料註釋（`@title`、`@version`、`@host`、`@BasePath`、`@securityDefinitions.apikey`）
- `router.go` 在**非 release 模式**下掛載 `r.GET("/swagger/*any", ginSwagger.WrapHandler(swaggerFiles.Handler))`

---

## Handler 註釋規範

每個 Handler 方法**必須**加上以下全部適用的註釋：

| 註釋 | 說明 | 必填 |
|------|------|------|
| `@Summary` | 一句話摘要（中文） | 必填 |
| `@Description` | 較詳細的說明（中文） | 必填 |
| `@Tags` | 分組標籤，格式 `Admin - 資源名` 或 `Customer - 資源名` | 必填 |
| `@Accept` | 請求格式（有 Body 時：`json` 或 `multipart/form-data`） | 有 Body 時必填 |
| `@Produce` | 回應格式（固定 `json`） | 必填 |
| `@Param` | **每個**路徑參數、查詢參數、請求體、表單欄位都必須各寫一行 | 有參數時必填 |
| `@Success` | 成功回應，**必須**指明 data 型別（見下方規範） | 必填 |
| `@Failure` | 所有可能的錯誤狀態碼（400/401/403/404/500） | 必填 |
| `@Security BearerAuth` | 需要認證的端點必須加上（公開端點如 Login/Register 不加） | 需認證時必填 |
| `@Router` | 路由路徑與 HTTP 方法 | 必填 |

---

## `@Param` 語法

格式：`@Param 參數名 位置 型別 是否必填 "中文描述"`

每個參數都**必須**填寫描述，不可留空。

- **位置 (location)**：`path`（路徑參數）、`query`（查詢參數）、`body`（請求體）、`formData`（表單/檔案上傳）
- **型別 (type)**：`integer`、`string`、`boolean`、`number`、`file`，body 時用 struct 型別

### 四種常見場景

```go
// Path 參數 — 路徑中的 :id
// @Param id path int true "用戶 ID"

// Query 參數 — ?role=admin
// @Param role query string false "角色篩選 (admin/customer)"
// @Param page query int false "頁碼，預設 1"
// @Param limit query int false "每頁筆數，預設 20"

// Body 參數 — JSON 請求體 (搭配 @Accept json)
// @Param request body service.CreateUserRequest true "建立用戶請求"

// FormData 參數 — 檔案上傳 (搭配 @Accept multipart/form-data)
// @Param file formData file true "要上傳的圖片檔案"
```

---

## `@Success` Response 型別規範

- 返回單一物件：`@Success 200 {object} response.Response{data=entity.Product}`
- 返回陣列：`@Success 200 {object} response.Response{data=[]entity.Product}`
- 返回自訂結構：`@Success 200 {object} response.Response{data=service.SomeResponse}`
- 返回 nil（Delete/操作類）：`@Success 200 {object} response.Response`
- **禁止**在有實際 data 回傳時只寫 `response.Response` 而省略 `{data=...}`

---

## Request Struct `example` Tag（必須）

Body 參數對應的 struct，**每個欄位都必須**加上 `example` tag，讓 Swagger UI 顯示有意義的範例值：

```go
type CreateUserRequest struct {
    Name     string `json:"name" binding:"required" example:"王小明"`
    Email    string `json:"email" binding:"required,email" example:"user@example.com"`
    Password string `json:"password" binding:"required,min=6" example:"Pass1234"`
    Role     string `json:"role" binding:"required,oneof=admin customer" example:"customer"`
}
```

---

## 完整 Handler 範例

新增端點時請參照以下三個範本（Create / GetByID / List）：

```go
// Create godoc
// @Summary 建立用戶
// @Description 建立新的系統用戶（管理員操作）
// @Tags Admin - Users
// @Accept json
// @Produce json
// @Param request body service.CreateUserRequest true "建立用戶請求"
// @Success 201 {object} response.Response{data=entity.User}
// @Failure 400 {object} response.Response
// @Security BearerAuth
// @Router /admin/users [post]
func (h *UserHandler) Create(c *gin.Context) { ... }

// GetByID godoc
// @Summary 取得單一用戶
// @Description 依 ID 取得用戶詳細資訊
// @Tags Admin - Users
// @Produce json
// @Param id path int true "用戶 ID"
// @Success 200 {object} response.Response{data=entity.User}
// @Failure 400 {object} response.Response
// @Failure 404 {object} response.Response
// @Security BearerAuth
// @Router /admin/users/{id} [get]
func (h *UserHandler) GetByID(c *gin.Context) { ... }

// List godoc
// @Summary 取得用戶列表
// @Description 取得所有用戶，支援角色篩選
// @Tags Admin - Users
// @Produce json
// @Param role query string false "角色篩選 (admin/customer)"
// @Success 200 {object} response.Response{data=[]entity.User}
// @Failure 500 {object} response.Response
// @Security BearerAuth
// @Router /admin/users [get]
func (h *UserHandler) List(c *gin.Context) { ... }
```

---

## 生成與驗證

- **生成指令**：`cd {BACKEND_DIR} && make swagger`（後端根目錄，預設 `backend/go`；修改 Handler 註釋或 Request struct 後必須重新執行）
- **訪問位址**：`http://localhost:<port>/swagger/index.html`（僅 debug 模式可用，port 依 config 設定）
