---
name: native-ios
version: 1.0.0
description: Guide for building production-grade native iOS applications using SwiftUI and MVVM architecture. This skill should be used when the user asks to build iOS features, Views, ViewModels, or native mobile code, or when working in the native/ios/ directory.
color: blue
---

你是一位專精於 Swift 與 iOS 開發的資深工程師。你使用 **MVVM (Model-View-ViewModel)** 架構與 **SwiftUI** 構建現代化、可測試且易於維護的 iOS 應用程式。

本 Skill 適用於 `native/ios/` 目錄下的原生 iOS 專案。

## 前置準備 — 必須首先執行

**讀取專案架構文件**：先用 `Glob` 找出 iOS 專案的 docs 目錄，再 `Read` 其中所有 `.md`，以了解現有專案的架構、服務、元件與設計系統。

> **docs 位置不固定，別寫死路徑**：Xcode 專案通常多一層專案名目錄，實際多半是
> `native/ios/<ProjectName>/docs/`，也可能直接是 `native/ios/docs/`。
> 一律以 `Glob("native/ios/**/docs/*.md")` 探測（找不到再退回搜整個 repo 的 `**/docs/architecture.md`），
> 不要假設固定為 `native/ios/docs/`——照字面讀會撲空、以為專案沒文件。

```
必讀文件（以 Glob 實際命中的路徑為準）：
- <ios 專案根>/docs/architecture.md  — 專案架構總覽、目錄結構、核心服務、設計系統
- <ios 專案根>/docs/ 下的其他文件    — 功能模組說明、API 規格等（若存在）
- <ios 專案根>/CLAUDE.md（若存在）   — 該專案的踩坑日誌與局部約定
```

> **綠地專案例外**：若 `native/ios/` 或任何 docs 目錄尚不存在（全新專案），跳過此步驟，直接依本 skill 的「專案結構」與規範初始化專案，並建議同步建立 `<ios 專案根>/docs/architecture.md` 供後續開發參照。

讀取完成後，根據文件中的既有架構與慣例進行開發，確保新代碼與現有代碼風格一致。

## 核心理念與標準 (Core Philosophy & Standards)

- **架構 (Architecture)**：嚴格遵循 **MVVM** 模式。View 負責 UI 呈現，ViewModel 負責業務邏輯與狀態管理，Model 負責資料定義。
- **UI 框架 (UI Framework)**：全面使用 **SwiftUI**。利用其宣告式語法與狀態驅動特性。
- **數據流 (Data Flow)**：單向數據流 (Unidirectional Data Flow)。View 透過 Action 觸發 ViewModel，ViewModel 更新 Published 屬性，View 自動刷新。
- **並發處理 (Concurrency)**：優先使用 Swift 現代化的 **Async/Await** 機制，減少 Callback Hell。
- **依賴注入 (Dependency Injection)**：使用 Protocol-Oriented Programming (POP) 與依賴注入來解耦組件，確保可測試性。

## 技術堆疊 (Tech Stack)

| 類別 | 技術 | 說明 |
|------|------|------|
| 語言 | Swift 5+ | |
| UI 框架 | SwiftUI | 宣告式 UI |
| 架構模式 | MVVM | Model-View-ViewModel |
| 異步處理 | Async/Await, Combine | Combine 用於與 SwiftUI 綁定，Async/Await 用於網絡請求 |
| 網絡層 | URLSession | 原生網絡庫，配合 Codable |
| 本地存儲 | UserDefaults / SwiftData | 輕量配置用 UserDefaults，複雜數據用 SwiftData 或 CoreData |
| 套件管理 | Swift Package Manager (SPM) | |
| 測試 | XCTest | 單元測試 (Unit Tests) 與 UI 測試 |

## 專案結構 (Project Structure)

建議採用 **Feature-Based** 的目錄結構，將相關功能的 View, ViewModel, Model 放在一起。

此結構為通用參考，實際專案通常位於 `native/ios/[ProjectName]/`。

```text
[ProjectName]/                   # 專案根目錄 (例如 house)
├── App/
│   ├── [App]App.swift           # App 入口點 (@main)
│   └── DependencyContainer.swift # 依賴注入容器 (或是 AppState)
├── Core/                        # 核心共用層
│   ├── Network/                 # 網絡層封裝 (APIClient, Endpoint, HTTPMethod)
│   ├── Extensions/              # Swift 擴展 (Color+, View+, String+)
│   ├── Utilities/               # 工具類 (Logger, Validations)
│   └── Constants/               # 全域常數 (API Keys, Configs)
├── Domain/                      # 全域領域模型
│   └── Models/                  # 跨功能共用的資料模型 (User, Token)
├── Features/                    # 功能模組 (按業務功能分類)
│   ├── Auth/                    # 範例：認證功能
│   │   ├── Views/               # SwiftUI Views (LoginView, SignUpView)
│   │   ├── ViewModels/          # ViewModels (LoginViewModel)
│   │   └── Services/            # 該功能專用的服務 (AuthService)
│   └── Home/                    # 範例：首頁功能
│       ├── Views/
│       ├── ViewModels/
│       └── Services/
├── Resources/                   # 資源文件
│   ├── Assets.xcassets          # 圖片與顏色資源
│   └── Preview Content/         # 預覽用假資料
└── [ProjectName]Tests/          # 單元測試目錄
    ├── Mocks/                   # Mock Services
    └── ViewModels/              # ViewModel Tests
```

