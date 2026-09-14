# 縱向 ScrollView 的橫向回彈與內容寬度：三條規則與量測工法

## 現象

iOS 26 的縱向 `ScrollView` 在內容剛好貼齊寬度時仍給橫向回彈空間，真機上整頁可以被左右拉開再彈回；內容若比視窗寬哪怕幾 pt，就從「回彈」變成「真的可以橫向捲」。設定類頁面、表單、統計卡都會中。

## 規則一：逐頁掛 `scrollBounceBehavior`

每個縱向 ScrollView（包括 sheet 內的）掛：

```swift
ScrollView { … }
    .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
```

橫向 chip 列另有各自的處理（放得下不可拖，見 `liquid-glass-ios26.md`）。

## 規則二：嚴禁 UIKit 全域關橫向回彈

```swift
UIScrollView.appearance().bouncesHorizontally = false   // ❌ 不要
```

UIKit 會連帶把 `bounces` 視為關閉，**sheet 靠 ScrollView 頂端回彈驅動的系統下拉收合整條失效**——所有含 ScrollView 的 sheet 從內容區往下拉都收不了。實證：加了之後備忘錄 sheet 八次下拉全失敗，撤回即恢復。一行看似省事，代價是全 app 的 sheet 收合。

## 規則三：內容略寬的臨界 → 最後防線

`basedOnSize` 只在「內容不比視窗寬」時擋得住。真機 393pt 曾因某頁內容略寬（右側開關被推出畫面、wrap 版面一列多擠一格），整頁可被拉開，而模擬器 402pt 加特大字級量遍所有元素都在框內、重現不到那幾 pt 的臨界。結構性解法（首頁早就這樣做）：

```swift
ScrollView {
    VStack { … }
        .containerRelativeFrame(.horizontal)   // 內容寬強制 = ScrollView 寬
        .clipped()                             // 漏網的寬元素被裁掉，不撐寬整頁
}
```

配合字級 × 螢幕寬的既有防線：`lineLimit(1) + minimumScaleFactor`、`layoutPriority` 分誰先縮、死寬度乘字級倍率。

## 量測工法（模擬器）

- **找超寬元素**：`idb ui describe-all --json` 走訪所有 AX 元素，列出 `x + width > 螢幕寬` 的項目（排除 Application 根與 x ≥ 螢幕寬的離屏抽屜）。
- **橫拖是否真的動**：記一個 AX 標籤的 `x`，`idb ui swipe` 橫向拖一段，再讀一次比對；回彈會彈回，所以要在 swipe 結束後 0.3s 內截圖才看得到拉開的瞬間。
- **字級**：`defaults write <bundle> orua.fontScale` 類的 UserDefaults 改字級在 cfprefsd 快取下常不生效，改字級要在 app 內點；用 AX 找到字級 pill（label 形如「Aa、特大」）再 tap。
- **idb 合成手勢能做什麼**：能驅動 sheet 的系統下拉收合（從 ScrollView 內容區往下拉）、能驅動 UIKit `UIPanGestureRecognizer`、能驅動 SwiftUI `DragGesture`（18pt 門檻可開列、可拉深）。先前「idb 拉不動 sheet」的紀錄是被全域回彈設定（規則二）誤導，已翻案。做不到的：`UIScreenEdgePanGestureRecognizer` 邊緣手勢、長按後原地不動再拖的 lift。
