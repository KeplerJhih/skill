import SwiftUI
import UIKit
import Combine

// 收鍵盤通用 modifier。兩個 live 模式：
//   ① .dismissKeyboardOnTap()       — 點空白處收（form 類 sheet 預設首選）
//   ② .keyboardDismissDome(accent:)  — 鍵盤頂緣玻璃半圓拉柄，tap + 點背景 + 滑動收三合一
// 依賴：SwiftUI + UIKit + Combine（iOS 16+，`scrollDismissesKeyboard`）。無 design-system 依賴。
// 搭配 KeyboardDismissDome.swift 一起 drop-in。

extension View {

    // MARK: - 點空白處收鍵盤（預設首選）

    /// 在 view 內 tap 任何空白處都會收鍵盤 — 除了點到另一個 TextField（切換輸入欄不閃爍）。
    /// 用 `endEditing(true)` 對整個 window 強制收，比 `sendAction(resignFirstResponder, ...)` 可靠。
    ///
    /// **首選用法**：form 類 sheet（欄位 + 留白）— 套在最外層 view 後，user 點任何 TextField 外的
    /// 區域（空白 / label / chip）就收鍵盤，不必擠 toolbar Done 按鈕。視覺最乾淨。
    ///
    /// **不適用**：畫面全被 TextEditor 蓋滿沒有空白可點 — 改套 dome 拉柄即可。
    func dismissKeyboardOnTap() -> some View {
        background(KeyboardDismissTapView())
    }

    // MARK: - 鍵盤頂緣「置中玻璃半圓拉柄」（overlay 版，收鍵盤全套）

    /// 在**鍵盤頂緣中央**浮一顆 `KeyboardDismissDome`（玻璃半圓拉柄，鍵盤 icon + accent 箭頭），
    /// 隨鍵盤升降出現 / 緊貼鍵盤頂緣；tap → 收鍵盤。**套在 sheet 最外層**。
    ///
    /// **為何 overlay 而非 `.keyboard` toolbar**：toolbar 版的 dome 渲染在「鍵盤自己的圖層」，
    /// 玻璃只能糊到鍵盤暗底 → 看起來像「黑底＋玻璃」、又黏在 accessory 區不夠貼鍵。
    /// 本版把 dome 放進 **app 內容層的 overlay**，毛玻璃透出的是真正的表單內容（Liquid Glass），
    /// 並用鍵盤高度（`keyboardWillChangeFrame`）把它釘在**鍵盤頂緣正上方緊貼**。
    ///
    /// **收鍵盤全套 = 一行搞定三種收法**：本 modifier 已內含
    /// ① 玻璃拉柄 tap ② 點背景空白（`dismissKeyboardOnTap`）③ 滑動內容（`scrollDismissesKeyboard(.immediately)`）。
    /// 後續其他表單只要套這一行即同時擁有三種收法，不必各自再加。
    /// **配合 footer 釘底**：sheet 仍需 `.ignoresSafeArea(.keyboard, edges:.bottom)`（各自獨立）。
    /// ```
    /// VStack { …欄位… }
    ///     .ignoresSafeArea(.keyboard, edges: .bottom)
    ///     .keyboardDismissDome(accent: .accentColor)   // ← 拉柄 + 點背景收 + 滑動收，全包
    /// ```
    func keyboardDismissDome(accent: Color = .accentColor) -> some View {
        modifier(KeyboardDismissDomeModifier(accent: accent))
    }
}

// MARK: - Internal: tap-outside coordinator

private struct KeyboardDismissTapView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = TapProxyView()
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    /// 手勢必須掛在 **window** 而非本 background view：`Form`/`List`（UICollectionView）
    /// 會把空白處的 touch 全部吃掉，touch 到不了 background 層的 recognizer（ScrollView/VStack
    /// 型 sheet 不會踩、Form 型必踩）；掛 window（所有 view 的 ancestor）才收得到。
    /// 隨 view 進出 window 自動掛載 / 移除。
    final class TapProxyView: UIView, UIGestureRecognizerDelegate {
        private var tap: UITapGestureRecognizer?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // 離開舊 window（sheet 關閉）→ 從舊 window 移除，避免殘留
            if let tap { tap.view?.removeGestureRecognizer(tap) }
            self.tap = nil
            guard let window else { return }
            let g = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            g.cancelsTouchesInView = false   // 不吃掉 tap，Button/chip 照常運作
            g.delegate = self
            window.addGestureRecognizer(g)
            tap = g
        }

        @objc func handleTap() {
            // endEditing(true) 對整個 window 強制收，連 SwiftUI 內部的
            // FocusState 也會跟著清（因為它 backing 還是 UIKit responder）。
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .forEach { $0.endEditing(true) }
        }

        // 點到 TextField 跳過，讓 iOS 自然處理切換輸入欄不閃爍
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            var v = touch.view
            while let cur = v {
                if cur is UITextField || cur is UITextView { return false }
                v = cur.superview
            }
            return true
        }

        // 跟其他 gesture（DatePicker / Button 內建）同時辨識，不會被「吃掉」
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

