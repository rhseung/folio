import FolioDomain
import SwiftUI

extension View {
    func rolling(_ value: String) -> some View {
        contentTransition(.numericText()).animation(Theme.Motion.settle, value: value)
    }
}

extension Double {
    var oneDecimal: String { formatted(.number.precision(.fractionLength(1))) }
}
