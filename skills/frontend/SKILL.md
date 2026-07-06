---
name: frontend
version: 1.0.0
description: 構建可擴展、高效能且可維護的 React/TypeScript 前端應用程式指南。特別強調 RWD 回應式設計、佈局穩定性與多端操作體驗。
color: green
---

此技能專注於 React 前端工程 (Frontend Engineering) 核心原則，確保 React 應用程式在各類裝置（手機、平板、桌面）上的品質、效能與一致性。適用於任何專案；下述目錄路徑為**預設慣例**，若專案 CLAUDE.md 另有宣告則以專案為準。

## 🛠️ 專案技術堆疊

- **React 19** + TypeScript 5.9
- **Vite 7** (開發伺服器 port 5173)
- **React Router 7** (前端路由)
- **Tailwind CSS 4** (樣式)
- **MUI (Material UI) v6** (UI 元件庫)
- **Axios** (HTTP 客戶端)
- **Lucide React** (圖示庫)

## 📂 目錄結構

預設慣例路徑為 `frontend/main/`（專案 CLAUDE.md 可覆蓋）：

```text
frontend/main/src/
  pages/          # 頁面級元件 (auth, admin, customer, account)
  components/
    ui/           # 原子級 UI 元件 (Buttons, Inputs, Badges)
    layout/       # 佈局元件 (Nav, Sidebar, Footer, AdminLayout)
  api/            # Axios API 封裝與請求定義
  types/          # TypeScript 全域型別 (index.ts)
  contexts/       # React Context 狀態管理
  styles/         # 全域樣式與 Tailwind 配置
🧠 核心原則
型別安全 (Type Safety)：全面使用 TypeScript，所有 Props 與 API 回應皆需定義型別。
關注點分離 (SoC)：UI 歸 UI，邏輯歸 Hooks，數據歸 API 層。
回應式優先 (RWD & Mobile First)：開發時預設考慮行動端版面，再透過 Tailwind 斷點 (md:, lg:) 擴充至桌面端。
佈局穩定性：嚴禁出現非預期的橫向捲軸 (overflow-x)，確保元件在容器縮放時不重疊、不破裂。
效能至上：合理使用 useMemo 與 React.memo，避免不必要的重渲染。

💡 最佳實踐
1. 元件與 RWD 設計
流暢佈局：優先使用 Flexbox 與 Grid。避免寫死固定寬度 (如 width: 800px)，改用 max-w-* 或百分比。
斷點一致性：統一使用 Tailwind 內建斷點，確保全站縮放行為一致。
防止跑版：
長文字區塊務必加上 break-words 或 truncate。
圖片使用 aspect-ratio 預留空間，避免載入後的佈局抖動 (CLS)。

2. 交互與操作體驗
觸控友善：行動端按鈕與連結的點擊範圍 (Hit Target) 至少需為 44x44px。
輸入優化：表單欄位在行動端應有足夠間距，避免放大縮小造成的視覺混亂。
視覺回饋：所有點擊操作應有 active 或 hover 狀態（行動端注意 hover 可能失效）。

3. API 與狀態管理
Server State：API 集中在 src/api/，並統一處理 Loading 與 Error 狀態。
URL State：分頁、過濾條件應優先儲存於 URL Query Params。

4. 網路請求與資源 URL 規範
API 請求：統一透過 `src/api/client.ts` 的 Axios 實例發送，嚴禁在元件中硬編碼後端域名或 Port。
靜態資源 URL（如上傳圖片等後端回傳的相對路徑）：一律直接使用，嚴禁拼接 `http://localhost:XXXX`。
開發環境：所有需代理到後端的路徑，統一在 `vite.config.ts` 的 `proxy` 中配置，Port 只需設定一處。
生產環境：前後端同域名部署，相對路徑自動生效。
禁止事項：不可在元件中使用 `import.meta.env.VITE_API_BASE` 或任何硬編碼的 `localhost:PORT` 拼接 URL。

📝 開發指令
```Bash
make dev      # 啟動開發伺服器
make build    # 編譯正式版本
make lint     # 執行程式碼檢查
make install  # 安裝依賴
```

✅ 完成需求後的必要步驟 (DoD)
在提交前端變更前，Tech Lead 必須確認以下項目：
1. 代碼質量：
在前端目錄（預設 frontend/main）執行 make lint 且無錯誤。
無未使用的變數或 any 型別。
2. RWD 跑版檢查 (必做)：
[ ] 斷點過渡：手動縮放視窗，確認從 375px 到 1920px 內容無重疊。
[ ] 橫向捲軸：確認行動版模式下無非預期的水平溢出。
[ ] 互動測試：確認選單 (Drawer) 與彈窗 (Modal) 在手機上能正常開關且不遮擋關鍵操作。
[ ] 符合操作：輸入框、按鈕等在行動端是否容易點選，無跑位問題。

效能確認：
圖片與資源是否已做基本的延遲載入或大小優化。
注意：請時刻記住，我們不只在寫代碼，我們在打造跨裝置的一致體驗。