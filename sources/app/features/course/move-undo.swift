import FolioActions
import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class MoveUndo {
    private(set) var batch: UUID?

    func keep(_ ran: ActionContext?) {
        if let batch = ran?.made { self.batch = batch }
    }

    // 되돌린 뒤 과목을 다시 추적해야 옮긴 파일의 항목이 파일을 따라 돌아온다.
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
