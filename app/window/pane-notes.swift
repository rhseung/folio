import CryptoKit
import FolioDomain
import Foundation
import SwiftUI

struct PaneNotes: Equatable {
    let panes: TabPanes
    let pane: UUID

    // 행이 그릴 때마다 새 값을 넘기므로, identity로 비교해야 그 안의 모든 노트가 다시 그려지지 않는다.
    static func == (a: PaneNotes, b: PaneNotes) -> Bool { a.panes === b.panes && a.pane == b.pane }

    @MainActor func mode(of item: UUID) -> NoteViewMode? { panes.noteMode(of: item, pane: pane) }

    @MainActor func show(_ mode: NoteViewMode, of item: UUID) { panes.show(mode, of: item, pane: pane) }
}
