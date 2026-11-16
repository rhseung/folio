import FolioDomain
import SwiftUI

extension FocusedValues {
    @Entry var navigator: Navigator?
    @Entry var openPlace: (@MainActor (AppLink) -> Void)?
}
