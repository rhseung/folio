import FolioDomain
import SwiftUI

struct OutlineCommand {
    var shown: Bool
    var toggle: @MainActor () -> Void
}
