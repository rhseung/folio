import SwiftUI

struct ColumnCommand {
    var kind: ColumnKind
    var shown: Bool
    var toggle: @MainActor () -> Void
}
