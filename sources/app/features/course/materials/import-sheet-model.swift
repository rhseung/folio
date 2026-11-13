import FolioAI
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation
import PDFKit

@MainActor @Observable
final class ImportPlaceModel {
    indirect enum Sections: Equatable {
        case reading(done: Int, total: Int)
        case proposed(LectureSplit, source: LectureSource?)
        case nothing(pageCount: Int)
        case later(Sections)
    }

    typealias Find = @MainActor (URL, [FolioDomain.Unit], @escaping @MainActor (Int, Int) -> Void) async -> LectureFinding

    let workspace: Workspace
    let course: LoadedCourse
    let places: [String]
    private(set) var rows: [Row]
    private(set) var selection: Set<Int> = []
    private var anchor = 0
    private var cursor = 0
    private let held: [String: Set<String>]
    private(set) var sections: [Int: Sections] = [:]
    private(set) var opened: Set<Int> = []
    private let find: Find
    @ObservationIgnored private var reads: [Int: Task<Void, Never>] = [:]
    private(set) var asking: Set<Int> = []
    private(set) var claudeFailures: [Int: String] = [:]
    @ObservationIgnored private let claude: LectureClaude
    @ObservationIgnored private var asks: [Int: Task<Void, Never>] = [:]

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
        var perItem: Bool { places[0].contains("/") }
    }

    init(workspace: Workspace, course: LoadedCourse, files: [URL], places: [String], find: Find? = nil, claude: LectureClaude? = nil) {
        self.workspace = workspace
        self.course = course
        self.places = places
        let client = workspace.claudeReady ? workspace.claude(for: course) : nil
        self.find = find ?? { url, units, progress in await LectureReader.find(url, units: units, claude: client, progress: progress) }
        self.claude = claude ?? LectureClaude.of(workspace, course: course)
        let sessions = course.file.sessions
        rows = files.enumerated().map { i, url in
            let guess = MaterialIntake.guess(
                Self.incoming(url), places: places, sessions: sessions, exams: course.file.exams, now: workspace.now,
                settings: workspace.settings, calendar: workspace.calendar)
            return Row(id: i, url: url, guess: guess, folder: guess.folder, session: guess.session)
        }
        held = Dictionary(uniqueKeysWithValues: ([CourseFolder.lectures.rawValue] + places).map { ($0, course.store.names(in: $0)) })
        if files.count == 1 { opened = [0] }
        for row in rows { readSections(row.id) }
    }

    isolated deinit {
        for task in reads.values { task.cancel() }
        for task in asks.values { task.cancel() }
    }

    // 샌드박스 밖의 파일은 그 scope 안에서만 열린다.
    private static func incoming(_ url: URL) -> IncomingFile {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url), let first = pdf.page(at: 0) else {
            return IncomingFile(name: url.lastPathComponent)
        }
        let box = first.bounds(for: .mediaBox)
        // 90도 돌린 쪽은 box와 상관없이 긴 변이 가로로 보인다.
        let turned = first.rotation % 180 != 0
        return IncomingFile(name: url.lastPathComponent, pages: pdf.pageCount, landscape: (box.width > box.height) != turned)
    }

    var many: Bool { rows.count > 1 }

    var title: String {
        String(localized: many ? .materialsImportMany(rows.count) : .materialsImportOne(rows[0].url.lastPathComponent))
    }

    var confirmTitle: String { String(localized: many ? .materialsImportConfirmMany(rows.count) : .materialsImportConfirm) }

    var hint: String? {
        guard many else { return String(localized: .materialsImportNote) }
        #if os(macOS)
        return String(localized: .materialsImportKeys)
        #else
        return nil
        #endif
    }

    // MARK: Kinds and sessions

    var kinds: [Kind] {
        var result: [Kind] = []
        for p in [CourseFolder.lectures.rawValue] + places {
            let label = MaterialRole(path: p + "/_")?.label ?? p
            if let i = result.firstIndex(where: { $0.label == label }) {
                result[i].places.append(p)
            } else {
                result.append(Kind(label: label, places: [p]))
            }
        }
        return result
    }

    func kind(of row: Row) -> Kind? { kinds.first { $0.places.contains(row.folder) } }

    func isLecture(_ row: Row) -> Bool { row.folder == CourseFolder.lectures.rawValue }

    func kindLabel(_ row: Row) -> String {
        guard let kind = kind(of: row) else { return row.folder }
        return kind.perItem ? "\(kind.label) \((row.folder as NSString).lastPathComponent)" : kind.label
    }

    var sessions: [Session] { course.file.sessions.filter { !$0.isCancelled }.sorted(by: Session.inOrder).reversed() }

    func sessionTitle(_ s: Session) -> String { course.file.title(of: s, calendar: workspace.calendar) }

    func sessionLabel(_ row: Row) -> String {
        guard let s = row.session.flatMap({ id in sessions.first { $0.id == id } }) else {
            return String(localized: .materialsImportNoSession)
        }
        return workspace.isStudyToday(s.date)
            ? String(localized: .materialsImportToday(course.file.day(of: s, calendar: workspace.calendar))) : sessionTitle(s)
    }

    func sessionNote(_ s: Session) -> String? {
        if workspace.isStudyToday(s.date) { return String(localized: .materialsImportTodayNote) }
        return s.date > workspace.now ? String(localized: .materialsImportUpcoming) : nil
    }

    func kindWhy(_ row: Row) -> String? {
        guard row.folder == row.guess.folder, let why = row.guess.why else { return nil }
        return String(localized: .materialsImportGuessed(why.text))
    }

    func sessionWhy(_ row: Row) -> String? {
        guard isLecture(row), row.session == row.guess.session, let why = row.guess.sessionWhy else { return nil }
        return String(localized: .materialsImportGuessed(why.text))
    }

    // MARK: Destinations

    // 같은 이름의 두 파일이 한 이름을 함께 차지하지 않도록 모든 행을 함께 계획한다.
    var placements: [MaterialIntake.Placement] {
        MaterialIntake.plan(
            rows.map { row in (row.url.lastPathComponent, row.folder, isLecture(row) ? session(row) : nil) },
            taken: { self.held[$0] ?? [] })
    }

    private func session(_ row: Row) -> Session? { row.session.flatMap { id in course.file.sessions.first { $0.id == id } } }

    func nameNote(_ p: MaterialIntake.Placement) -> String? {
        if let suffix = p.suffix { return String(localized: .materialsImportNumbered(suffix.trimmingCharacters(in: .whitespaces))) }
        if let prefix = p.prefix { return String(localized: .materialsImportWeekPrefix(prefix)) }
        return nil
    }

    // MARK: Changing rows

    func targets(_ row: Row) -> [Int] { selection.contains(row.id) && selection.count > 1 ? selection.sorted() : [row.id] }

    func setFolder(_ folder: String, for ids: [Int]) {
        for i in ids {
            rows[i].folder = folder
            if isLecture(rows[i]), rows[i].session == nil { rows[i].session = rows[i].guess.session ?? defaultSession }
            readSections(i)
        }
    }

    func setKind(_ kind: Kind, for ids: [Int]) {
        for i in ids { setFolder(kind.places.contains(rows[i].folder) ? rows[i].folder : kind.places.last!, for: [i]) }
    }

    func setSession(_ session: UUID?, for ids: [Int]) {
        for i in ids where isLecture(rows[i]) { rows[i].session = session }
    }

    private var defaultSession: UUID? {
        MaterialIntake.guess(
            IncomingFile(name: ""), places: [], sessions: course.file.sessions, now: workspace.now,
            settings: workspace.settings, calendar: workspace.calendar
        ).session
    }

    // MARK: Selecting

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

    private(set) var picking = false

    func hold(_ id: Int) {
        guard many else { return }
        click(id)
        picking = true
    }

    func press(_ id: Int, _ press: PickPress) {
        click(id, extend: press == .range, toggle: press == .toggle)
        if selection.isEmpty { picking = false }
    }

    func step(_ by: Int, extend: Bool) {
        guard many else { return }
        let next = selection.isEmpty ? (by > 0 ? 0 : rows.count - 1) : min(max(cursor + by, 0), rows.count - 1)
        if extend && !selection.isEmpty { click(next, extend: true) } else { click(next) }
    }

    @discardableResult
    func applyKind(number: Int) -> Bool {
        let kinds = kinds
        let ids = many ? selection.sorted() : [0]
        guard kinds.indices.contains(number - 1), !ids.isEmpty else { return false }
        setKind(kinds[number - 1], for: ids)
        return true
    }

    // MARK: Sections

    private func readSections(_ id: Int) {
        let row = rows[id]
        guard isLecture(row), sections[id] == nil, reads[id] == nil, row.url.pathExtension.lowercased() == "pdf" else { return }

        sections[id] = .reading(done: 0, total: 0)
        let units = course.file.units
        reads[id] = Task { [weak self, find] in
            let found = await find(row.url, units) { done, total in
                guard let self, case .reading = self.sections[id] else { return }
                self.sections[id] = .reading(done: done, total: total)
            }
            guard let self, !Task.isCancelled else { return }

            switch found {
            case .found(let split, let source): self.sections[id] = .proposed(split, source: source)
            case .nothing(let count): self.sections[id] = .nothing(pageCount: count)
            case .failed(let why, let count):
                self.sections[id] = .nothing(pageCount: count)
                self.claudeFailures[id] = why
            case .unreadable: self.sections[id] = nil
            }
            self.reads[id] = nil
        }
    }

    func sections(of row: Row) -> Sections? { isLecture(row) ? sections[row.id] : nil }

    func toggleOpen(_ id: Int) {
        if opened.contains(id) { opened.remove(id) } else { opened.insert(id) }
    }

    func edit(_ id: Int) -> LectureSplit? {
        if case .proposed(let split, _) = sections[id] { return split }
        return nil
    }

    func setSplit(_ split: LectureSplit, of id: Int) {
        guard case .proposed(_, let source) = sections[id] else { return }
        sections[id] = .proposed(split, source: source)
    }

    func splitByHand(_ id: Int) {
        guard case .nothing(let count) = sections[id] else { return }
        sections[id] = .proposed(LectureSplit(pageCount: count), source: nil)
        opened.insert(id)
        claudeFailures[id] = nil
    }

    func later(_ id: Int) {
        switch sections[id] {
        case .proposed?, .nothing?: sections[id] = .later(sections[id]!)
        default: break
        }
        claudeFailures[id] = nil
    }

    func takeBack(_ id: Int) {
        guard case .later(let kept) = sections[id] else { return }
        sections[id] = kept
        opened.insert(id)
    }

    // MARK: Claude (#450)

    private var claudeOn: Bool { claude.off() == nil }

    func canRetryClaude(_ id: Int) -> Bool {
        guard !asking.contains(id), claudeFailures[id] != nil, case .nothing? = sections[id] else { return false }
        return true
    }

    func showsRetry(_ id: Int) -> Bool { asking.contains(id) || canRetryClaude(id) }

    func retryClaude(_ id: Int) {
        guard canRetryClaude(id), isLecture(rows[id]) else { return }
        let url = rows[id].url, units = course.file.units
        asking.insert(id)
        claudeFailures[id] = nil
        asks[id] = Task { [weak self, claude] in
            let found = await claude.ask(url, units)
            guard let self, !Task.isCancelled else { return }
            self.asking.remove(id)
            self.asks[id] = nil
            if case .nothing? = self.sections[id] { self.take(found, for: id) }
        }
    }

    private func take(_ found: ClaudeFinding, for id: Int) {
        if case .found(let split) = found {
            sections[id] = .proposed(split, source: .claude)
            opened.insert(id)
        } else {
            claudeFailures[id] = found.message
        }
    }

    func sectionsLine(_ row: Row) -> String? {
        if asking.contains(row.id), isLecture(row) { return String(localized: .lectureClaudeReading) }
        switch sections(of: row) {
        case .reading(let done, let total) where total > 0 && done == total && claudeOn:
            return String(localized: .lectureClaudeReading)
        case .reading(let done, let total):
            return total == 0
                ? String(localized: .materialsImportSectionsReading) : String(localized: .materialsImportSectionsReadingPages(done, total))
        case .proposed(let split, let source):
            let count = String(localized: .materialsImportSectionsCount(split.claimed))
            guard let source else { return count }
            let from =
                switch source {
                case .outline: String(localized: .materialsImportSectionsFromOutline)
                case .titles: String(localized: .materialsImportSectionsFromTitles)
                case .claude: String(localized: .materialsImportSectionsFromClaude)
                }
            return "\(count) · \(from)"
        case .nothing: return claudeFailures[row.id] ?? String(localized: .materialsImportSectionsNone)
        case .later: return String(localized: .materialsImportSectionsLater)
        case nil: return nil
        }
    }

    #if DEBUG
    func show(_ state: Sections, for id: Int) {
        reads[id]?.cancel()
        reads[id] = nil
        sections[id] = state
    }
    #endif

    func cuts(_ row: Row) -> [LectureCut]? {
        guard case .proposed(let split, _)? = sections(of: row) else { return nil }
        let cuts = split.cuts
        return cuts.isEmpty ? nil : cuts
    }

    func confirm() {
        for task in reads.values { task.cancel() }
        for task in asks.values { task.cancel() }
        workspace.importFiles(rows.map { ($0.url, $0.folder, isLecture($0) ? $0.session : nil, cuts($0)) }, course: course.id)
    }
}
