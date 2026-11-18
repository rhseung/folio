import FolioDomain
import Foundation

extension AppLink.CoursePage: Identifiable {
    public var id: Self { self }

    var title: String {
        switch self {
        case .overview: String(localized: .courseSectionOverview)
        case .sessions: String(localized: .courseSectionSessions)
        case .units: String(localized: .courseSectionUnits)
        case .notes: String(localized: .courseSectionNotes)
        case .materials: String(localized: .courseSectionMaterials)
        case .quiz: String(localized: .courseSectionQuizSolve)
        case .cards: String(localized: .courseSectionQuizCards)
        case .stats: String(localized: .courseSectionQuizStats)
        case .problems: String(localized: .courseSectionQuizProblems)
        case .assignments: String(localized: .courseSectionAssignments)
        case .exams: String(localized: .courseSectionExams)
        case .grades: String(localized: .courseSectionGrades)
        }
    }

    var tab: CourseTab {
        switch self {
        case .overview: .overview
        case .sessions, .units: .classes
        case .notes: .notes
        case .materials: .materials
        case .quiz, .cards, .stats, .problems: .quiz
        case .assignments: .assignments
        case .exams, .grades: .assessment
        }
    }
}
