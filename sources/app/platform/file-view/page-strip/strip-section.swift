import FolioDomain
import SwiftUI

struct StripSection: Identifiable, Equatable {
    enum Kind: Equatable {
        case held
        case new
        case none

        var tinted: Bool { self != .none }
    }

    let id: UUID
    let pages: ClosedRange<Int>
    let title: String
    var kind: Kind = .held

    var label: String { Session.pagesLabel(pages) }
}
