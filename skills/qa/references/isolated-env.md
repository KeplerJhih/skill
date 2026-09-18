# 隔離的 QA 環境：不碰使用者正在用的服務與資料

適用：要做端到端驗證，但使用者的開發伺服器正在跑、資料庫裡有真實資料，而且功能會呼叫外部服務（AI、金流、簡訊、第三方 API）。

## 原則

1. **不停使用者的服務**：不殺 air / vite / 其他專案的程序；另起自己的實例用別的埠。
2. **不用使用者的密鑰**：QA 實例用自己產生的 JWT 密鑰與加密金鑰，權杖自己鑄，不需要真實密碼。
3. **不打真實的外部服務**：一律換成假服務，並在假服務裡放驗證點。
4. **資料庫只增不改，結束後只刪自己建的**：先快照，測完只刪 QA 列，設定還原到一模一樣，最後比對快照。
5. **檔案與設定放暫存**：QA 用的 vite 設定、日誌、測試檔都放 git 忽略的目錄（專案的 `tmp/` 或 session 暫存區）。

## 步驟

### 1. 另起後端

```bash
go build -o <暫存>/qa-server ./cmd/server   # 或該語言的建置方式
SERVER_HOST=127.0.0.1 SERVER_PORT=<QA埠> JWT_SECRET=$(openssl rand -hex 24) \
ENCRYPTION_KEY=$(openssl rand -hex 32) STORAGE_DIR=<暫存>/qa-storage <暫存>/qa-server
```

- 連同一個開發資料庫（要驗證真實 schema），但上傳目錄、日誌都指到暫存。
- 不讀專案的 `.env`（那是禁區）；需要的值全部用行內環境變數帶。

### 2. 自鑄權杖

依專案的 JWT 格式（演算法、claims 欄位）用 QA 密鑰簽一個給測試用的使用者 id 與角色；瀏覽器測試時把它寫進前端存權杖的 localStorage 鍵，直接跳過登入頁。

```python
# HS256 範例：header.payload.signature，base64url 去掉 =
payload = {"uid": <id>, "role": "<role>", "jti": <uuid>, "iat": now, "exp": now + 3600}
```

### 3. 假外部服務

- 用 Python `http.server` 之類幾十行就能起一個，監聽 127.0.0.1 的另一個埠；QA 實例的設定指向它。
- 依金鑰或路徑區分要模擬的服務商行為（例如 A 家要求嚴格 JSON schema、B 家回 Markdown 包 JSON）。
- **放驗證點**：把收到的請求重點寫進日誌（模型、格式、系統提示是否含某個標記字），測試腳本讀日誌斷言。這是唯一能證明「設定真的送出去了」的方法。
- 用輸入特徵模擬各種結果（例如很小的圖片回空結果、特定大小回 503），一個假服務就能跑完成功 / 空 / 失敗三條路。

### 4. 前端另起 Vite

不要改專案的 `vite.config.ts`。在 git 忽略的目錄放一個覆寫檔：

```ts
// tmp/vite.qa.config.ts
import { mergeConfig } from 'vite'
import base from '../vite.config'
export default mergeConfig(base, { server: { port: <QA埠>, proxy: { '/api': 'http://127.0.0.1:<QA後端埠>' } } })
```

`npx vite --config tmp/vite.qa.config.ts --strictPort`。

### 5. 資料庫快照與還原

測試前：

```sql
-- 會被測試改到的設定列：整列記下
select * from <settings_table> where ...;
-- 各表最大 id：之後大於它的就是 QA 建的
select (select max(id) from orders), (select max(id) from attachments), ...;
```

測試後，在單一交易內：

1. 依外鍵順序刪 QA 建的列：先子表（依 QA 專屬的欄位值或 id 範圍），再父表。
2. 設定列 `UPDATE` 回快照的值（含 `updated_at`、`updated_by`）。
3. 重跑快照查詢，逐欄比對一致才 `COMMIT`。

刪除條件要「雙重」：id 大於快照 **且** 帶 QA 特徵（QA 建的服務商 id、備註含 QA 字樣），避免使用者在測試期間新增的真實資料被誤刪。

### 6. 收尾

- 依埠號找 QA 程序（`lsof -nP -tiTCP:<埠> -sTCP:LISTEN`）逐一結束，確認使用者的埠都還在。
- 刪暫存目錄裡的上傳檔、日誌。
- 回報時附：快照 vs 還原後的比對結果、刪了哪些列。

## 常見錯誤

- 用真實帳號登入 QA 實例：密碼會出現在對話或截圖裡。用自鑄權杖。
- 假服務沒放驗證點：只看到「成功」，不知道送出去的內容對不對。
- 只依 id 範圍刪除：使用者同時在用系統時會誤刪。
- 忘了還原 `updated_at`：快照比對會過不了，也會讓「最近修改」顯示錯誤。
