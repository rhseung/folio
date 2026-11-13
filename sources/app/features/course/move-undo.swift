import FolioActions
import Foundation
import Observation
import SwiftUI

/// The last move a screen made (`material mv`, `note mv`, an approved cleanup), until its undo button takes it back
/// with `cleanup undo`. One for the materials page and one for the notes section, whose list and open note both move.
@MainActor @Observable
final class MoveUndo {
    private(set) var batch: UUID?

    func keep(_ ran: ActionContext?) {
        if let batch = ran?.made { self.batch = batch }
    }

    /// Asked first, as `cleanup undo` declares; the course is tracked again after, so a moved file's entry follows it back.
    func undo(_ workspace: Workspace, course: UUID, then done: @escaping @MainActor () -> Void = {}) -> PendingAction? {
        guard let batch else { return nil }
        return workspace.ask(CleanupUndo(batch: batch, course: course)) { [weak self] _ in
            self?.batch = nil
            done()
        }
    }
}

struct UndoMoveButton: View {
    let moves: MoveUndo
    let action: () -> Void

    var body: some View {
        if moves.batch != nil { Button(.commonUndoMove, action: action) }
    }
}
