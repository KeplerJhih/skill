# 文件頁（Scalar）設計與設定

`assets/docs-page.html` 是可直接複製的文件頁。它是一個純 HTML + 原生 JS 的頁面，載入內嵌的 Scalar 單檔版本，讀 `/docs/openapi.json`，加上兩列自製工具。

## 頁面結構

```
┌ 第一列：API 伺服器 [自動偵測 ▾] [自行輸入 …] [套用]  目前：https://…   下載 OpenAPI 3.0 規格 ┐
├ 第二列：登入 [後台 ▾] [帳號] [密碼] [取得 token] [登出]  已登入：王小明（admin）           ┤
└ Scalar：左側分區（後台 / 客戶端 / 共用）＋ ⌘K 搜尋 │ 右側端點、範例、Test Request        ┘
```

## 模板要改的地方

檔案最上方 `<script>` 的 `CONFIG` 區塊，全部集中在這裡：

| 欄位 | 說明 |
|---|---|
| `title` | 頁面標題（`<title>` 也一起改） |
| `specUrl` | 規格檔路徑，慣例 `/docs/openapi.json` |
| `portals` | 登入入口清單：`{ label, path }`，path 為登入端點；回應須為 `{ data: { token, user } }`，不同格式改 `extractToken` |
| `groups` | 左側分區：`{ name, prefix }` 依 tag 前綴比對，最後一組 `prefix: ''` 收剩下的 |
| `securityScheme` | 規格裡的安全機制名稱（swag 預設 `BearerAuth`），登入後 token 灌進這個 scheme |

其他都不用改。

## Scalar 設定項（模板已設）

```js
Scalar.createApiReference('#app', {
  content: spec,                 // 傳物件而非 url，才能先改 servers / x-tagGroups / 帶 token
  agent: { disabled: true },     // Ask AI：第一次提問會把規格上傳到 Scalar，關閉
  mcp: { disabled: true },       // MCP 連結：需要外部 MCP server，關閉
  hideModels: true,              // 左側不列 schema 清單，只留端點
  documentDownloadType: 'json',
  layout: 'modern',
  theme: 'default',
  authentication: {              // 登入後才帶
    preferredSecurityScheme: 'BearerAuth',
    securitySchemes: { BearerAuth: { name: 'Authorization', in: 'header', value: 'Bearer ' + token } }
  }
})
```

- 規格是 3.0 時伺服器切換改的是 `spec.servers = [{ url }]`；2.0 時改 `schemes` / `host` / `basePath`。模板處理 3.0。
- `x-tagGroups` 是 Redoc / Scalar 都支援的擴充，模板在頁面上算出來，不寫進規格檔，這樣規格檔給別的工具用時不帶頁面專屬的東西。
- 免費版左下角的 "Powered by Scalar" 拿不掉。

## 安全考量

- **只在非正式環境註冊**：文件頁會暴露完整端點結構，且登入列會碰帳密。正式環境不該有。
- **token 存 sessionStorage**：關分頁即失效；不用 Scalar 的 `persistAuth`（那是 localStorage）。密碼送出後立即清空欄位，不存。
- **伺服器切換存 localStorage**：只是網址，無敏感資料。指到其他網域時，登入與試打會受對方 CORS 影響，頁面有提示。
- **資產內嵌**：不連 CDN，離線可用、內容可控；更新版本時改 curl 指令的版本號並記在 handler 註解。
- **公開清單**：路由測試把 `/docs/*any` 登記為公開端點並註明只在非 release 註冊，避免有人之後在 release 也掛上。

## 曾比較過的替代方案（供日後重評）

| 方案 | 授權 / 體積 | 左側 | 試打 | 結論 |
|---|---|---|---|---|
| Swagger UI（swaggo 附） | Apache-2.0，隨套件 | 無分類 | 有 | 難讀，移除 |
| Redoc | MIT，1MB | tag 分組 | **無** | 純閱讀可用，但要兩個頁面 |
| RapiDoc | MIT，0.8MB | 篩選欄 + 端點摘要 | 有 | 功能夠，外觀樸素；體積敏感時的備案 |
| Stoplight Elements | Apache-2.0，約 2MB + CSS | tag 分組 | 有 | 未實測 |
| **Scalar** | MIT，3.7MB | tag 分組 + ⌘K | 有，多語言範例 | 採用 |

離線單檔需求（對方連不到你的環境）：`npx @redocly/cli build-docs docs/openapi3.json -o api.html` 可產一份把規格與 Redoc 打包在一起的 HTML（唯讀）。
