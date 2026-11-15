import FolioDomain
import SwiftUI

struct SelectOption<ID: Hashable>: Identifiable {
    let id: ID
    let label: String
    var detail: String?
    var section: String?
    var depth = 0
    var isDisabled = false
    var isFile = false
}
