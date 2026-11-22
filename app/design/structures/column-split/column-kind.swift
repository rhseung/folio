import SwiftUI

enum ColumnKind: String, CaseIterable {
    case courseSections, settingsTabs, people, lms

    var holdsSections: Bool { self == .courseSections || self == .settingsTabs || self == .lms }
}
