import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor @Observable
final class NoteListModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    private(set) var notes: [NoteFile] = []
    private(set) var folders: [String] = []
    var filter: NoteKind?
    var adding = false
    var pending: PendingAction?
    let moves: MoveUndo

    init(workspace: Workspace, course: LoadedCourse, moves: MoveUndo = MoveUndo()) {
        self.workspace = workspace
        initial = course
        self.moves = moves
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var notesRevision: Int { workspace.notesRevision }

    struct Row: Identifiable {
        let note: NoteFile
        let detail: String?
        var id: URL { note.url }
    }

    struct Part: Identifiable {
        let title: String
        let rows: [Row]
        var id: String { title }
    }

    var shown: [NoteFile] { notes.filter { filter == nil || $0.meta.kind == filter } }
    var parts: [Part] { Self.parts(shown, file: course.file, calendar: workspace.calendar) }

    var filterOptions: [(NoteKind?, String)] {
        [(NoteKind?.none, String(localized: .notesFilterAll))] + NoteKind.allCases.map { (Optional($0), $0.label) }
    }
    var addHelp: String { filter.map { String(localized: .notesNewKind($0.label)) } ?? String(localized: .notesNewFree) }
    var emptyLine: String { filter.map { String(localized: .notesKindEmpty($0.label)) } ?? String(localized: .notesEmpty) }

    static func parts(_ notes: [NoteFile], file: CourseFile, calendar: Calendar) -> [Part] {
        NoteGroup.grouped(notes, meta: \.meta, title: \.title, in: file).map { group, notes in
            Part(title: group.title, rows: notes.map { Row(note: $0, detail: detail(of: $0, in: group, file: file, calendar: calendar)) })
        }
    }

    private static func detail(of note: NoteFile, in group: NoteGroup, file: CourseFile, calendar: Calendar) -> String? {
        guard note.meta.id != nil else { return String(localized: .notesNeedsId) }

        let meta = note.meta
        switch group {
        case .classes:
            let sessions = file.sessions(pointingAt: meta.id)
            let covered =
                sessions.count > 1
                ? file.sessionSpan(of: meta.id, calendar: calendar)
                : sessions.first.map { $0.date.formatted(.dateTime.month().day().weekday()) }
            return covered.map { "\($0) · \(meta.kind.label)" } ?? "\(meta.kind.label) · " + String(localized: .notesNoSession)
        case .exams:
            return file.exams.first { $0.id == meta.examId }?.title ?? String(localized: .notesNoExam)
        case .units:
            return file.units(of: meta).map(\.title).joined(separator: ", ").nilIfEmpty ?? String(localized: .notesNoUnits)
        case .free:
            return meta.tags.isEmpty ? nil : meta.tags.map { "#" + $0 }.joined(separator: " ")
        }
    }

    func reload() {
        notes = (try? course.store.notes()) ?? []
        folders = course.store.noteFolders()
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
}

extension NoteGroup {
    var title: String {
        switch self {
        case .classes: String(localized: .notesPartClass)
        case .exams: String(localized: .notesPartExam)
        case .units: String(localized: .notesPartUnit)
        case .free: String(localized: .notesPartFree)
        }
    }
}

@MainActor @Observable
final class NotesModel {
    let workspace: Workspace
    private let initial: LoadedCourse

    init(workspace: Workspace, course: LoadedCourse) {
        self.workspace = workspace
        initial = course
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }

    func note(_ id: UUID?) -> NoteFile? { id.flatMap { try? course.store.note(id: $0) } }
}

// 키를 누를 때마다 미리보기가 다시 그리므로, 노트는 그때마다가 아니라 `revision`(workspace의 `notesRevision`)마다 한 번
// 읽는다.
final class NoteEmbedSource {
    private let store: CourseStore
    private let others: [CourseStore]
    private let own: URL?
    private var revision: Int?
    private var notes: [NoteFile]?
    private var elsewhere: [NoteFile]?
    private var texts: [URL: String] = [:]
    private var current: String?

    let name: (AppLink) -> String?

    init(store: CourseStore, others: [CourseStore] = [], own: URL?, name: @escaping (AppLink) -> String? = { _ in nil }) {
        self.store = store
        self.others = others
        self.own = own
        self.name = name
    }

    @MainActor convenience init(workspace: Workspace, course: LoadedCourse, own: URL?) {
        self.init(store: course.store, others: workspace.courses.filter { $0.id != course.id }.map(\.store), own: own) {
            [weak workspace] link in
            MainActor.assumeIsolated { workspace?.name(of: link) }
        }
    }

    func embeds(revision: Int, text: String) -> NoteEmbeds {
        current = text
        if revision != self.revision {
            self.revision = revision
            notes = nil
            elsewhere = nil
            texts = [:]
        }

        let labels = NoteEmbeds.Labels(
            missing: String(localized: .notesEmbedMissing), loop: String(localized: .notesEmbedLoop),
            tooDeep: String(localized: .notesEmbedTooDeep))
        return NoteEmbeds(
            key: own?.standardizedFileURL.path, labels: labels, title: { [self] id in noteFile(id: id)?.title },
            hasNote: { [self] title in note(titled: title) != nil },
            name: { [name] href in AppLink(string: href).flatMap { link in name(link).map(link.label) } }
        ) { [self] link in find(link) }
    }

    private func note(titled title: String) -> NoteFile? {
        if notes == nil { notes = (try? store.notes()) ?? [] }
        return notes?.linked(title)
    }

    private func noteFile(id: UUID) -> NoteFile? {
        if notes == nil { notes = (try? store.notes()) ?? [] }
        if let found = notes?.first(where: { $0.meta.id == id }) { return found }
        if elsewhere == nil { elsewhere = others.flatMap { (try? $0.notes()) ?? [] } }
        return elsewhere?.first { $0.meta.id == id }
    }

    private func find(_ link: WikiLink) -> NoteEmbeds.Note? {
        let named: NoteFile? = if let id = link.noteID { noteFile(id: id) } else { note(titled: link.target) }
        guard let note = named, note.format == .markdown else { return nil }
        if note.url.standardizedFileURL == own?.standardizedFileURL, let current {
            return NoteEmbeds.Note(key: note.url.standardizedFileURL.path, text: current, math: note.meta.math.rawValue)
        }
        guard let text = texts[note.url] ?? (try? store.read(note)) else { return nil }
        texts[note.url] = text
        return NoteEmbeds.Note(key: note.url.standardizedFileURL.path, text: text, math: note.meta.math.rawValue)
    }
}

// 노트 자신의 frontmatter(태그, 별칭)는 따로 두었다가 그대로 다시 쓴다. Folio의 속성은 course.json에 있고 `note link`로
// 바뀐다.
@MainActor @Observable
final class NoteEditorModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    let note: NoteFile
    private var frontmatter = Frontmatter()
    var meta = NoteMeta()
    var body = ""
    private var saved = ""
    // 노트를 불러오면 선택기도 바뀌는데, 그것을 문법을 고른 것으로 세면 안 된다.
    private var savedMath = MathSyntax.latex
    var pendingInsert: String?
    var pendingMath: CompletionItem?
    private(set) var assets: [URL] = []
    private(set) var assetsRevision = 0
    // 여기서 마지막으로 읽거나 쓴 내용이다. 저장할 때 디스크가 이와 다르면 다른 곳(다른 기기, CLI)에서 바뀐 것이므로
    // 덮어쓰기 전에 묻는다.
    private var onDisk = ""
    var conflict = false

    let embeds: NoteEmbedSource
    let links: NoteLinkCompletion

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile) {
        self.workspace = workspace
        initial = course
        self.note = note
        meta = note.meta
        embeds = NoteEmbedSource(workspace: workspace, course: course, own: note.url)
        links = NoteLinkCompletion(workspace: workspace, course: course.id, note: note)
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var store: CourseStore { course.store }
    var dirty: Bool { body != saved }
    var baseURL: URL { note.url.deletingLastPathComponent() }
    var notesRevision: Int { workspace.notesRevision }
    var assist: NoteAssist { NoteAssist(settings: workspace.settings, links: links) }

    func link(titled title: String) -> AppLink? { workspace.noteId(titled: title, in: course).map { AppLink(.note, $0) } }

    func load() {
        onDisk = (try? store.read(note)) ?? ""
        (frontmatter, body) = Frontmatter.split(onDisk)
        saved = body
        conflict = false
        reloadMeta()
    }

    func reloadMeta() {
        let current = (course.stored(note) ?? note).meta
        if current != meta { meta = current }
        savedMath = meta.math
    }

    // 편집기 자신의 저장은 `onDisk`를 파일과 같게 두므로 다시 읽지 않는다. 저장하지 않은 편집은 바꾸지 않고, 거절된
    // 저장처럼 묻는다.
    func refresh() {
        reloadMeta()
        guard let disk = try? store.read(note), disk != onDisk else { return }
        if dirty { conflict = true } else { load() }
    }

    func saveMath() {
        guard meta.math != savedMath else { return }
        savedMath = meta.math
        saveLinks()
    }

    func saveNow(force: Bool) {
        guard !conflict || force else { return }
        let path = store.notePath(of: note.url)
        let text = frontmatter.render(body: body)
        do {
            try workspace.runThrowing(NoteWrite(course: course.id, note: path, text: text, expected: force ? nil : onDisk))
            onDisk = text
            saved = body
        } catch ActionError.conflict {
            conflict = true
        } catch {
            workspace.error = "\(error)"
        }
    }

    func saveIfDirty() { if dirty { saveNow(force: false) } }

    // 그 줄이 페이지가 보였던 내용을 아직 담고 있을 때만 쓴다.
    func replaceLines(_ from: Int, _ to: Int, _ old: String, _ new: String) -> Bool {
        var lines = body.components(separatedBy: "\n")
        guard from >= 1, from <= to, to <= lines.count, lines[(from - 1)...(to - 1)].joined(separator: "\n") == old else { return false }
        lines.replaceSubrange((from - 1)...(to - 1), with: new.components(separatedBy: "\n"))
        body = lines.joined(separator: "\n")
        return true
    }

    func append(_ text: String) { body += (body.hasSuffix("\n") ? "\n" : "\n\n") + text + "\n" }

    // MARK: Review

    var unfinishedReview: Session? {
        guard let id = meta.id, let session = course.file.sessions.first(where: { $0.reviewNoteId == id }), session.reviewNoteUnfinished
        else { return nil }
        return session
    }

    func finishReview(_ session: Session) { workspace.setReviewNoteUnfinished(false, of: session.id, in: course.id) }

    // MARK: Links

    func linkSessions(_ kind: NoteKind) -> [Session] {
        course.file.sessions.filter { s in
            !s.isCancelled && s.date <= workspace.now && s.note(of: kind).map { $0 == meta.id } ?? true
        }.sorted { $0.date > $1.date }
    }
    var linkExams: [Exam] { course.file.exams.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) } }
    var outline: [(unit: FolioDomain.Unit, depth: Int)] { course.outline }
    var linkedSessions: [Session] { course.file.sessions(pointingAt: meta.id) }

    func sessionName(_ s: Session) -> String { course.file.title(of: s, calendar: workspace.calendar) }

    var currentLink: String {
        switch meta.kind {
        case .rough, .review:
            switch linkedSessions.count {
            case 0: String(localized: .notesLinkNoSession(meta.kind.label))
            case 1:
                String(localized: .notesLinkSession(course.file.day(of: linkedSessions[0], calendar: workspace.calendar), meta.kind.label))
            default:
                String(
                    localized: .notesLinkSession(course.file.sessionSpan(of: meta.id, calendar: workspace.calendar) ?? "", meta.kind.label))
            }
        case .examSummary:
            linkExams.first { $0.id == meta.examId }.map { String(localized: .notesLinkExam($0.title)) }
                ?? String(localized: .notesLinkNoExam)
        case .unit:
            String(
                localized: .notesLinkUnit(
                    course.file.units(of: meta).map(\.title).joined(separator: ", ").nilIfEmpty ?? String(localized: .notesNoUnits)))
        case .free: String(localized: .notesPartFree)
        }
    }

    func isLinked(_ s: Session, as kind: NoteKind) -> Bool { meta.kind == kind && linkedSessions.contains { $0.id == s.id } }

    func pick(_ session: UUID, as kind: NoteKind) {
        guard let id = meta.id else { return }
        guard kind == .review, meta.kind == .review else { return relink(kind, session: session) }
        if linkedSessions.contains(where: { $0.id == session }) {
            workspace.run(NoteUnlinkSession(course: course.id, note: id, session: session))
        } else {
            workspace.run(NoteLinkSessions(course: course.id, note: id, sessions: [session]))
        }
        meta.sessionIds = linkedSessions.map(\.id)
    }

    func relink(_ kind: NoteKind, session: UUID? = nil, exam: UUID? = nil) {
        guard meta.id != nil else { return }
        meta.kind = kind
        meta.sessionId = session
        meta.examId = exam
        saveLinks()
    }

    func toggleUnit(_ unit: UUID) {
        if meta.kind != .unit {
            meta.unitIds = []
            relink(.unit)
        }
        if let i = meta.unitIds.firstIndex(of: unit) { meta.unitIds.remove(at: i) } else { meta.unitIds.append(unit) }
        saveLinks()
    }

    private func saveLinks() {
        guard let id = meta.id else { return }
        let ran = workspace.run(NoteLink(course: course.id, note: id, meta: meta))
        if ran == nil, let saved = course.stored(note) { meta = saved.meta }
    }

    // MARK: Assets

    static func markdown(for file: URL, path: String) -> String {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let isImage = UTType(filenameExtension: file.pathExtension)?.conforms(to: .image) ?? false
        let name = file.deletingPathExtension().lastPathComponent
        return isImage ? "![\(name)](\(encoded))" : "[\(file.lastPathComponent)](\(encoded))"
    }

    func assetLink(_ file: URL) -> String { Self.markdown(for: file, path: store.link(to: "assets/" + file.lastPathComponent, from: note)) }

    func reloadAssets() { assets = store.noteAssets() }

    func addAssets(_ urls: [URL]) {
        let store = store
        workspace.perform {
            for url in urls where url.isFileURL {
                // 샌드박스 밖에서 넘겨받은 파일은 이 scope 안에서만 읽을 수 있다.
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                try store.addNoteAsset(url)
            }
        }
        reloadAssets()
    }

    func saveFile(_ name: String, _ data: Data) -> String? {
        var link: String?
        let store = store
        workspace.perform {
            let path = try store.addNoteAsset(named: name, data: data)
            link = Self.markdown(for: URL(fileURLWithPath: path), path: store.link(to: path, from: note))
            assetsRevision += 1
        }
        return link
    }
}
