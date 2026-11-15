import FolioDomain
import SwiftUI

struct PickOption<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    var detail: String?
    var section: String?
    var depth = 0
    var disabled = false
}
