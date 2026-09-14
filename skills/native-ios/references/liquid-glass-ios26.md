# iOS 26 Liquid Glass 與圓潤形體：三層分工、鏡片選擇器、真機踩坑

> Drop-in 源檔：`examples/Surface.swift`（圓角尺 + 六個表面 modifier）、`examples/GlassPillPicker.swift`
> （Tab bar 式可拖曳玻璃鏡片選擇器，依賴 Surface.swift 的 `selectionLens` 與 `examples/HorizontalPanGesture.swift`）。
> 皆零 design-system 依賴，顏色由呼叫端注入。

## 三層分工：玻璃只給導航層

Apple 的 Liquid Glass 是給「浮在內容上方的控制層」用的，內容本身維持實色。實戰定案：

| 層 | 材質 | 用在 |
|----|------|------|
| 內容層 | 實色底 + 0.5pt 細框 + 連續圓角（`contentCard` / `fieldSurface` / `roundedStroke`） | 卡片、輸入框、表單容器、**LazyVStack 每一列**（零材質，捲動零成本） |
| 浮層 | `.ultraThinMaterial`，少量、非每列 | 群組卡、頂部 banner、拖曳懸停特效、釘底 footer 底（`pinnedFooterBackdrop`） |
| 導航層 | `.glassEffect`（iOS 26）／磨砂替身（17–25），`chromeGlass` | 角落鈕、pill 選擇器、底部浮動搜尋 bar、鍵盤拉柄 |

規則：
- **`#available(iOS 26)` 只允許出現在 Surface 一檔**，Feature 層不得自行寫 availability 分支。
- 圓角只用五檔 + 膠囊（xs 6 / sm 10 / md 14 / lg 20 / xl 28），全部 `.continuous`；巢狀同心：內圓角 = 外圓角 − 內距。
- 不要再寫 `RoundedRectangle(cornerRadius: 數字)` 或 `.background(accent)` 方塊；點擊面積一律保留 `.contentShape(Rectangle())`，只換視覺 shape。
- 玻璃層不疊手刻描邊 / 陰影（會跟系統玻璃打架）；內容卡不加陰影。

## 真機踩坑（每一條都退過版）

1. **`glassEffect` 的白色 specular rim 關不掉**：鋪在內容卡（群組卡）上真機使用者反映不舒服 → 退回 `ultraThinMaterial`。這是「玻璃只給導航層」的起點。
2. **巢狀玻璃出粗黑邊**：殼 `glassEffect` + 裡面的選中鏡片 `glassEffect`，鏡片嵌在殼的內容裡 = 巢狀，iOS 26 真機畫出又粗又黑的邊。底部 Tab bar 是「毛玻璃殼 + 一顆清透鏡片」**兩層獨立**。解：殼改 `.ultraThinMaterial` 不描邊，鏡片才是唯一 glassEffect。
3. **鏡片染色像實心色塊**：`glassEffect(.regular.tint(accent))` 在真機看起來是實心色塊、看不出鏡片。對齊 Tab bar：鏡片不染色 + 選中文字改 accent 色。
4. **玻璃放 `.background` 在模擬器會蓋住文字**（選中字整個消失），真機正常。這是模擬器渲染問題，**勿據此改架構**；同族：模擬器對 Menu / toolbar 雙圓、offset 平移大樹的渲染都不可信，玻璃相關改動一律真機驗。
5. **`glassEffectID` morph 只能點、不能拖**：它是「舊鏡片消失、新鏡片出現」的過渡，就算加 `glassEffectTransition(.matchedGeometry)` 也只是滑過去，做不到 Tab bar「按住拖著鏡片走」。
6. 既有三坑仍在：chip 進 `Menu` 必配 `.buttonStyle(.plain)`、進原生 toolbar 必配 `sharedBackgroundVisibility(.hidden)`、系統 Menu 玻璃會吸 label icon 的色調（見 `nav-chips-and-glass-pickers.md`）。

## Tab bar 式鏡片選擇器（GlassPillPicker）正解

- 固定的毛玻璃膠囊殼；chip 放得下走靜態 HStack、放不下才在殼內橫向捲（`ViewThatFits`，捲動時 `basedOnSize` + 膠囊裁切）。**殼不能套在橫向 ScrollView 的內容上**，否則整條殼跟著被拖來拖去（真機實訴）。
- **一顆常駐鏡片**（`selectionLens`：iOS 26 不染色 interactive 玻璃，17–25 accent 18% 淡底）由元件量每顆 chip 的 frame 自己定位；點別的 chip 鏡片 spring 滑過去；按住拖 → 鏡片跟手微放大、經過哪個 chip 就選哪個（selection 震動）、放手吸附。
- 拖曳走 `HorizontalPanGesture`（UIKit pan，只在水平為主時 begin），外層縱向 ScrollView 的捲動與 sheet 下拉收合完全不受影響；殼內要捲動的情境不提供拖曳選擇。
- 選中靠文字改 accent 色（鏡片透明），分類型 pill 可傳 hue 色。

## 釘底 footer 的磨砂底

ZStack(.bottom) sibling 的儲存 / 確認列改成膠囊按鈕後，內容捲過去會直接露在按鈕旁邊（使用者明確反感）。`pinnedFooterBackdrop` = `.ultraThinMaterial` + 40% 底色往下延伸到螢幕底緣、頂緣 35% 漸淡；ScrollView 內容仍留 `.padding(.bottom, ~100)` 讓最後一欄捲得上來。

## 驗收

- 模擬器只能驗建置、版面與 17–25 替身；鏡片質感、morph、黑邊、雙圓一律真機。
- 每套配色（含深淺）各截一張看卡片描邊對比。
