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
        if let newest = workspace.semesters.first {
            let i = Self.terms.firstIndex(of: newest.term) ?? 0
            (year, term) = i + 1 < Self.terms.count ? (newest.year, Self.terms[i + 1]) : (newest.year + 1, Self.terms[0])
        }
    }

    var exists: Bool { workspace.transcript.semesters.contains { $0.year == year && $0.term == term } }

    var note: String? {
        exists
            ? String(localized: .semesterAddExists)
            : SemesterFolder(year: year, term: term).map { String(localized: .semesterFolderNote($0.name)) }
    }

    func add() -> UUID? {
        let c = workspace.calendar
        return workspace.run(SemesterAdd(year: year, term: term, start: LocalDate(start, in: c), end: LocalDate(end, in: c)))?.made
    }
}
