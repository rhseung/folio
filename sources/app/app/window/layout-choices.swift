import FolioDomain
import SwiftUI

struct LayoutChoices {
    struct Choice: Identifiable {
        let preset: PanePreset
        let enabled: Bool
        let chosen: Bool
        var id: String { preset.id }
    }

    let builtIn: [Choice]
    let mine: [Choice]
    let canSave: Bool
    let apply: (PanePreset) -> Void
    let save: () -> Void
    let manage: () -> Void
}
