import FolioDomain
import SwiftUI

enum Tone {
    case plain, accent, warning, danger, success, info

    @MainActor var foreground: Color {
        switch self {
        case .plain, .accent: Theme.Palette.text
        case .warning: Theme.Palette.warning
        case .danger: Theme.Palette.danger
        case .success: Theme.Palette.success
        case .info: Theme.Palette.info
        }
    }

    @MainActor var fill: Color {
        switch self {
        case .plain, .accent: Theme.Palette.fill
        case .success: Theme.Palette.success.opacity(Theme.Opacity.tint)
        case .warning: Theme.Palette.warningFill
        case .danger: Theme.Palette.dangerFill
        case .info: Theme.Palette.infoFill
        }
    }
}

extension StatusTone {
    @MainActor var tint: Color {
        switch self {
        case .plain: Theme.Palette.text
        case .good: Theme.Palette.success
        case .caution: Theme.Palette.warning
        case .bad: Theme.Palette.danger
        case .info: Theme.Palette.info
        case .muted: Theme.Palette.textSecondary
        }
    }
}
