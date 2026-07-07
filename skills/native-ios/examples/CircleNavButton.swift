import SwiftUI

/// 頁面角落導航鈕的統一元素:34×34 圓框 chip(填色底 + 細框 + 次要色 icon)。
/// 上一頁 ‹ / 收合 ˅ / 關閉 ✕ / 更多 ⋯ / 分享 等**所有角落導航**共用同一元素,
/// 全 app 视覺一致(尺寸/粗細/顏色零特例)。
///
/// **零 design-system 依賴,可 drop-in 任何 SwiftUI 專案**:預設吃系統語意色,
/// 專案有自己的 token 時由呼叫端傳入(或改預設值三行)。
///
/// ⚠️ iOS 26 玻璃三坑(缺一步就雙圓疊套,詳見 references/nav-chips-and-glass-pickers.md):
///   1. 放進 `Menu` 當 label → Menu **必配 `.buttonStyle(.plain)`**
///   2. 放進原生 `.toolbar` → ToolbarItem **必配 `sharedBackgroundVisibility(.hidden)`**(iOS 26)
///   3. 此類改動**模擬器渲染不可信,必須真機驗證**
struct CircleNavChip: View {
    let icon: String
    /// 一律預設 13/light — 元素完全一致,勿開 per-icon 特例。
    var iconSize: CGFloat = 13
    var weight: Font.Weight = .light
    var iconColor: Color = .secondary
    var fill: Color = Color(.secondarySystemBackground)
    var border: Color = Color(.separator).opacity(0.6)

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: iconSize, weight: weight))
            .foregroundColor(iconColor)
            .frame(width: 34, height: 34)
            .background(fill)
            .overlay(Circle().stroke(border, lineWidth: 0.5))
            .clipShape(Circle())
    }
}

/// CircleNavChip 的 Button 包裝(plain style 已內建)。
struct CircleNavButton: View {
    let icon: String
    var iconSize: CGFloat = 13
    var weight: Font.Weight = .light
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CircleNavChip(icon: icon, iconSize: iconSize, weight: weight)
        }
        .buttonStyle(.plain)
    }
}
