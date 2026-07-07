# 角落導航鈕 & 玻璃選擇控件（iOS 26 實戰模式）

兩個 drop-in 元件（`examples/CircleNavButton.swift`、`examples/SelectorGlass.swift`）+ 一組實戰踩出來的 iOS 26 系統玻璃陷阱。**零 design-system 依賴**：預設吃系統語意色 / 原生 Material，專案有 token 時由呼叫端注入。

## 元件一：CircleNavChip / CircleNavButton（角落導航鈕）

**解決什麼**：App 各頁左右上角的「上一頁 ‹ / 收合 ˅ / 關閉 ✕ / 更多 ⋯ / 分享」長期漂移成多種尺寸（30/32/34）與樣式（裸 icon / 文字鈕 / 異規邊框）。統一為單一元素：34×34 圓框 chip、icon 13/light、**零 per-icon 特例**（連 ⋯ 都不開特例——元素完全一致優先於 glyph 光學微調）。

**用法矩陣**：

| 場景 | 寫法 |
|------|------|
| 一般按鈕 | `CircleNavButton(icon: "chevron.left") { dismiss() }` |
| Menu 觸發（⋯） | `Menu { … } label: { CircleNavChip(icon: "ellipsis") }`**`.buttonStyle(.plain)`** ← 必加 |
| 原生 toolbar 內 | ToolbarItem 內放 chip + **`.sharedBackgroundVisibility(.hidden)`**（iOS 26，`#available` 分流；iOS 17/18 無玻璃底直接放） |
| sheet 收合語意 | icon 用 `chevron.down`；push 返回用 `chevron.left`；表單「取消」文字鈕屬丟棄語意，**不要**硬換成 chip |

**Header 左右平行**：單行標題（~20pt）與 34pt chip 置中後頂/底緣不齊，肉眼讀作「左右不平行」。解法：左側標題叢集加 `.frame(minHeight: 34, alignment: .leading)` 鎖等高 band——任何字級下兩側自動對齊，成本一行。

## 元件二：selectorGlass（選擇控件中性玻璃）

**解決什麼**：下拉選擇（幣別/帳戶/圖示…）手刻方框醜、用系統 Menu 玻璃又會被染色（見坑 #1）。`.selectorGlass()` = 原生 `Material` + 20pt 連續圓角 + 頂亮→底淡細白描邊 + 低仰角軟陰影，深淺色自適應（iOS 15+，不依賴 iOS 26 glassEffect）。

**用法**：Menu/Button 加 `.buttonStyle(.plain)` 壓系統玻璃 → label content 套 `.selectorGlass()`。開 sheet 的 Button 改用 `SelectorGlassButtonStyle()`（外觀 + spring 按壓）。

**shadow 掛法**：shadow 必須掛在背景 shape 上（`shape.fill(...).shadow(...)`），掛在 view 外層會連 label 文字一起投影；且 shadow 進 background 後**不可再 `.clipShape`**（會把陰影裁掉）。

## ⚠️ iOS 26 系統玻璃三坑（同一族，實戰各踩過）

1. **系統 Menu 玻璃會吸收 label 內前景 icon 的色調**：label 裡有一顆金色 icon → 整顆膠囊被染成金色；未選中（灰 icon）時又是中性 → 同一控件兩種顏色、且與相鄰控件不一致。自製 Material / `.glassEffect(.regular)` 不吃 tint，永遠中性——這是不用系統預設玻璃的根本原因。
2. **Menu label 放自製 chip 而 Menu 沒加 `.buttonStyle(.plain)`**：真機 iOS 26 用系統玻璃圓底把 chip **再包一層**（雙圓／放大的米黃圓）。
3. **原生 toolbar 放自製 chip**：toolbar 按鈕自帶玻璃圓底，同樣雙圓疊套。解法 `sharedBackgroundVisibility(.hidden)`；或退而求其次 toolbar 內放裸 icon 讓系統圓底呈現（但與自訂 header 的 chip 不同材質，能用 hidden 就用 hidden）。

**鐵律：模擬器對系統玻璃的渲染極弱、與真機不一致**——坑 #2 在模擬器上幾乎看不出來，真機一眼爆。**凡涉及 Menu/toolbar + 自製元件的改動，必須真機驗證後才算完成。**

## 相關慣例（同場加映）

- **sheet 下拉提示**：`presentationDragIndicator(.visible)` 掛在全 app 共用的 sheet 根容器（如 AppShell）一次生效；刻意 `interactiveDismissDisabled` 的 sheet 顯式 `.hidden` 蓋掉，不給「可以滑」的假暗示。
- **compact DatePicker 不要包框**：`.datePickerStyle(.compact)` 本身就是原生圓角 chip，外面再包 `background + stroke` 就是雙重裝飾；乾淨版只留 `.labelsHidden().tint(accent)`。日期範圍選擇的高質感版式：標題+「完成」列 → 細線 → 兩列「label 左、日期 chip 右」的 inline DatePicker（`DatePicker(selection:in:){ Text(label) }`），`in:` 互相 clamp 天然防無效區間，`presentationDetents([.height(240)])` 小卡呈現。
