import FolioActions
import FolioCore
import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class AddSemesterModel {
    let workspace: Workspace
    var year: Int
    var term: Term
    var start: Date
    var end: Date

    init(workspace: Workspace) {
        self.workspace = workspace
        let calendar = workspace.calendar
        let newest = workspace.semesters.first.map { (year: $0.year, term: $0.term) }
        let next = Term.next(after: newest, now: workspace.now, calendar: calendar)
        (year, term) = next
        start = workspace.now
        end = calendar.date(byAdding: .month, value: next.term.months, to: workspace.now) ?? workspace.now
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