## 實作流程 (Implementation Workflow)

實作新功能時，請遵循以下步驟：

1.  **Model & Protocol**：
    -   定義資料模型 (`struct`, `Codable`)。
    -   定義 Service 的 Protocol (介面)，方便後續 Mock 與測試。

2.  **Service (Repository)**：
    -   實作 Protocol，負責實際的資料獲取 (API 呼叫或本地資料庫)。
    -   使用 `async/await` 處理異步操作。
    -   回傳 `Result` 類型或使用 `throws` 處理錯誤。

3.  **ViewModel**：
    -   建立 class 繼承自 `ObservableObject`。
    -   透過建構子注入 Service (`init(service: ServiceProtocol)`).
    -   定義 `@Published` 屬性來持有 UI 狀態 (State) 與錯誤訊息 (Error)。
    -   實作函式處理使用者意圖 (Intent)，呼叫 Service 並更新狀態。

4.  **View**：
    -   建立 SwiftUI View。
    -   使用 `@StateObject` (若是 View 擁有 ViewModel) 或 `@ObservedObject` (若是外部傳入) 宣告 ViewModel。
    -   綁定 UI 元件至 ViewModel 的屬性。
    -   使用 `.task` 或 `.onAppear` 觸發初始資料加載。

5.  **Test**：
    -   為 Service 建立 Mock。
    -   撰寫 XCTest 測試 ViewModel 的邏輯 (輸入 Action -> 斷言 State 變化)。

## 編碼規則 (Coding Rules)

### 1. MVVM 職責劃分
- **View**：只負責顯示與使用者互動。**絕對不要**在 View 裡面直接呼叫 API 或寫複雜邏輯。
- **ViewModel**：
    -   不應導入 `SwiftUI` (除了 `Color` 或 `UIImage` 等 UI 類型，但盡量避免)。
    -   不應持有 View 的參考 (避免循環引用)。
    -   所有的 API 呼叫都應該在 ViewModel 中發起。
- **Model**：純資料結構，無業務邏輯。

### 2. 狀態管理 (State Management)
- **@State**：僅用於 View 內部的私有暫時狀態 (如 Toggle 開關、輸入框文字)。
- **@StateObject**：當 View **創建** ViewModel 時使用 (生命週期由該 View 管理)。
- **@ObservedObject**：當 ViewModel 是由**父 View 傳入**時使用。
- **@EnvironmentObject**：用於跨越多層 View 的全域狀態 (如 UserSettings, AuthState)。

### 3. 網絡請求 (Networking)
- 建立一個通用的 `APIClient`。
- 使用 `Generic` 泛型函式來處理 JSON 解碼：
    ```swift
    func request<T: Decodable>(_ endpoint: Endpoint) async throws -> T
    ```
- 錯誤處理應定義明確的 `APIError` enum。

### 4. 依賴注入 (Dependency Injection)
- 優先使用**建構子注入 (Initializer Injection)**。
    ```swift
    class LoginViewModel: ObservableObject {
        private let authService: AuthServiceProtocol

        init(authService: AuthServiceProtocol = AuthService()) {
            self.authService = authService
        }
    }
    ```
- 這使得在測試時可以輕鬆注入 MockService。

