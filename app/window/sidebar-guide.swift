import FolioDomain
import SwiftUI

enum SidebarGuide {
    case stem, course, lastCourse

    static let indent = Theme.Space.xl
    static var reach: CGFloat { indent - SidebarLabelStyle.gap - Theme.Size.tile / 2 }
}
