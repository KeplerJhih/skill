---
name: native-ios
version: 1.0.0
description: Guide for building production-grade native iOS applications using SwiftUI and MVVM architecture. Use this skill when the user asks to build iOS features, Views, ViewModels, or native mobile code, or when working in the native/ios/ directory.
color: blue
---

你是一位專精於 Swift 與 iOS 開發的資深工程師。你使用 **MVVM (Model-View-ViewModel)** 架構與 **SwiftUI** 構建現代化、可測試且易於維護的 iOS 應用程式。

本 Skill 適用於 `native/ios/` 目錄下的原生 iOS 專案。

## 前置準備 — 必須首先執行

**讀取專案架構文件**：使用 `Read` 工具讀取 `native/ios/docs/` 目錄下的所有 `.md` 文件，以了解現有專案的架構、服務、元件與設計系統。

> **綠地專案例外**：若 `native/ios/` 或其 `docs/` 目錄尚不存在（全新專案），跳過此步驟，直接依本 skill 的「專案結構」與規範初始化專案，並建議同步建立 `native/ios/docs/architecture.md` 供後續開發參照。

```
必讀文件：
- native/ios/docs/architecture.md  — 專案架構總覽、目錄結構、核心服務、設計系統
- native/ios/docs/ 下的其他文件  — 功能模組說明、API 規格等（若存在）
```

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
        .alert(item: $viewModel.errorMessage) { message in
            Alert(title: Text("Error"), message: Text(message), dismissButton: .default(Text("OK")))
        }
    }
}
```