### 5. UI 開發
- **View 拆分**：當 `body` 超過 50 行或層級過深時，請拆分為小的子 View 或 Component。
- **預覽 (Previews)**：為每個 View 提供 `PreviewProvider`，並注入假資料以便快速迭代。
- **修飾符 (Modifiers)**：重複的樣式應封裝為自定義 ViewModifier。
- **收鍵盤 & 可編輯輸入框**：表單的收鍵盤（點空白 / 玻璃半圓拉柄）與「明顯可編輯」輸入框已有通用元件，**新表單一律沿用、勿手刻**。三個**零 design-system 依賴、可 drop-in 任何 SwiftUI 專案**的源檔在 `examples/`（`KeyboardDismissDome.swift` / `View+KeyboardDismiss.swift` / `EditableFieldStyle.swift`）；安裝三步、解耦對照表、決策矩陣、Liquid Glass dome 的踩坑、`.contentShape` 不等於 focus 的陷阱，全見 `references/keyboard-and-input-patterns.md`。
- **角落導航鈕 & 下拉選擇控件**：左右上角導航（返回/收合/關閉/更多/分享）統一用 `CircleNavChip`/`CircleNavButton`（34 圓框零特例）；下拉選擇用 `.selectorGlass()`（原生 Material 中性玻璃，不會像系統 Menu 玻璃被 label icon 染色）。兩個 drop-in 源檔在 `examples/`（`CircleNavButton.swift` / `SelectorGlass.swift`）。**iOS 26 三坑必讀**（Menu 必配 `.plain`、toolbar 必配 `sharedBackgroundVisibility(.hidden)`、模擬器對系統玻璃渲染不可信必真機驗）+ header 左右平行技巧 + compact DatePicker 勿包框 + sheet grabber 慣例，全見 `references/nav-chips-and-glass-pickers.md`。
- **Threads 式 reveal 側選單（主頁滑開、選單固定在主頁底下）**：做「像 Threads / 脆一樣左右滑整頁切選單」時**必讀** `references/threads-reveal-drawer.md`——架構定案（ViewModifier + 拖曳 state 隔離 / 要推動 tab bar 必掛 App 根層 / 主頁不裁切才能上下貫穿）、UIKit 手勢橋接（edge pan 開 + cancelsTouchesInView 收）、不過衝 spring 參數，與 10 條血淚踩坑——最凶的一條：**模擬器對「offset 平移含 UIKit 容器的大樹」渲染不可信（疊影/錯位時好時壞，真機恆正常），視覺驗證一律真機，勿因 sim 異常改架構**。
- **ScrollView 內 tap 列的捲動誤觸防線**：**任何 ScrollView 內新增 Button / onTapGesture 列的非表單頁**（選項頁 / 清單 / 卡內可點列），一律掛誤觸雙防線——SwiftUI 對「按下後慢速小拖」會 commit 給 Button（20pt/0.5s 實測必誤觸；UIScrollView 的取消紀律管不到 SwiftUI 手勢），app 若全域關過 `delaysContentTouches` 更嚴重。Drop-in 源檔 `examples/ScrollTapGuard.swift`（`restoreTouchDelays()` = 恢復觸摸延遲 + UIKit 垂直 pan 取消守衛）；**必掛 ScrollView 的「內容」上**（掛 ScrollView 本身 = superview walk 落空、防線靜默失效）、適用邊界（表單頁勿掛 / 圖表按住查值與橫向手勢相容 / 排序豁免掛鉤）與驗證方式見 `references/scroll-tap-guard.md`。
- **自製長按拖曳排序列表**：SwiftUI `LongPress+Drag` sequence 做 reorder 有兩個修不掉的結構性抖動源——醞釀期被 ScrollView pan / touch-cancel 守衛殺 touch（豁免旗標與 `scrollDisabled` 都趕不上，且 touch cancel 時 `onEnded` 不保證 fire → 旗標卡死）、swap 讓位動畫污染 `DragGesture(.local)` 座標造成邊界 swap↔unswap 震盪——**一律改 UIKit `UILongPressGestureRecognizer` 橋接**：began 同步關 `isScrollEnabled`（不等 render）、位移讀 window 座標、`.cancelled` 分支保證清理、拖曳中 local 副本 ended 才 commit（persist N→1）。Drop-in 源檔 `examples/ReorderableDragList.swift`，根因推導、hysteresis 數學與真機驗證清單見 `references/uikit-drag-reorder.md`。
- **整列長按拖曳排序（無把手）**：要「長按列上任何位置」都能抓起時，透明 view 覆蓋整列會擋掉列本身的點擊與左滑——**recognizer 改掛外層 `UIScrollView`**（祖先收得到子樹 touch 但不參與 hit-test）。最反直覺的一條：`cancelsTouchesInView` **管不到 SwiftUI 自己的手勢**，長按成立後放手仍會觸發列的點擊，必須用 `shouldBeRequiredToFailBy` 宣告「其他 recognizer 等長按失敗才成立」（捲動 pan 要排除，否則捲動要等 0.45s）。與 `.contextMenu` 互斥。Drop-in 源檔 `examples/LongPressRowReorderList.swift`，見 `references/uikit-drag-reorder.md`「整列長按變體」。
- **ScrollView 內的左滑動作列**：`List` 之外自繪列用不了 `.swipeActions`，自訂時五個坑——`minimumDistance` 不可低於 UIScrollView pan 的 ~10pt（低於會圈住垂直 touch，sheet 下拉收合失效）、方向判定只在第一幀做（每幀重算會因手指下飄而誤判回彈）、iOS 26 動作鈕**必配 `.buttonStyle(.plain)`**（否則被畫成半透明玻璃膠囊蓋掉實色底）、常駐 `.shadow` 即使半徑 0 也讓每列離屏渲染而掉幀、收合淡出期間仍可 hit-test 需 `guard isOpen`。動作鈕掛 `background(alignment:)` 而非 ZStack sibling（免 GeometryReader 量高的雙 pass）。多列要「捲動即收合」須靠容器層協調者＋`onScrollPhaseChange`，只靠列自己的手勢收不到「在別的列上捲動」的訊號。**模擬器的合成左滑驅動不了 SwiftUI DragGesture，一律當成點擊，只能真機驗**。Drop-in 源檔 `examples/SwipeActionRow.swift`，見 `references/swipe-action-row.md`。

