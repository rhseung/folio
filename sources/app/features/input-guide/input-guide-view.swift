import FolioDomain
import FolioMarkdown
import SwiftUI

extension EnvironmentValues {
    @Entry var showInputGuide: @MainActor (MathSyntax?) -> Void = { _ in }
}

extension FocusedValues {
    @Entry var showInputGuide: (@MainActor (MathSyntax?) -> Void)?
}
