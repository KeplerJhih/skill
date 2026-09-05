# App Store 送審前置清單 & App Store Connect API 實戰

適用：任何 iOS 專案第一次（或久違）送審。目標是**一次過 `reviewSubmissionItems`**，不要靠網頁紅字慢慢猜。
資料面用 `appstore-connect` MCP（`api.request`）；二進位素材與錯誤明細走 curl（原因見末段）。

## 一、專案端（archive 前）

| 項目 | 怎麼確認 | 缺了會怎樣 |
|---|---|---|
| `PrivacyInfo.xcprivacy` | 有用 `UserDefaults` → `NSPrivacyAccessedAPICategoryUserDefaults` 理由 `CA92.1`；無追蹤 `NSPrivacyTracking=false`；無蒐集 `NSPrivacyCollectedDataTypes=[]` | 上傳後收 ITMS-91053 信、審核可能退 |
| 出口合規 | `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` | 每個 build 都要在網頁回答加密問題 |
| 裝置家族 | 沒驗過 iPad 版面就 `TARGETED_DEVICE_FAMILY = 1`（iPhone-only） | 1,2 會**強制要 iPad 13" 截圖** |
| 方向 | 直向設計的 App 把 `UISupportedInterfaceOrientations_iPhone` 收成 Portrait | 橫向破版被審到 |
| build 號 | `CURRENT_PROJECT_VERSION` 手動遞增（`manageAppVersionAndBuildNumber=false`） | 同號上傳被拒 |
| App 圖示 | 1024 無 alpha、未預切圓角；主體佔 ~78%（用 `-trim` 取 bbox 置中裁切） | 圖示偏小／偏移 |
| 開發用環境變數鉤子 | `ProcessInfo.environment["…"]` 類保留無妨，release 不會被觸發 | — |
| IAP 與付費牆 | 付費牆關著就**不要把 IAP 加進送審單**（審核員找不到購買入口 → IAP 退件、版本可能一起卡） | 見下 |

**Archive／上傳**：
```
xcodebuild -scheme <S> -configuration Release -destination 'generic/platform=iOS' -archivePath X.xcarchive archive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath X.xcarchive -exportOptionsPlist Export.plist -exportPath out -allowProvisioningUpdates
```
`Export.plist`：`method=app-store-connect`、`destination=upload`、`signingStyle=automatic`、`teamID`、`manageAppVersionAndBuildNumber=false`。先帶 `-authenticationKey*` 三參數跑一次，成功即可全自動、不依賴 Xcode 登入；失敗訊息含 `Cloud signing permission error` 代表該金鑰能力不足，再退回 Xcode 登入帳號（帳號 session 過期會報 `Failed to Use Accounts`）。金鑰能不能簽章以實跑結果為準，不以角色名稱判斷。上傳後 3–10 分鐘 `GET /v1/builds?filter[app]=…&sort=-uploadedDate` 出現 `VALID` 才能綁：`PATCH /v1/appStoreVersions/{v}/relationships/build`。

## 二、ASC 資料面（MCP 可做）

| 項目 | API |
|---|---|
| 分類 | `PATCH /v1/appInfos/{id}` relationships `primaryCategory`/`secondaryCategory`（id 如 `FINANCE`、`PRODUCTIVITY`） |
| 內容版權聲明 | `PATCH /v1/apps/{id}` `contentRightsDeclaration`（有第三方品牌 logo → `USES_THIRD_PARTY_CONTENT`） |
| 年齡分級 | id 取 `GET /v1/appInfos/{id}/ageRatingDeclaration`（**不要**靠 include）→ `PATCH /v1/ageRatingDeclarations/{id}` 全 `NONE`/`false` |
| 價格（免費也要建） | `GET /v1/apps/{id}/appPricePoints?filter[territory]=TWN` 找 `customerPrice=0` → `POST /v1/appPriceSchedules`（baseTerritory + manualPrices included） |
| 上架地區 | `GET /v1/territories?limit=200` → `POST /v2/appAvailabilities`（`availableInNewTerritories=true` + 全部 territoryAvailabilities included） |
| 版本文案 | `PATCH /v1/appStoreVersionLocalizations/{id}`：`description`、`keywords`（≤100 字元）、`promotionalText`、`supportUrl` |
| 隱私政策網址 | `PATCH /v1/appInfoLocalizations/{id}` `privacyPolicyUrl`（**每個語系都要**） |
| 版權 | `PATCH /v1/appStoreVersions/{id}` `copyright`（沿用同帳號其他 App 格式，例 `© 2026 <Name>`） |
| 審核聯絡人／備註 | `POST /v1/appStoreReviewDetails`（appStoreVersion）→ `PATCH` contactFirst/LastName、Phone（含國碼）、Email、`notes`（英文條列：無帳號／資料本機／網路用途／如何載測試資料／本版有無 IAP） |
| 商店名 vs 桌面名 | ASC `appInfoLocalization.name`（可含副標式後綴，如「X-訂閱管理」）與 `CFBundleDisplayName` 是兩個欄位 |

