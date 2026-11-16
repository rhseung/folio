import FolioActions
import Foundation
import Observation
import SwiftUI

struct UndoMoveButton: View {
    let moves: MoveUndo
    let action: () -> Void

    var body: some View {
        if moves.batch != nil { Button(.commonUndoMove, action: action) }
    }
}
