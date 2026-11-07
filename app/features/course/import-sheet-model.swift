import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation
import PDFKit

/// The add sheet: one row per incoming file with where it lands, under what name, and for which class. Each row opens
/// on `MaterialIntake.guess`; menus change one row, or every selected row when the menu's row is among them.
@MainActor @Observable
final class ImportPlaceModel {
    let workspace: Workspace
    let course: LoadedCourse
    let places: [String]
    private(set) var rows: [Row]
    private(set) var selection: Set<Int> = []
    /// Where a ⇧ range starts and where ↑↓ move from.
    private var anchor = 0
    private var cursor = 0
    /// What each folder holds, read once: nothing else writes there while the sheet is open.
    private let held: [String: Set<String>]

    struct Row: Identifiable {
        let id: Int
        let url: URL
        let guess: IntakeGuess
        var folder: String
        var session: UUID?
    }

    struct Kind: Identifiable {
        var label: String
        var places: [String]
        var id: String { label }
        var isLecture: Bool { places == [CourseFolder.lectures.rawValue] }
        /// Assignments and exams name which one even when there is one, so the choice reads plainly.
        var perItem: Bool { places[0].contains("/") }
    }

    init(workspace: Workspace, course: LoadedCourse, files: [URL], places: [String]) {
        self.workspace = workspace
        self.course = course
        self.places = places
        let sessions = course.file.sessions
        rows = files.enumerated().map { i, url in
            let guess = MaterialIntake.guess(Self.incoming(url), places: places, sessions: sessions, exams: course.file.exams, now: workspace.now,
                                             settings: workspace.settings, calendar: workspace.calendar)
            return Row(id: i, url: url, guess: guess, folder: guess.folder, session: guess.session)
        }
        held = Dictionary(uniqueKeysWithValues: ([CourseFolder.lectures.rawValue] + places).map { ($0, course.store.names(in: $0)) })
    }

