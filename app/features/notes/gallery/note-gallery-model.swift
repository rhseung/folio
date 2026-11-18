import FolioActions
import FolioCore
import FolioDomain
import FolioIndex
import FolioMarkdown
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class NoteGalleryModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    let moves: MoveUndo
    private(set) var notes: [NoteFile] = []
    private(set) var folders: [String] = []
    private var dates: [URL: (created: Date, modified: Date)] = [:]
    private(set) var previews: [URL: String] = [:]
    var adding = false
    var pending: PendingAction?
    var searching = false { didSet { if !searching { query = "" } } }
    var query = "" { didSet { if query != oldValue { find() } } }
    private var found: Set<UUID> = []
    @ObservationIgnored private var finding: Task<Void, Never>?
    @ObservationIgnored private var reading: Task<Void, Never>?
    @ObservationIgnored private var index: SearchStore?
    var width: CGFloat = 0
    private var prefs: Prefs { didSet { save() } }
    @ObservationIgnored private let defaults: UserDefaults?

    // 이보다 좁으면 도구 줄을 한 줄로 줄이고 카드를 작게 둔다. 세그먼트, 캡슐 둘, 돋보기가 한 줄에 들어가는 폭이다.
    static let wideFrom: CGFloat = 560

    init(
        workspace: Workspace, course: LoadedCourse, moves: MoveUndo = MoveUndo(), defaults: UserDefaults? = NoteGalleryModel.sharedDefaults
    ) {
        self.workspace = workspace
        initial = course
        self.moves = moves
        self.defaults = defaults
        prefs = (defaults?.data(forKey: Self.key(course.id))).flatMap { try? JSONDecoder().decode(Prefs.self, from: $0) } ?? Prefs()
    }

    static var sharedDefaults: UserDefaults? { LocalFolders.isolatesDefaults() ? nil : .standard }
    static func key(_ course: UUID) -> String { "noteGallery.\(course.uuidString)" }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var notesRevision: Int { workspace.notesRevision }
    var compact: Bool { width < Self.wideFrom }

    // MARK: 고르기

    struct Prefs: Codable, Equatable {
        var kind: NoteGroup?
        var sort = NoteSort.modified
        var groupings: [String: NoteGrouping] = [:]
        // 처음 상태에서 바꾼 묶음이다. 종류와 묶기마다 따로 둔다.
        var flipped: [String: Set<String>] = [:]
    }

    var kind: NoteGroup? {
        get { prefs.kind }
        set { prefs.kind = newValue }
    }

    var sort: NoteSort {
        get { prefs.sort }
        set { prefs.sort = newValue }
    }

    var grouping: NoteGrouping {
        get {
            let options = NoteGrouping.options(for: kind)
            return prefs.groupings[Self.name(kind)].flatMap { options.contains($0) ? $0 : nil } ?? options[0]
        }
        set { prefs.groupings[Self.name(kind)] = newValue }
    }

    private static func name(_ kind: NoteGroup?) -> String { kind.map { "\($0)" } ?? "all" }
    private var foldKey: String { "\(Self.name(kind))/\(grouping.rawValue)" }

    var kindOptions: [(NoteGroup?, String)] {
        [(NoteGroup?.none, String(localized: .notesFilterAll))]
            + [NoteGroup.classes, .units, .exams, .free].map { (Optional($0), $0.segment) }
    }
    var sorts: [NoteSort] { NoteSort.allCases }
    var groupings: [NoteGrouping] { NoteGrouping.options(for: kind) }
    var choosesGrouping: Bool { groupings.count > 1 }
    var sortOptions: [(NoteSort, String)] { sorts.map { ($0, $0.label) } }
    var groupingOptions: [(NoteGrouping, String)] { groupings.map { ($0, $0.label) } }

    // MARK: 목록

    func reload() {
        let store = course.store
        notes = store.notes(in: course.file)
        folders = store.noteFolders()
        let created = Dictionary(course.file.notes.map { ($0.id, $0.createdAt) }, uniquingKeysWith: { a, _ in a })
        dates = Dictionary(
            notes.map { note in
                let values = try? note.url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                let made = note.meta.id.flatMap { created[$0] } ?? values?.creationDate ?? .distantPast
                return (note.url, (created: made, modified: values?.contentModificationDate ?? made))
            }, uniquingKeysWith: { a, _ in a })
        readPreviews()
    }

    // 본문을 모두 읽어야 하므로 main actor 밖에서 읽는다. iCloud 파일은 읽기를 조정하느라 늦을 수 있다.
    // 앞선 읽기가 늦게 끝나 고치기 전 본문으로 덮어쓰지 않게, 새 읽기 전에 취소하고 취소된 결과는 버린다.
    private func readPreviews() {
        reading?.cancel()
        let (notes, store) = (notes, course.store)
        reading = Task { [weak self] in
            let read = await Task.detached {
                Dictionary(
                    notes.map { note in
                        let text = (try? store.read(note)) ?? ""
                        return (note.url, NoteExcerpt.text(of: text, tex: note.format == .tex))
                    }, uniquingKeysWith: { a, _ in a })
            }.value
            if !Task.isCancelled { self?.previews = read }
        }
    }

    var items: [NoteGallery.Item] {
        let store = course.store
        return notes.map { note in
            let date = dates[note.url] ?? (created: .distantPast, modified: .distantPast)
            // `notePath`는 과목 폴더 기준이라 맨 앞이 Notes다.
            let folder = store.notePath(of: note.url).split(separator: "/").dropFirst().dropLast().joined(separator: "/")
            return NoteGallery.Item(
                url: note.url, title: note.title, meta: note.meta, folder: folder, created: date.created, modified: date.modified)
        }
    }

    var shown: [NoteGallery.Item] {
        let all = items.filter { kind == nil || NoteGroup($0.meta.kind) == kind }
        guard isSearching else { return all }
        return all.filter { item in
            item.meta.id.map { found.contains($0) } == true
                || item.title.localizedStandardContains(query.trimmingCharacters(in: .whitespaces))
        }
    }

    var isSearching: Bool { searching && !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var sections: [NoteGallery.Section] {
        NoteGallery.sections(
            shown, grouping: isSearching ? .none : grouping, sort: sort, in: course.file, now: workspace.now, settings: workspace.settings,
            calendar: workspace.calendar)
    }

    func note(_ item: NoteGallery.Item) -> NoteFile? { notes.first { $0.url == item.url } }

    var subtitle: String { String(localized: .notesGalleryCount(notes.count)) }

    var emptyTitle: String {
        if isSearching { return String(localized: .notesGalleryNoMatch) }
        return kind.map { String(localized: .notesKindEmpty($0.segment)) } ?? String(localized: .notesGalleryEmpty)
    }

    // MARK: 접기

    func isOpen(_ section: NoteGallery.Section) -> Bool {
        isSearching || section.heading == nil || section.opensFirst != (prefs.flipped[foldKey]?.contains(section.id) ?? false)
    }

    func toggle(_ section: NoteGallery.Section) {
        prefs.flipped[foldKey, default: []].formSymmetricDifference([section.id])
    }

    func setAll(open: Bool) {
        prefs.flipped[foldKey] = Set(sections.filter { $0.opensFirst != open }.map(\.id))
    }

    // MARK: 묶음 머리와 카드

    func title(_ heading: NoteGallery.Heading) -> String {
        let file = course.file
        switch heading {
        case .thisWeek: return String(localized: .notesGalleryThisWeek)
        case .lastWeek: return String(localized: .notesGalleryLastWeek)
        case .twoWeeksAgo: return String(localized: .notesGalleryTwoWeeksAgo)
        case .month(let year, let month):
            let thisYear = LocalDate(workspace.now, in: workspace.calendar).year
            return year == thisYear
                ? String(localized: .notesGalleryMonth(month)) : String(localized: .notesGalleryYearMonth(String(year), month))
        case .week(let n): return String(localized: .notesGalleryWeek(n))
        case .noSession: return String(localized: .notesNoSession)
        case .unit(let id): return file.units.first { $0.id == id }?.title ?? String(localized: .notesNoUnits)
        case .noUnit: return String(localized: .notesNoUnits)
        case .exam(let id): return file.exams.first { $0.id == id }?.title ?? String(localized: .notesNoExam)
        case .noExam: return String(localized: .notesNoExam)
        case .kind(let group): return group.title
        case .folder(let folder): return folder.isEmpty ? CourseFolder.notes.rawValue : folder
        case .tag(let tag): return "#" + tag
        case .noTag: return String(localized: .notesGalleryNoTag)
        }
    }

    func detail(_ section: NoteGallery.Section) -> String? {
        if let span = section.span {
            let day = { (d: LocalDate) in "\(d.month)/\(d.day)" }
            return "\(day(span.lowerBound)) – \(day(span.upperBound))"  // strings: data, 날짜 범위는 숫자와 기호만이다
        }
        return section.scope.map { String(localized: .notesGalleryScope($0.title)) }
    }

    struct CardText {
        let kind: String
        let tex: Bool
        let title: String
        let preview: String
        let context: String?
        let when: String
    }

    func card(_ item: NoteGallery.Item) -> CardText {
        let file = course.file
        let calendar = workspace.calendar
        let facets = NoteFacets(of: item.meta, in: file, grouping: isSearching ? .none : grouping)
        var parts: [String] = []
        if !facets.sessions.isEmpty {
            parts.append(
                facets.sessions.count > 2
                    ? file.sessionSpan(of: item.meta.id, calendar: calendar) ?? ""
                    : facets.sessions.map { file.day(of: $0, calendar: calendar) }.joined(separator: ", "))
        }
        if !facets.units.isEmpty { parts.append(facets.units.map(\.title).joined(separator: ", ")) }
        if let exam = facets.exam {
            parts.append(exam.start.map { "\(exam.title) · \(CourseFile.day($0, calendar: calendar))" } ?? exam.title)
        }
        if !facets.tags.isEmpty { parts.append(facets.tags.map { "#" + $0 }.joined(separator: " ")) }

        let kindLabel =
            kind == nil && NoteGroup(item.meta.kind) == .classes
            ? String(localized: .notesGalleryClassKind(item.meta.kind.label)) : item.meta.kind.label
        return CardText(
            kind: kindLabel, tex: NoteFormat(path: item.url.path) == .tex, title: item.title, preview: previews[item.url] ?? "",
            context: parts.filter { !$0.isEmpty }.joined(separator: " · ").nilIfEmpty,
            when: when(sort == .created ? item.created : item.modified))
    }

    // 시각은 오늘과 어제에만 붙인다. 그보다 먼 날에 시각까지 쓰면 좁은 카드의 아래 줄에 들어가지 않는다.
    func when(_ date: Date) -> String {
        let (settings, calendar, now) = (workspace.settings, workspace.calendar, workspace.now)
        guard date != .distantPast else { return "" }
        let recent = (-1...0).contains(DateTimeText.days(date, from: now, settings: settings, calendar: calendar))
        return DateTimeText.text(date, from: now, time: recent, settings: settings, calendar: calendar)
    }

    // MARK: 복습 노트 없는 수업

    var missingReviews: [Session] {
        let file = course.file, now = workspace.now
        return file.heldSessions(at: now).filter { file.needsReviewNote($0, at: now) }.sorted { $0.date > $1.date }
    }

    func sessionTitle(_ session: Session) -> String { course.file.title(of: session, calendar: workspace.calendar) }

    func makeReviewNote(_ session: Session) -> UUID? {
        let id = workspace.note(.review, of: session.id, in: course.id)
        reload()
        return id
    }

    // MARK: 동작

    var newKind: NoteKind {
        switch kind {
        case .classes: .rough
        case .units: .unit
        case .exams: .examSummary
        case .free, nil: .free
        }
    }

    func open(_ note: NoteFile) -> UUID? {
        if let id = note.meta.id { return id }
        guard let id = workspace.noteId(of: note, in: course) else { return nil }
        reload()
        return id
    }

    func undoMove() {
        pending = moves.undo(workspace, course: course.id) { [weak self] in self?.reload() }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        defaults?.set(data, forKey: Self.key(initial.id))
    }

    // 제목과 본문은 앱의 검색 색인(`FolioIndex`)에서 찾는다. 색인에 ID가 없는 노트도 제목으로는 걸린다.
    private func find() {
        finding?.cancel()
        let words = query.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty, let gist = workspace.gist else {
            found = []
            return
        }
        if index == nil { index = try? SearchStore.local(for: gist) }
        guard let index else { return }
        let courseId = course.id
        finding = Task { [weak self] in
            let hits = await Task.detached {
                (try? index.search(words, kinds: [.note], courses: [courseId], limit: 200)) ?? []
            }.value
            if !Task.isCancelled { self?.found = Set(hits.map(\.item.id)) }
        }
    }
}

extension NoteGroup {
    var segment: String {
        switch self {
        case .classes: String(localized: .notesGallerySegmentClass)
        case .units: String(localized: .notesGallerySegmentUnit)
        case .exams: String(localized: .notesGallerySegmentExam)
        case .free: String(localized: .notesGallerySegmentFree)
        }
    }
}

extension NoteSort {
    var label: String {
        switch self {
        case .modified: String(localized: .notesGallerySortModified)
        case .created: String(localized: .notesGallerySortCreated)
        case .title: String(localized: .notesGallerySortTitle)
        case .course: String(localized: .notesGallerySortCourse)
        }
    }
}

extension NoteGrouping {
    var label: String {
        switch self {
        case .date: String(localized: .notesGalleryGroupDate)
        case .kind: String(localized: .notesGalleryGroupKind)
        case .week: String(localized: .notesGalleryGroupWeek)
        case .unit: String(localized: .notesGalleryGroupUnit)
        case .exam: String(localized: .notesGalleryGroupExam)
        case .folder: String(localized: .notesGalleryGroupFolder)
        case .tag: String(localized: .notesGalleryGroupTag)
        case .none: String(localized: .notesGalleryGroupNone)
        }
    }
}
