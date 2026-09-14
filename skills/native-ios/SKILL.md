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
- **收鍵盤 & 可編輯輸入框**：新表單一律沿用 `examples/KeyboardDismissDome.swift` / `View+KeyboardDismiss.swift` / `EditableFieldStyle.swift`，勿手刻；安裝與踩坑見 `references/keyboard-and-input-patterns.md`。
- **形體與材質（iOS 26 Liquid Glass）**：圓角只用 `Radius` 五檔 + 膠囊、全部 continuous；**玻璃只給導航層**（角落鈕 / pill 殼外的浮動 bar / 鍵盤拉柄），內容層實色、浮層材質，`#available(iOS 26)` 集中在 `examples/Surface.swift` 一檔。真機踩坑（rim 關不掉、巢狀玻璃粗黑邊、鏡片染色像色塊、glass 放 background 模擬器蓋字但真機正常、`glassEffectID` 只能點不能拖）與 Tab bar 式可拖曳鏡片選擇器 `examples/GlassPillPicker.swift`，見 `references/liquid-glass-ios26.md`。
- **角落導航鈕 & 下拉選擇控件**：統一 `CircleNavChip`/`CircleNavButton`（34 圓框零特例）與 `.selectorGlass()`，drop-in 在 `examples/CircleNavButton.swift` / `SelectorGlass.swift`；iOS 26 三坑（Menu 必配 `.plain`、toolbar 必配 `sharedBackgroundVisibility(.hidden)`、模擬器對玻璃渲染不可信）見 `references/nav-chips-and-glass-pickers.md`。
- **橫向手勢一律 UIKit pan 橋接**：SwiftUI `DragGesture` 在 ScrollView 內由 SwiftUI 分配所有權（起手橫向 ≳ 0.9 倍垂直即判給元件），**被判走的下拉不會回到 ScrollView / sheet 收合**——整頁都是列的 sheet 下拉常收不了、斜向捲動卡住同根。左滑列、可拖曳 pill 等任何自訂橫向手勢一律套 `examples/HorizontalPanGesture.swift`（iOS 18，只在水平為主時 begin；17 退 DragGesture），推導見 `references/swipe-action-row.md`「手勢所有權」。
- **ScrollView 內的左滑動作列**：`List` 之外自繪列用不了 `.swipeActions`；drop-in `examples/SwipeActionRow.swift`（已走 UIKit pan 橋接）。要點：動作鈕掛 `background(alignment:)` 免量高、iOS 26 動作鈕必配 `.buttonStyle(.plain)`、常駐 `.shadow` 掉幀、收合淡出期間 ghost tap 要 `guard isOpen`、多列「捲動即收合」靠容器協調者，見 `references/swipe-action-row.md`。
- **縱向 ScrollView 的橫向回彈**：iOS 26 內容貼齊寬度仍可被左右拉開 → 每個縱向 ScrollView 掛 `.scrollBounceBehavior(.basedOnSize, axes: .horizontal)`；**嚴禁** `UIScrollView.appearance().bouncesHorizontally = false`（殺掉 sheet 下拉收合）；內容略寬臨界用 `containerRelativeFrame(.horizontal) + clipped()` 最後防線，見 `references/scroll-bounce-and-width.md`。
- **Threads 式 reveal 側選單**：必讀 `references/threads-reveal-drawer.md`（架構定案、UIKit edge pan 開 + cancelsTouchesInView 收、不過衝 spring、10 條踩坑）；最凶一條：模擬器對「offset 平移含 UIKit 容器的大樹」渲染不可信，視覺一律真機。
- **ScrollView 內 tap 列的捲動誤觸防線**：任何非表單頁的 ScrollView 內 Button / onTapGesture 列，內容一律掛 `examples/ScrollTapGuard.swift` 的 `restoreTouchDelays()`（恢復觸摸延遲 + UIKit 垂直 pan 取消守衛），**必掛 ScrollView 的內容而非 ScrollView 本身**，邊界見 `references/scroll-tap-guard.md`。
- **長按拖曳排序**：SwiftUI `LongPress+Drag` 有修不掉的抖動源，一律改 UIKit `UILongPressGestureRecognizer` 橋接——把手版 `examples/ReorderableDragList.swift`、整列版 `examples/LongPressRowReorderList.swift`（recognizer 掛外層 UIScrollView + `shouldBeRequiredToFailBy`），推導見 `references/uikit-drag-reorder.md`。

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
5. **合成手勢能做什麼**：`idb ui swipe` 驅動得了 SwiftUI `DragGesture`（18pt 門檻可開列、拉深）、UIKit `UIPanGestureRecognizer`、sheet 的系統下拉收合（從 ScrollView 內容區往下拉）；做不到邊緣手勢與「長按停住再拖」的 lift。若 sheet 拉不動，先懷疑全域回彈設定（見 `references/scroll-bounce-and-width.md`），不是 idb。
6. **量測工法**：AX dump（`idb ui describe-all --json`）比對固定標籤的 y 得捲動量、列出 `x+width > 螢幕寬` 找超寬元素；固定角度 swipe 可量手勢仲裁邊界。
7. **字級**：`defaults write` 改字級鍵在 cfprefsd 快取下常不生效，要在 app 內點（AX label 形如「Aa、特大」）；`orua.onboarded` 類首裝哨兵則要在首次啟動**前**寫。

## App Store 送審（第一次上架 / 久違送審必讀）

送審前照 `references/asc-release-checklist.md` 走：專案端六項（PrivacyInfo.xcprivacy / 出口合規 / 裝置家族與方向 / build 號 / 圖示 / 付費牆與 IAP 取捨）→ ASC 資料面全用 `appstore-connect` MCP 填（分類、版權聲明、年齡分級、免費價格排程、地區、文案、隱私網址、審核聯絡人）→ 截圖走「MCP reserve → curl PUT 預簽 URL → PATCH md5」→ 送審三步、送出前停下確認。**兩個最常卡的點**：App 隱私標籤答完要按「發布」（API 做不到）；MCP 吞掉 409 明細時用 `.mcp.json` 的 key 自簽 ES256 JWT 直打 API 才看得到 `associatedErrors`。
