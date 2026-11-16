import SwiftUI

struct ColumnFit: Equatable {
    var roomy: Bool
    var collapsed: Bool
    var nothingBeside = false

    init(roomy: Bool, collapsed: Bool, fold: ColumnFold = .sections) {
        self.roomy = roomy
        self.collapsed = collapsed
        if case .list(false) = fold { nothingBeside = true }
    }

    var docked: Bool { roomy && !collapsed }
    var listAlone: Bool { !roomy && nothingBeside }
    var showsPage: Bool { !listAlone }

    enum Show: Equatable { case dock, overlay }
    var show: Show { roomy ? .dock : .overlay }
}
