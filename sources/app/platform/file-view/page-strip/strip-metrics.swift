import SwiftUI

enum StripMetrics {
    #if os(iOS)
    static let header: CGFloat = Theme.Size.touchTarget
    #else
    static let header: CGFloat = Theme.Size.toolbarButton - Theme.Space.xs
    #endif
}
