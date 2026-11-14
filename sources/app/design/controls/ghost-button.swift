import SwiftUI

extension ButtonStyle where Self == ToolbarButtonStyle {
    static var toolbar: ToolbarButtonStyle { .init() }
}

extension ButtonStyle where Self == GhostButtonStyle {
    static var ghost: GhostButtonStyle { .init() }
    static var ghostIcon: GhostButtonStyle { .init(iconOnly: true) }
}
