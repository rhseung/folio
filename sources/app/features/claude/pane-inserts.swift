import FolioAI
import FolioDomain
import SwiftUI

@MainActor final class PaneInserts {
    private var boxes: [UUID: PaneInsert] = [:]

    subscript(pane: UUID) -> PaneInsert {
        if let box = boxes[pane] { return box }
        let box = PaneInsert()
        boxes[pane] = box
        return box
    }
}
