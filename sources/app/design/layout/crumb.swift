import FolioDomain
import SwiftUI

struct Crumb {
    var title: String
    var symbol: String?
    var dot: Color?
    var action: (() -> Void)?
    var rename: (() -> Void)?
}
