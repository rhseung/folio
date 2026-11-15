import FolioDomain
import SwiftUI

struct SoftButtonStyle: ButtonStyle {
    var strong = false
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        SoftButton(configuration: configuration, strong: strong, iconOnly: iconOnly)
    }
}
