import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class AddSemesterModel {
    let workspace: Workspace
    var year = Calendar.current.component(.year, from: .now)
    var term: Term = .fall
    var start = Date.now
    var end = Calendar.current.date(byAdding: .month, value: 4, to: .now) ?? .now

    static let terms: [Term] = [.spring, .summer, .fall, .winter]

    init(workspace: Workspace) {
        self.workspace = workspace
        // Opens on the term after the newest one, which is the one usually being added.
        if let newest = workspace.semesters.first {
            let i = Self.terms.firstIndex(of: newest.term) ?? 0
            (year, term) = i + 1 < Self.terms.count ? (newest.year, Self.terms[i + 1]) : (newest.year + 1, Self.terms[0])
        }
    }

    var exists: Bool { workspace.transcript.semesters.contains { $0.year == year && $0.term == term } }

    var note: String? {
        exists ? String(localized: .semesterAddExists) : SemesterFolder(year: year, term: term).map { String(localized: .semesterFolderNote($0.name)) }
    }

    func add() -> UUID? {
        let c = workspace.calendar
        return workspace.run(SemesterAdd(year: year, term: term, start: LocalDate(start, in: c), end: LocalDate(end, in: c)))?.made
    }
}

@MainActor @Observable
final class AddCourseModel {
    let workspace: Workspace
    let semester: Semester
    var title = ""
    var codeId: UUID?
    var number = ""
    var credits: Double? = 3
    var mode: GradingMode = .relative

    init(workspace: Workspace, semester: Semester) {
        self.workspace = workspace
        self.semester = semester
    }

    var codes: [CourseCode] { workspace.catalog.codes.sorted { $0.prefix < $1.prefix } }

    var folder: String? {
        let prefix = codes.first { $0.id == codeId }?.prefix ?? ""
        return StandardLayout.courseFolderName(prefix: prefix, number: number, title: title)
    }

    var disabled: Bool { folder == nil || codeId == nil || (credits ?? -1) < 0 }

    var note: String { folder.map { String(localized: .semesterFolderNote($0)) } ?? String(localized: .semesterAddCourseHint) }

    func add() -> UUID? {
        guard let codeId, let credits else { return nil }
        return workspace.run(CourseAdd(semester: semester.id, title: title, code: codeId, number: number, credits: credits, mode: mode))?.made
    }
}
