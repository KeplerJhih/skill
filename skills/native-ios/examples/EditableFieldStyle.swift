import SwiftUI
import UIKit

/// 「明顯是可編輯輸入框」通用樣式：**填色底 + 左 accent 細軌 + 細框 + 右鉛筆 icon**。
///
/// 解決「極淡外框跟分隔線一樣，看不出能點擊輸入」的問題（尤其備註類選填欄）。
/// 四個顏色參數**預設吃系統語意色**（`.secondarySystemBackground` / `.separator` / `.accentColor`
/// / `.secondary`），深 / 淺色自動自適應；要套 app design-system 就傳對應 token。
/// 無第三方 / 無 design-system 依賴 — 可直接 drop-in 任何 SwiftUI 專案。
///
/// 用法：`TextField(...).editableFieldStyle()`（focus / tap 手勢仍由 caller 自行掛，見 reference §4）。
struct EditableFieldStyle: ViewModifier {
    /// 填色底（一看就是輸入框）。預設 `.secondarySystemBackground`。
    var fill: Color = Color(uiColor: .secondarySystemBackground)
    /// 外框細線。預設 `.separator`。
    var border: Color = Color(uiColor: .separator)
    /// 左側強調細軌（可編輯暗示）。預設 `.accentColor`。
    var rail: Color = .accentColor
    /// 右側鉛筆 icon 色。預設 `.secondary`。
    var pencilColor: Color = .secondary
    /// 是否顯示右側鉛筆 icon。
    var showPencil: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12)
            .padding(.leading, 13)
            .padding(.trailing, showPencil ? 32 : 13)   // 預留右側鉛筆空間，文字不被蓋
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill)                              // 填色底：一看就是輸入框
            .overlay(Rectangle().stroke(border, lineWidth: 0.5))
            .overlay(alignment: .leading) {               // 左 accent 細軌：可編輯欄位暗示
                Rectangle().fill(rail).frame(width: 2)
            }
            .overlay(alignment: .trailing) {              // 右鉛筆：點此編輯
                if showPencil {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(pencilColor)
                        .padding(.trailing, 12)
                }
            }
            .contentShape(Rectangle())                    // 整個填色框都可點（配合 caller 的 focus 手勢）
    }
}

extension View {
    /// 套用「明顯可編輯輸入框」樣式（填色 + 左 accent 軌 + 鉛筆 icon，深淺色自適應）。
    /// 顏色省略時吃系統語意色；要套 design-system 就傳對應 token：
    /// `.editableFieldStyle(fill: t.bgElev, rail: t.gold, ...)`。
    func editableFieldStyle(fill: Color = Color(uiColor: .secondarySystemBackground),
                            border: Color = Color(uiColor: .separator),
                            rail: Color = .accentColor,
                            pencilColor: Color = .secondary,
                            showPencil: Bool = true) -> some View {
        modifier(EditableFieldStyle(fill: fill, border: border, rail: rail,
                                    pencilColor: pencilColor, showPencil: showPencil))
    }
}
