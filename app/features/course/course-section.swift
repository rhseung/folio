import Foundation

enum CourseSection: CaseIterable, Identifiable {
    case overview, sessions, units, notes, materials
    case quizSolve, quizCards, quizStats, quizProblems
    case assignments, exams, grades
    var id: Self { self }

    var title: String {
        switch self {
        case .overview: String(localized: .courseSectionOverview)
        case .sessions: String(localized: .courseSectionSessions)
        case .units: String(localized: .courseSectionUnits)
        case .notes: String(localized: .courseSectionNotes)
        case .materials: String(localized: .courseSectionMaterials)
        case .quizSolve: String(localized: .courseSectionQuizSolve)
        case .quizCards: String(localized: .courseSectionQuizCards)
        case .quizStats: String(localized: .courseSectionQuizStats)
        case .quizProblems: String(localized: .courseSectionQuizProblems)
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
        case .quizSolve, .quizCards, .quizStats, .quizProblems: .quiz
        case .assignments, .exams, .grades: .assessment
        }
    }
}

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
