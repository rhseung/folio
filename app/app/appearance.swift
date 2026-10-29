import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Light, dark or following the system. Kept per device in user defaults: settings.json is shared by every device.
enum Appearance: String, CaseIterable {
    case system, light, dark
    static let storageKey = "appearance"

    var label: String {
        switch self {
        case .system: "자동"
        case .light: "라이트"
        case .dark: "다크"
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
        // NSApp.appearance rather than preferredColorScheme: it also reaches the Settings window, sheets and menus.
        content.onChange(of: appearance, initial: true) { _, a in
            // Left alone when it already follows the system: assigning nil drops a launch-time appearance override.
            guard a != .system || NSApp.appearance != nil else { return }
            NSApp.appearance = switch a {
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
