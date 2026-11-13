import SwiftUI

#if os(macOS)
import AppKit
#endif

enum Appearance: String, CaseIterable {
    case system, light, dark
    static let storageKey = "appearance"

    var label: String {
        switch self {
        case .system: String(localized: .appearanceSystem)
        case .light: String(localized: .appearanceLight)
        case .dark: String(localized: .appearanceDark)
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

extension View {
    func followsAppearance() -> some View { modifier(AppearanceFollower()) }
}

private struct AppearanceFollower: ViewModifier {
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    func body(content: Content) -> some View {
        #if os(macOS)
        // `preferredColorScheme`이 아니라 `NSApp.appearance`를 쓴다. 이 값은 설정 창, 시트, 메뉴에도 적용된다.
        content.onChange(of: appearance, initial: true) { _, a in
            guard a != .system || NSApp.appearance != nil else { return }
            NSApp.appearance =
                switch a {
                case .system: nil
                case .light: NSAppearance(named: .aqua)
                case .dark: NSAppearance(named: .darkAqua)
                }
        }
        #else
        content.preferredColorScheme(appearance == .system ? nil : appearance == .dark ? .dark : .light)
        #endif
    }
}