    /// The page count and shape `guess` reads. Files from outside the sandbox open only inside their scope.
    private static func incoming(_ url: URL) -> IncomingFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url), let first = pdf.page(at: 0) else {
            return IncomingFile(name: url.lastPathComponent)
        }
        let box = first.bounds(for: .mediaBox)
        // A page turned 90° shows its long side across, whatever its box says.
        let turned = first.rotation % 180 != 0
        return IncomingFile(name: url.lastPathComponent, pages: pdf.pageCount, landscape: (box.width > box.height) != turned)
    }

    var many: Bool { rows.count > 1 }

    var title: String {
        String(localized: many ? .materialsImportMany(rows.count) : .materialsImportOne(rows[0].url.lastPathComponent))
    }

    var confirmTitle: String { String(localized: many ? .materialsImportConfirmMany(rows.count) : .materialsImportConfirm) }

    var hint: String { String(localized: many ? .materialsImportKeys : .materialsImportNote) }

    // MARK: Kinds and sessions

    /// Places by kind label, in the order first met: `과제` → `Assignments/HW00`, `Assignments/HW01`, … The order is also
    /// the number key for each.
    var kinds: [Kind] {
        var result: [Kind] = []
        for p in [CourseFolder.lectures.rawValue] + places {
            let label = MaterialRole(path: p + "/_")?.label ?? p
            if let i = result.firstIndex(where: { $0.label == label }) { result[i].places.append(p) } else { result.append(Kind(label: label, places: [p])) }
        }
        return result
    }

    func kind(of row: Row) -> Kind? { kinds.first { $0.places.contains(row.folder) } }

    func isLecture(_ row: Row) -> Bool { row.folder == CourseFolder.lectures.rawValue }

    func kindLabel(_ row: Row) -> String {
        guard let kind = kind(of: row) else { return row.folder }
        return kind.perItem ? "\(kind.label) \((row.folder as NSString).lastPathComponent)" : kind.label
    }

    /// Newest first: a file is almost always for a recent class.
    var sessions: [Session] { course.file.sessions.filter { !$0.isCancelled }.sorted(by: Session.inOrder).reversed() }

    func sessionTitle(_ s: Session) -> String { course.file.title(of: s, calendar: workspace.calendar) }

    /// `11/6(목) · 오늘` for today's class, which is the one a file is most often for; any other by its title.
    func sessionLabel(_ row: Row) -> String {
        guard let s = row.session.flatMap({ id in sessions.first { $0.id == id } }) else { return String(localized: .materialsImportNoSession) }
        return workspace.isStudyToday(s.date) ? String(localized: .materialsImportToday(course.file.day(of: s, calendar: workspace.calendar))) : sessionTitle(s)
    }

    func sessionNote(_ s: Session) -> String? {
        if workspace.isStudyToday(s.date) { return String(localized: .materialsImportTodayNote) }
        return s.date > workspace.now ? String(localized: .materialsImportUpcoming) : nil
    }

    /// The ✦ reasons: only while the row still holds what was guessed.
    func kindWhy(_ row: Row) -> String? {
        guard row.folder == row.guess.folder, let why = row.guess.why else { return nil }
        return String(localized: .materialsImportGuessed(why.text))
    }

    func sessionWhy(_ row: Row) -> String? {
        guard isLecture(row), row.session == row.guess.session, let why = row.guess.sessionWhy else { return nil }
        return String(localized: .materialsImportGuessed(why.text))
    }

    // MARK: Destinations

    /// Each row's folder and final name, planned together so two files of one name don't both claim it.
    var placements: [MaterialIntake.Placement] {
        MaterialIntake.plan(rows.map { row in (row.url.lastPathComponent, row.folder, isLecture(row) ? session(row) : nil) },
                            taken: { self.held[$0] ?? [] })
    }

    private func session(_ row: Row) -> Session? { row.session.flatMap { id in course.file.sessions.first { $0.id == id } } }

    /// Why the name differs from the file's own, for the destination's tooltip.
    func nameNote(_ p: MaterialIntake.Placement) -> String? {
        if let suffix = p.suffix { return String(localized: .materialsImportNumbered(suffix.trimmingCharacters(in: .whitespaces))) }
        if let prefix = p.prefix { return String(localized: .materialsImportWeekPrefix(prefix)) }
        return nil
    }

    // MARK: Changing rows

    /// The rows a menu on `row` changes: every selected row when it is one of several selected, else that row alone.
    func targets(_ row: Row) -> [Int] { selection.contains(row.id) && selection.count > 1 ? selection.sorted() : [row.id] }

    /// A kind with several folders keeps a row's folder when it is already one of them, else takes the newest: the latest
    /// assignment or exam is the likely one. A row turned into a lecture takes its guessed class, or the latest.
    func setFolder(_ folder: String, for ids: [Int]) {
        for i in ids {
            rows[i].folder = folder
            if isLecture(rows[i]), rows[i].session == nil { rows[i].session = rows[i].guess.session ?? defaultSession }
        }
    }

    func setKind(_ kind: Kind, for ids: [Int]) {
        for i in ids { setFolder(kind.places.contains(rows[i].folder) ? rows[i].folder : kind.places.last!, for: [i]) }
    }

    func setSession(_ session: UUID?, for ids: [Int]) {
        for i in ids where isLecture(rows[i]) { rows[i].session = session }
    }

    private var defaultSession: UUID? {
        MaterialIntake.guess(IncomingFile(name: ""), places: [], sessions: course.file.sessions, now: workspace.now,
                             settings: workspace.settings, calendar: workspace.calendar).session
    }

    // MARK: Selecting

    /// A click: alone it picks the row, ⇧ widens from the last pick, ⌘ adds or takes away one row.
    func click(_ id: Int, extend: Bool = false, toggle: Bool = false) {
        guard many else { return }
        if toggle {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            anchor = id
        } else if extend {
            selection = Set(min(anchor, id)...max(anchor, id))
        } else {
            selection = [id]
            anchor = id
        }
        cursor = id
    }

    /// ↑↓: the next row, or with ⇧ the range from the anchor to it.
    func step(_ by: Int, extend: Bool) {
        guard many else { return }
        let next = selection.isEmpty ? (by > 0 ? 0 : rows.count - 1) : min(max(cursor + by, 0), rows.count - 1)
        if extend && !selection.isEmpty { click(next, extend: true) } else { click(next) }
    }

    /// 1–9: the kind of that number for the selected rows, or for the only row.
    @discardableResult
    func applyKind(number: Int) -> Bool {
        let kinds = kinds
        let ids = many ? selection.sorted() : [0]
        guard kinds.indices.contains(number - 1), !ids.isEmpty else { return false }
        setKind(kinds[number - 1], for: ids)
        return true
    }

    func confirm() {
        workspace.importFiles(rows.map { ($0.url, $0.folder, isLecture($0) ? $0.session : nil) }, course: course.id)
    }
}
