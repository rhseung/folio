import FolioAI
import FolioDomain
import SwiftUI

@MainActor @Observable final class PaneDrag {
    struct Start {
        var divider: Int
        var layout: PaneLayout
        var left: CGFloat
        var pair: CGFloat
    }

    @ObservationIgnored var from: Start?
    var live: PaneLayout?
}
