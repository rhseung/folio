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
    /// Read with the notes, not in each row's menu, which every redraw of the list builds.
    private(set) var folders: [String] = []
    var filter: NoteKind?
    var adding = false
    var pending: PendingAction?
    /// The notes section's, shared with the open note: its sheet and menus move a note too.
    let moves: MoveUndo

    init(workspace: Workspace, course: LoadedCourse, moves: MoveUndo = MoveUndo()) {
        self.workspace = workspace
        initial = course
        self.moves = moves
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
    var parts: [Part] { Self.parts(shown, file: course.file, calendar: workspace.calendar) }

    var filterOptions: [(NoteKind?, String)] { [(NoteKind?.none, String(localized: .notesFilterAll))] + NoteKind.allCases.map { (Optional($0), $0.label) } }
    var addHelp: String { filter.map { String(localized: .notesNewKind($0.label)) } ?? String(localized: .notesNewFree) }
    var emptyLine: String { filter.map { String(localized: .notesKindEmpty($0.label)) } ?? String(localized: .notesEmpty) }

    static func parts(_ notes: [NoteFile], file: CourseFile, calendar: Calendar) -> [Part] {
        NoteGroup.grouped(notes, meta: \.meta, title: \.title, in: file).map { group, notes in
            Part(title: group.title, rows: notes.map { Row(note: $0, detail: detail(of: $0, in: group, file: file, calendar: calendar)) })
        }
    }

    private static func detail(of note: NoteFile, in group: NoteGroup, file: CourseFile, calendar: Calendar) -> String? {
        // A note moved in from an old folder has no ID until opened; it says so instead of a kind it doesn't have yet.
        guard note.meta.id != nil else { return String(localized: .notesNeedsId) }

        let meta = note.meta
        switch group {
        case .classes:
            // A review note covering several classes names the range it covers.
            let sessions = file.sessions(pointingAt: meta.id)
            let covered = sessions.count > 1
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
        // The row's note was read before it had an entry, and would still show it as needing one.
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

    /// A note moved in from an old folder gets its ID here too, as when opened from the list: the preview draws its link
    /// whole, so the link must open it.
    func noteId(titled title: String) -> UUID? {
        ((try? course.store.notes()) ?? []).linked(title).flatMap { workspace.noteId(of: $0, in: course) }
    }
}

/// The notes a note's preview draws in its embeds and block references' previews and names in its links: by title in
/// its course, or by ID in any course (`[[note:<ID>]]`). A title is found as `NotesModel.noteId(titled:)` opens it.
/// Read once for each `revision` (the workspace's `notesRevision`), not on every keystroke the preview redraws for.
final class NoteEmbedSource {
    private let store: CourseStore
    private let others: [CourseStore]
    private let own: URL?
    private var revision: Int?
    private var notes: [NoteFile]?
    private var elsewhere: [NoteFile]?
    private var texts: [URL: String] = [:]
    /// The note's text as the editor has it, which may not be saved yet: a reference to its own block shows that.
    private var current: String?

    /// The name of what a link into the app points at (`Workspace.name(of:)`), which the preview shows on a link
    /// without its own and a pasted address is written with.
    let name: (AppLink) -> String?

    init(store: CourseStore, others: [CourseStore] = [], own: URL?, name: @escaping (AppLink) -> String? = { _ in nil }) {
        self.store = store
        self.others = others
        self.own = own
        self.name = name
    }

    @MainActor convenience init(workspace: Workspace, course: LoadedCourse, own: URL?) {
        // The preview and the editor read it on the main actor, where the workspace is.
        self.init(store: course.store, others: workspace.courses.filter { $0.id != course.id }.map(\.store), own: own) { [weak workspace] link in
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
        let labels = NoteEmbeds.Labels(missing: String(localized: .notesEmbedMissing), loop: String(localized: .notesEmbedLoop),
                                       tooDeep: String(localized: .notesEmbedTooDeep))
        return NoteEmbeds(key: own?.standardizedFileURL.path, labels: labels, title: { [self] id in noteFile(id: id)?.title },
                          hasNote: { [self] title in note(titled: title) != nil },
                          name: { [name] href in AppLink(string: href).flatMap { link in name(link).map(link.label) } }) { [self] link in find(link) }
    }

    private func note(titled title: String) -> NoteFile? {
        if notes == nil { notes = (try? store.notes()) ?? [] }
        return notes?.linked(title)
    }

    /// The course's own notes first; the others are listed only for an ID that isn't here, which a link copied from
    /// another course's note has.
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

/// The note's own frontmatter (tags, aliases) is kept aside and written back unchanged; Folio's properties are in
/// course.json and change through `note link`.
@MainActor @Observable
final class NoteEditorModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    let note: NoteFile
    private var frontmatter = Frontmatter()
    var meta = NoteMeta()
    var body = ""
    private var saved = ""
    /// Loading a note sets the picker too, which must not count as choosing a syntax.
    private var savedMath = MathSyntax.latex
    /// Set to insert at the editor's cursor; the editor clears it once inserted.
    var pendingInsert: String?
    /// A symbol picked in the math palette, for the editor to put at its cursor and clear.
    var pendingMath: CompletionItem?
    private(set) var assets: [URL] = []
    /// Bumped when a pasted or dropped image lands in `assets/`, which the tray doesn't see happen.
    private(set) var assetsRevision = 0
    /// The file as last read or written here. A save finding something else on disk was changed elsewhere (another
    /// device, the CLI) and asks before overwriting it.
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

    func load() {
        onDisk = (try? store.read(note)) ?? ""
        (frontmatter, body) = Frontmatter.split(onDisk)
        saved = body
        conflict = false
        reloadMeta()
    }

    func reloadMeta() {
        let current = (course.stored(note) ?? note).meta
        // Every write to any note lands here; the bar and the preview redraw only when this note's links moved.
        if current != meta { meta = current }
        savedMath = meta.math
    }

    /// After a write elsewhere (`notesRevision`). The editor's own save left `onDisk` as the file is, so it reads
    /// nothing again; unsaved edits are never replaced and ask as a refused save would.
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

    /// Writes a task box ticked in the preview over its line, if it still holds what the page showed.
    func replaceLines(_ from: Int, _ to: Int, _ old: String, _ new: String) -> Bool {
        var lines = body.components(separatedBy: "\n")
        guard from >= 1, from <= to, to <= lines.count, lines[(from - 1)...(to - 1)].joined(separator: "\n") == old else { return false }
        lines.replaceSubrange((from - 1)...(to - 1), with: new.components(separatedBy: "\n"))
        body = lines.joined(separator: "\n")
        return true
    }

    func append(_ text: String) { body += (body.hasSuffix("\n") ? "\n" : "\n\n") + text + "\n" }

    // MARK: Review

    /// Where the writing happens, so finishing it is one click here rather than a trip back to Today.
    var unfinishedReview: Session? {
        guard let id = meta.id, let session = course.file.sessions.first(where: { $0.reviewNoteId == id }), session.reviewNoteUnfinished else { return nil }
        return session
    }

    func finishReview(_ session: Session) { workspace.setReviewNoteUnfinished(false, of: session.id, in: course.id) }

    // MARK: Links

    /// A session whose note of this kind is another note can't take this one (`NoteLink` refuses it), so it isn't offered.
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
            case 1: String(localized: .notesLinkSession(course.file.day(of: linkedSessions[0], calendar: workspace.calendar), meta.kind.label))
            default: String(localized: .notesLinkSession(course.file.sessionSpan(of: meta.id, calendar: workspace.calendar) ?? "", meta.kind.label))
            }
        case .examSummary:
            linkExams.first { $0.id == meta.examId }.map { String(localized: .notesLinkExam($0.title)) } ?? String(localized: .notesLinkNoExam)
        case .unit:
            String(localized: .notesLinkUnit(course.file.units(of: meta).map(\.title).joined(separator: ", ").nilIfEmpty ?? String(localized: .notesNoUnits)))
        case .free: String(localized: .notesPartFree)
        }
    }

    func isLinked(_ s: Session, as kind: NoteKind) -> Bool { meta.kind == kind && linkedSessions.contains { $0.id == s.id } }

    /// A review note covers every class reviewed in it, so picking a class adds it or takes it off again; a rough note,
    /// or a note becoming a review note, moves to the class picked.
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

    /// One kind at a time: becoming another kind lets go of the session or exam the old one belonged to.
    func relink(_ kind: NoteKind, session: UUID? = nil, exam: UUID? = nil) {
        guard meta.id != nil else { return }
        meta.kind = kind
        meta.sessionId = session
        meta.examId = exam
        saveLinks()
    }

    func toggleUnit(_ unit: UUID) {
        // The units another kind shows are its session's or exam's, not the note's own, so a new unit note starts empty.
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
        // A refused link leaves the file as it was; the label would otherwise show a kind the note doesn't have.
        if ran == nil, let saved = course.stored(note) { meta = saved.meta }
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
