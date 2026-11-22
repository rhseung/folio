import FolioDomain
import Foundation

enum CourseTab: CaseIterable, Identifiable {
    case overview, classes, assignments, notes, materials, study, assessment
    var id: Self { self }

    // 풀기는 열의 항목이 아니라 문제나 계획에서 여는 화면이다.
    var pages: [AppLink.CoursePage] { AppLink.CoursePage.allCases.filter { $0.tab == self && $0 != .solve } }

    var title: String {
        switch self {
        case .overview: String(localized: .courseTabOverview)
        case .classes: String(localized: .courseTabClasses)
        case .assignments: String(localized: .courseTabAssignments)
        case .notes: String(localized: .courseTabNotes)
        case .materials: String(localized: .courseTabMaterials)
        case .study: String(localized: .courseTabStudy)
        case .assessment: String(localized: .courseTabAssessment)
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .classes: "calendar"
        case .assignments: "checklist"
        case .notes: "doc.text"
        case .materials: "folder"
        case .study: "book.closed"
        case .assessment: "graduationcap"
        }
    }
}