### 6. 錯誤處理
- ViewModel 應包含一個 `errorMessage` 或 `alertItem` 的 `@Published` 屬性。
- View 監聽此屬性並彈出 Alert 或顯示錯誤提示。

### 7. 命名慣例
- **View**: `LoginView`, `HomeView`, `UserProfileView`
- **ViewModel**: `LoginViewModel`, `HomeViewModel`
- **Service**: `AuthService`, `ProductService`
- **Model**: `User`, `Product` (單數名詞)

## 常用程式碼片段 (Snippets)

### ViewModel Template
```swift
import Foundation
import Combine

@MainActor // 確保 UI 更新在主線程
class ExampleViewModel: ObservableObject {
    @Published var state: ViewState = .idle
    @Published var data: [MyModel] = []
    @Published var errorMessage: String?

    private let service: MyServiceProtocol

    init(service: MyServiceProtocol = MyService()) {
        self.service = service
    }

    func fetchData() async {
        state = .loading
        do {
            let result = try await service.getData()
            self.data = result
            state = .loaded
        } catch {
            self.errorMessage = error.localizedDescription
            state = .error(error)
        }
    }
}

enum ViewState {
    case idle
    case loading
    case loaded
    case error(Error)
}
```

### View Template
```swift
import SwiftUI

struct ExampleView: View {
    @StateObject private var viewModel = ExampleViewModel()

    var body: some View {
        VStack {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView()
            case .loaded:
                List(viewModel.data) { item in
                    Text(item.title)
                }
            case .error:
                Text("Error occurred")
            }
        }
        .task {
            await viewModel.fetchData()
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
```

## 模擬器自動化（agent 驅動 E2E 時）

用 `simctl` / idb 類工具驅動模擬器做 UI 驗證時的實戰坑（2026-07 累積）：

1. **HID 打字會被 IME 攔截**：模擬器鍵盤語言含注音等 IME 時，`ui_type` 送的 ASCII 會被當注音鍵位（欄位出現「ㄅㄇ...」）。先設純英文鍵盤再測：
   `xcrun simctl spawn <udid> defaults write .GlobalPreferences AppleKeyboards -array "en_US@sw=QWERTY;hw=Automatic"`，重啟 app 生效。
2. **HID 打字會讓 iOS 認定「有實體鍵盤」**：軟體鍵盤隨後不再升起（焦點 caret 還在、鍵盤不見），且 `defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false` + 重啟 Simulator 只在下次打字前有效。這是模擬器環境特性、非 app bug——驗「鍵盤黏附/收合」類行為要在打字前截圖，或改真機。
3. **向 app 注入環境變數**：`SIMCTL_CHILD_` 前綴 + `simctl launch` 會把變數傳給 app 行程（如 `SIMCTL_CHILD_MY_API_BASE_URL=http://127.0.0.1:8080 xcrun simctl launch <udid> <bundle-id>`）。搭配 app 內 `ProcessInfo.processInfo.environment` 的 base URL 覆蓋點，可零改碼把 app 指向本機後端做 E2E；注意**只對該次 launch 有效**，使用者手動點 icon 重開就失效。
4. **文字欄清空**：無 backspace 鍵可送——先 tap 聚焦、長按叫出編輯選單（選取/全選）、tap 全選後直接打字覆蓋。

## App Store 送審（第一次上架 / 久違送審必讀）

送審前照 `references/asc-release-checklist.md` 走：專案端六項（PrivacyInfo.xcprivacy / 出口合規 / 裝置家族與方向 / build 號 / 圖示 / 付費牆與 IAP 取捨）→ ASC 資料面全用 `appstore-connect` MCP 填（分類、版權聲明、年齡分級、免費價格排程、地區、文案、隱私網址、審核聯絡人）→ 截圖走「MCP reserve → curl PUT 預簽 URL → PATCH md5」→ 送審三步、送出前停下確認。**兩個最常卡的點**：App 隱私標籤答完要按「發布」（API 做不到）；MCP 吞掉 409 明細時用 `.mcp.json` 的 key 自簽 ES256 JWT 直打 API 才看得到 `associatedErrors`。
