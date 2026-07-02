import SwiftUI

/// 收鍵盤「玻璃半圓拉柄」通用組件（Liquid Glass dome）。
///
/// 鍵盤頂緣中央一顆毛玻璃（`.ultraThinMaterial`）半圓凸起，內含鍵盤 icon（系統 `.primary`）
/// + accent 色向下箭頭。半透明、透出後面內容（不墊黑底）；tap → `action`（收鍵盤）。
///
/// 透過 `View.keyboardDismissDome(accent:)` 以 **overlay 掛在 app 內容層**（非 `.keyboard`
/// toolbar — 那會墊黑底；overlay 才透出真內容成 Liquid Glass），靠鍵盤高度觀察釘在鍵盤頂緣正中。
/// **改外觀只動這一個檔**，全 app 同步。
///
/// 依賴：純 SwiftUI（iOS 16+，`UnevenRoundedRectangle`）。無第三方 / 無 design-system 依賴 —
/// 可直接 drop-in 任何 SwiftUI 專案。
struct KeyboardDismissDome: View {
    /// 向下箭頭的強調色（傳 app 主色 / accent）。鍵盤 icon 固定用 `.primary`（深 / 淺色自適應）。
    var accent: Color = .accentColor
    let action: () -> Void

    private let domeWidth: CGFloat = 76
    private let domeHeight: CGFloat = 38

    /// 上半圓 + 平底：`width = 2 × height` 時為完美半圓（`UnevenRoundedRectangle` 頂角半徑 = 高）。
    private var dome: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: domeHeight,
                               bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0,
                               topTrailingRadius: domeHeight,
                               style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Image(systemName: "keyboard")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accent)
            }
            .offset(y: 3)   // 內容稍微往下，落在半圓視覺重心
            .frame(width: domeWidth, height: domeHeight, alignment: .center)
            .background(.ultraThinMaterial, in: dome)
            .overlay(dome.stroke(Color.primary.opacity(0.16), lineWidth: 0.6))
            // 上緣高光（Liquid Glass 感）：白色描邊只在上半段漸層顯現
            .overlay(
                dome.stroke(Color.white.opacity(0.45), lineWidth: 0.7)
                    .mask(LinearGradient(colors: [.white, .clear],
                                         startPoint: .top, endPoint: .center))
            )
            .shadow(color: .black.opacity(0.16), radius: 5, y: -1)
            .contentShape(dome)
        }
        .buttonStyle(.plain)
    }
}