**API 做不到、本人必做**：**App 隱私標籤**（App 隱私 → 回答 → **按「發布」**）。只存草稿不發布 = 送審 409 `APP_DATA_USAGES_REQUIRED`；舊的 `appDataUsages` 端點已下線。

## 三、截圖（無 fastlane 也行）

1. 6.9" 模擬器（iPhone 1x Pro Max，1320×2868）；載測試資料後用 `idb ui tap --udid … x y` 腳本連拍；其他語系用 `xcrun simctl launch <udid> <bundle> -AppleLanguages "(en)"` 重啟再拍（App 讀 `Locale.preferredLanguages` 才會跟）。
2. `POST /v1/appScreenshotSets`（`screenshotDisplayType=APP_IPHONE_67`，6.9" 也收）→ 每張 `POST /v1/appScreenshots`（fileName/fileSize）拿 `uploadOperations`。
3. **MCP 打不到 object-storage 主機** → Bash：`curl -X PUT -H 'Content-Type: image/png' --data-binary @f "<url>"`（預簽 URL 免 JWT）。
4. `PATCH /v1/appScreenshots/{id}` `{uploaded:true, sourceFileChecksum:<md5>}` → 等 `assetDeliveryState.state=COMPLETE`。

## 四、送審三步

```
POST  /v1/reviewSubmissions        { platform: IOS, relationships.app }
POST  /v1/reviewSubmissionItems    { relationships.reviewSubmission, appStoreVersion }   ← 這一步會把所有缺項一次擋下
PATCH /v1/reviewSubmissions/{id}   { submitted: true }                                   ← 送出前停下給使用者確認
```

## 五、MCP 看不到 409/422 明細時：自簽 JWT 直打

`appstore-connect` MCP 的錯誤物件只留 title，`meta.associatedErrors`（真正缺項）被吞掉。從 `.mcp.json` 的 `APP_STORE_KEY_ID`／`APP_STORE_ISSUER_ID`／`APP_STORE_P8_PATH` 自簽：

```bash
b64(){ openssl base64 -e -A | tr '+/' '-_' | tr -d '='; }
NOW=$(date +%s)
H=$(printf '{"alg":"ES256","kid":"%s","typ":"JWT"}' "$KID" | b64)
P=$(printf '{"iss":"%s","iat":%d,"exp":%d,"aud":"appstoreconnect-v1"}' "$ISS" "$NOW" $((NOW+1200)) | b64)
SIG=$(printf '%s.%s' "$H" "$P" | openssl dgst -sha256 -sign "$KEY" -binary | python3 -c '
import sys,base64
d=sys.stdin.buffer.read(); i=2
def rd():
    global i
    l=d[i+1]; v=d[i+2:i+2+l]; i+=2+l; return v.lstrip(b"\x00").rjust(32,b"\x00")
r=rd(); s=rd(); print(base64.urlsafe_b64encode(r+s).decode().rstrip("="))')
JWT="$H.$P.$SIG"
curl -s -X POST https://api.appstoreconnect.apple.com/v1/reviewSubmissionItems -H "Authorization: Bearer $JWT" -H 'Content-Type: application/json' -d '…' | python3 -m json.tool
```
（DER→raw r‖s 的 python 是必要的，openssl 輸出的是 DER，JWT 要 64 bytes raw。）
