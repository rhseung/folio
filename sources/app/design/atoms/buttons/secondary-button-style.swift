import FolioDomain
import SwiftUI

struct SecondaryButtonStyle: ButtonStyle {
    var strong = false
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        SecondaryButton(configuration: configuration, strong: strong, iconOnly: iconOnly)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: Self { .init() }
    static func secondary(strong: Bool = false, iconOnly: Bool = false) -> Self { .init(strong: strong, iconOnly: iconOnly) }
}
