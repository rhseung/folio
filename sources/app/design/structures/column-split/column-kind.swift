import SwiftUI

enum ColumnKind: String, CaseIterable {
    case courseSections, settingsTabs, people, quizScope

    var holdsSections: Bool { self == .courseSections || self == .settingsTabs }
}