// MARK: - 玻璃半圓拉柄 overlay + 鍵盤高度觀察

/// 把 `KeyboardDismissDome` 浮在 app 內容層、釘在鍵盤頂緣中央。整層走 GeometryReader +
/// `.ignoresSafeArea()` 取全螢幕座標，`.position` 把 dome 底邊頂到鍵盤頂緣（緊貼）。
/// 空白處不攔觸（只有 dome Button 收觸），不擋鍵盤鍵 / 表單。
private struct KeyboardDismissDomeModifier: ViewModifier {
    let accent: Color
    @StateObject private var kb = KeyboardHeightObserver()

    func body(content: Content) -> some View {
        // **dome 用 .overlay 疊在 content 上，而非 ZStack 同層**。
        // 踩坑：原 `ZStack{ content; GeometryReader{}.ignoresSafeArea() }` 的全螢幕 GeometryReader
        // 會讓 ZStack 撐成全螢幕、連帶 content 跟著「忽略鍵盤」→ 內容短的搜尋頁結果列表延伸到鍵盤後、
        // 結果與鍵盤間露一大塊空白。改 .overlay：overlay 不驅動 source(content) 的尺寸與 safe area，
        // content 維持正常 keyboard avoidance；overlay 那層自身 .ignoresSafeArea() 仍取全螢幕座標供
        // dome 定位（只動 dome 層）。footer 釘底由各 sheet 自己顯式 .ignoresSafeArea(.keyboard) 決定。
        content
            // **一併綁定另外兩種收鍵盤方式**（此 modifier = 收鍵盤全套）：
            .scrollDismissesKeyboard(.immediately)   // 滑動內容收（env 傳播到內層 ScrollView）
            .dismissKeyboardOnTap()                  // 點背景空白處收
            .overlay {
                // dome **永遠存在**，位置綁 `kb.height` 連續變化 → 鍵盤滑上來時一起從下往上滑。
                GeometryReader { geo in
                    KeyboardDismissDome(accent: accent, action: dismissAll)
                        .position(x: geo.size.width / 2,
                                  y: geo.size.height - kb.height - 19)   // 底邊貼鍵盤頂（19 = domeHeight/2）
                        .opacity(kb.height > 1 ? 1 : 0)                  // 收下時淡出
                        .allowsHitTesting(kb.height > 40)
                }
                .ignoresSafeArea()                                       // 取全螢幕座標（只此 overlay 層）
                // 用**鍵盤自己的動畫時長**驅動，起落跟鍵盤同步。
                .animation(.easeOut(duration: kb.duration), value: kb.height)
            }
    }

    private func dismissAll() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .forEach { $0.endEditing(true) }
    }
}

/// 觀察鍵盤覆蓋高度 + 動畫時長：`keyboardWillChangeFrame`/`WillShow` → 螢幕高 − 鍵盤頂 y；`WillHide` → 0。
/// 同步抓 `keyboardAnimationDuration`，讓 dome 用鍵盤同款時長 animate → 跟鍵盤一起彈起 / 收下。
@MainActor
final class KeyboardHeightObserver: ObservableObject {
    @Published var height: CGFloat = 0
    @Published var duration: Double = 0.25
    private var bag: Set<AnyCancellable> = []

    init() {
        let nc = NotificationCenter.default
        nc.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
            .merge(with: nc.publisher(for: UIResponder.keyboardWillShowNotification))
            .sink { [weak self] note in
                guard let info = note.userInfo,
                      let frame = (info[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                else { return }
                self?.duration = (info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
                self?.height = max(0, UIScreen.main.bounds.height - frame.minY)
            }
            .store(in: &bag)
        nc.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] note in
                self?.duration = (note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
                self?.height = 0
            }
            .store(in: &bag)
    }
}
