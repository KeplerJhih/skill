# 瀏覽器自動化的坑（Chrome DevTools MCP / Claude in Chrome 通用）

## 版面與寬度

- **視窗全螢幕時 resize 無效**：`resize_window` / `resize_page` 可能回成功但 `innerWidth` 不變。要驗手機寬度，改在頁面裡插一個同網域、寬 390px 的 iframe 載入同一頁，量它的 `document.documentElement.scrollWidth` 與各元素 `getBoundingClientRect().right` 是否超出 `innerWidth`。
- **只看截圖判斷跑版不夠**：用腳本列出超出視窗右緣的元素（排除 `table` 內的），零筆才算過。

## 輸入與焦點

- **打字前先確認焦點在輸入框**：焦點停在按鈕上時，`type` 的字串裡有空白會觸發那個按鈕（例如誤切模式）。先 `left_click` 輸入框或用 `document.activeElement` 確認。
- **元件在下一個 microtask 才把值傳回父層**（shadcn / reka 類 Input）：用腳本注入值後要 `await` 讓出事件迴圈再送出，否則送的是舊值。真人操作不受影響。
- **自訂下拉用 ref 點不開**：改用座標點擊；或直接呼叫元件的 change 事件。
- **不要用 `focus` 旗標判斷「還在輸入框」**：視窗沒焦點時 `focus()` 不觸發事件，一律看 `document.activeElement`。

## 截圖與時機

- **頁面重繪中截圖會拿到白畫面或重複拼貼**：大型元件（文件頁、圖表）掛載後等 2–4 秒，或以 DOM 查詢佐證再截圖。
- **截圖不是驗證**：能用 `innerText` / `querySelector` 斷言的就用腳本；截圖只用來給人看。

## 工具限制

- **回傳給工具的物件 key 不要叫 `auth`、`token`、`password`**：工具會把值遮蔽成 `[BLOCKED: Sensitive key]`。改叫 `status`、`sample` 之類。
- **不能開 `file://`**：本機檔案用 `python3 -m http.server <埠> --bind 127.0.0.1` 供應，用完結束程序。
- **上傳只接受本工作階段可讀的檔案**：把測試檔放進專案被 git 忽略、開發伺服器會提供的目錄，在頁面內 `fetch` 後以 `DataTransfer` 塞進 `<input type="file">` 並觸發 `change`。
- **console 追蹤從第一次呼叫才開始**：要抓載入期的錯誤，先呼叫一次 console 工具再重新整理。
- **分頁用完關掉**：每次任務開自己的分頁，不重用先前工作階段的 tabId。

## 資料

- **同一張圖片會命中快取**：驗證「重新處理」的流程時，在檔案結尾加幾個隨機位元組讓雜湊不同（JPEG 結尾後的資料不影響解碼）。
- **附件回應可能有私人快取**（`Cache-Control: private`）：資料庫重置後同一瀏覽器可能顯示舊圖，用 `cache: 'reload'` 重抓或清快取。
