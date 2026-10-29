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
    var filter: NoteKind?
    var newTitle = ""
    var adding = false
    var deleting: NoteFile?

    init(workspace: Workspace, course: LoadedCourse) {
        self.workspace = workspace
        initial = course
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }

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
    var parts: [Part] { Self.parts(shown, file: course.file) }

    var filterOptions: [(NoteKind?, String)] { [(NoteKind?.none, String(localized: .notesFilterAll))] + NoteKind.allCases.map { (Optional($0), $0.label) } }
    var addHelp: String { filter.map { String(localized: .notesNewKind($0.label)) } ?? String(localized: .notesNewFree) }
    var titlePrompt: String { filter.map { String(localized: .notesNewKindTitle($0.label)) } ?? String(localized: .notesNewTitle) }
    var emptyLine: String { filter.map { String(localized: .notesKindEmpty($0.label)) } ?? String(localized: .notesEmpty) }

    static func parts(_ notes: [NoteFile], file: CourseFile) -> [Part] {
        func byTitle(_ a: NoteFile, _ b: NoteFile) -> Bool { a.title.localizedStandardCompare(b.title) == .orderedAscending }
        // A note moved in from an old folder has no ID until opened; it says so instead of a kind it doesn't have yet.
        func detail(_ n: NoteFile, _ text: String?) -> String? { n.meta.id == nil ? String(localized: .notesNeedsId) : text }

        let classNotes = notes.filter { $0.meta.kind == .rough || $0.meta.kind == .review }
            .map { (note: $0, session: file.session(of: $0.meta)) }
            .sorted { a, b in
                switch (a.session, b.session) {
                case let (x?, y?) where x.id != y.id: x.date > y.date
                case (_?, nil): true
                case (nil, _?): false
                default: a.note.meta.kind == b.note.meta.kind ? byTitle(a.note, b.note) : a.note.meta.kind == .rough
                }
            }
            .map { n, s in
                Row(note: n, detail: detail(n, s.map { "\($0.date.formatted(.dateTime.month().day().weekday())) · \(n.meta.kind.label)" }
                                                ?? "\(n.meta.kind.label) · " + String(localized: .notesNoSession)))
            }

        let exams = notes.filter { $0.meta.kind == .examSummary }
            .map { n in (note: n, exam: file.exams.first { $0.id == n.meta.examId }) }
            .sorted { a, b in
                let (x, y) = (a.exam?.start ?? .distantFuture, b.exam?.start ?? .distantFuture)
                return x != y ? x < y : byTitle(a.note, b.note)
            }
            .map { n, e in Row(note: n, detail: detail(n, e.map { $0.title.isEmpty ? $0.kind.label : $0.title } ?? String(localized: .notesNoExam))) }

        let units = UnitTree.outline(file.units).map(\.unit)
        let topics = notes.filter { $0.meta.kind == .topic }.sorted(by: byTitle).map { n in
            Row(note: n, detail: detail(n, units.filter { n.meta.unitIds.contains($0.id) }.map(\.title).joined(separator: ", ").nilIfEmpty ?? String(localized: .notesNoUnits)))
        }

        let free = notes.filter { $0.meta.kind == .free }.sorted(by: byTitle).map { n in
            Row(note: n, detail: detail(n, n.meta.tags.isEmpty ? nil : n.meta.tags.map { "#" + $0 }.joined(separator: " ")))
        }

        return [Part(title: String(localized: .notesPartClass), rows: classNotes), Part(title: String(localized: .notesPartExam), rows: exams),
                Part(title: String(localized: .notesPartTopic), rows: topics), Part(title: String(localized: .notesPartFree), rows: free)].filter { !$0.rows.isEmpty }
    }

    func reload() { notes = (try? course.store.notes()) ?? [] }

    /// Notes made elsewhere (the Claude panel) show up once one of them is chosen.
    func reloadIfMissing(_ id: UUID?) {
        if let id, !notes.contains(where: { $0.meta.id == id }) { reload() }
    }

    /// The note's ID, giving one first to a note moved in from an old folder.
    func open(_ note: NoteFile) -> UUID? {
        if let id = note.meta.id { return id }
        guard let path = course.store.coursePath(of: note.url), let id = workspace.run(NoteAdopt(course: course.id, note: path))?.made else { return nil }
        reload()
        return id
    }

    func create() -> UUID? {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, let id = workspace.run(NoteAdd(course: course.id, title: title, kind: filter ?? .free))?.made else { return nil }
        newTitle = ""
        adding = false
        reload()
        return id
    }

    /// Sessions let go of the note first: a note left behind by a failed trash is harmless, a link to nothing is not.
    func delete(_ note: NoteFile) {
        if let path = course.store.coursePath(of: note.url) { workspace.run(NoteRemove(course: course.id, note: path)) }
        reload()
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

    /// Links name a note by its title (Obsidian style); Obsidian also matches case-insensitively.
    func noteId(titled title: String) -> UUID? {
        let notes = (try? course.store.notes()) ?? []
        return (notes.first { $0.title == title } ?? notes.first { $0.title.caseInsensitiveCompare(title) == .orderedSame })?.meta.id
    }
}

