import FolioAI
import FolioDomain
import SwiftUI

@MainActor final class PaneSizes {
    var open: [UUID: CGFloat] = [:]
    var row: CGFloat = 0
}
