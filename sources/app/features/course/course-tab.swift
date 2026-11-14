import Foundation

enum CourseTab: CaseIterable, Identifiable {
    case overview, classes, notes, materials, quiz, assessment
    var id: Self { self }

    var pages: [CourseSection] { CourseSection.allCases.filter { $0.tab == self } }

    var title: String {
        switch self {
        case .overview: String(localized: .courseTabOverview)
        case .classes: String(localized: .courseTabClasses)
        case .notes: String(localized: .courseTabNotes)
        case .materials: String(localized: .courseTabMaterials)
        case .quiz: String(localized: .courseTabQuiz)
        case .assessment: String(localized: .courseTabAssessment)
        }
    }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .classes: "calendar"
        case .notes: "doc.text"
        case .materials: "folder"
        case .quiz: "questionmark.square"
        case .assessment: "checklist"
        }
    }
}