/// The frontmatter (tags, aliases, IDs) is kept aside and written back unchanged, except the math syntax set here.
@MainActor @Observable
final class NoteEditorModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    let note: NoteFile
    private var frontmatter = Frontmatter()
    var meta = NoteMeta()
    var body = ""
    private var saved = ""
    private var savedMath = MathSyntax.latex
    /// Set to insert at the editor's cursor; the editor clears it once inserted.
    var pendingInsert: String?
    private(set) var assets: [URL] = []
    /// Bumped when a pasted or dropped image lands in `assets/`, which the tray doesn't see happen.
    private(set) var assetsRevision = 0
    /// The file as last read or written here. A save finding something else on disk was changed elsewhere (another
    /// device, the CLI) and asks before overwriting it.
    private var onDisk = ""
    var conflict = false

    init(workspace: Workspace, course: LoadedCourse, note: NoteFile) {
        self.workspace = workspace
        initial = course
        self.note = note
    }

    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var store: CourseStore { course.store }
    var dirty: Bool { body != saved || meta.math != savedMath }
    var baseURL: URL { note.url.deletingLastPathComponent() }
    var html: String { HTMLRenderer.render(ParsedNote(frontmatter.render(body: body))) }

    func load() {
        onDisk = (try? store.read(note)) ?? ""
        (frontmatter, body) = Frontmatter.split(onDisk)
        saved = body
        meta = note.meta
        savedMath = meta.math
    }

    func saveNow(force: Bool) {
        guard !conflict || force else { return }
        guard let path = store.coursePath(of: note.url) else { return }
        var fm = frontmatter
        meta.apply(to: &fm)
        let text = fm.render(body: body)
        do {
            try workspace.runThrowing(NoteWrite(course: course.id, note: path, text: text, expected: force ? nil : onDisk))
            onDisk = text
            saved = body
            savedMath = meta.math
        } catch ActionError.conflict {
            conflict = true
        } catch {
            workspace.error = "\(error)"
        }
    }

    func saveIfDirty() { if dirty { saveNow(force: false) } }

    func append(_ text: String) { body += (body.hasSuffix("\n") ? "\n" : "\n\n") + text + "\n" }

    // MARK: Review

    /// Where the writing happens, so finishing it is one click here rather than a trip back to Today.
    var unfinishedReview: Session? {
        guard let id = meta.id, let session = course.file.sessions.first(where: { $0.reviewNoteId == id }), session.reviewNoteUnfinished else { return nil }
        return session
    }

    func finishReview(_ session: Session) { workspace.setReviewNoteUnfinished(false, of: session.id, in: course.id) }

    // MARK: Links

    var linkSessions: [Session] { course.file.sessions.filter { !$0.isCancelled && $0.date <= .now }.sorted { $0.date > $1.date } }
    var linkExams: [Exam] { course.file.exams.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) } }
    /// Outline order: `order` counts among siblings only, so sorting by it alone interleaves chapters and their units.
    var outline: [(unit: FolioDomain.Unit, depth: Int)] { UnitTree.outline(course.file.units) }
    var linkedSession: Session? { course.file.session(pointingAt: meta.id) }

    func sessionName(_ s: Session) -> String { course.file.name(of: s) }

    var currentLink: String {
        switch meta.kind {
        case .rough, .review:
            linkedSession.map { String(localized: .notesLinkSession(sessionName($0), meta.kind.label)) } ?? String(localized: .notesLinkNoSession(meta.kind.label))
        case .examSummary:
            linkExams.first { $0.id == meta.examId }.map { String(localized: .notesLinkExam($0.title)) } ?? String(localized: .notesLinkNoExam)
        case .topic:
            String(localized: .notesLinkTopic(outline.map(\.unit).filter { meta.unitIds.contains($0.id) }.map(\.title).joined(separator: ", ").nilIfEmpty
                                              ?? String(localized: .notesNoUnits)))
        case .free: String(localized: .notesPartFree)
        }
    }

    /// One kind at a time: becoming another kind lets go of the session or exam the old one belonged to.
    func relink(_ kind: NoteKind, session: UUID? = nil, exam: UUID? = nil) {
        guard meta.id != nil else { return }
        meta.kind = kind
        meta.sessionId = session
        meta.examId = exam
        saveLinks()
    }

    func toggleTopic(_ unit: UUID) {
        if meta.kind != .topic { relink(.topic) }
        if let i = meta.unitIds.firstIndex(of: unit) { meta.unitIds.remove(at: i) } else { meta.unitIds.append(unit) }
        saveLinks()
    }

    // The body is saved first, so the link action rewrites the frontmatter of the text on screen; reading the file back
    // afterwards keeps the editor's next save from taking that write for someone else's.
    private func saveLinks() {
        saveNow(force: false)
        guard !conflict, let id = meta.id else { return }
        workspace.run(NoteLink(course: course.id, note: id, kind: meta.kind, session: meta.sessionId, exam: meta.examId, units: meta.unitIds))
        onDisk = (try? store.read(note)) ?? onDisk
        workspace.notesRevision += 1
    }

    // MARK: Assets

    static func markdown(for file: URL, path: String) -> String {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let isImage = UTType(filenameExtension: file.pathExtension)?.conforms(to: .image) ?? false
        let name = file.deletingPathExtension().lastPathComponent
        return isImage ? "![\(name)](\(encoded))" : "[\(file.lastPathComponent)](\(encoded))"
    }

    /// How a dragged asset is written from where the note sits, e.g. `assets/a.png` or `../assets/a.png`.
    func assetLink(_ file: URL) -> String { Self.markdown(for: file, path: store.link(to: "assets/" + file.lastPathComponent, from: note)) }

    func reloadAssets() { assets = store.noteAssets() }

    func addAssets(_ urls: [URL]) {
        let store = store
        workspace.perform {
            for url in urls where url.isFileURL {
                // Files handed over from outside the sandbox stay readable only inside this scope.
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
