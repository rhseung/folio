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
    var renaming: NoteFile?
    var newFolder: NoteFile?
    var pending: PendingAction?
    /// The notes section's, shared with the open note: its rename sheet moves a note too.
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
        func byTitle(_ a: NoteFile, _ b: NoteFile) -> Bool { a.title.localizedStandardCompare(b.title) == .orderedAscending }
        // A note moved in from an old folder has no ID until opened; it says so instead of a kind it doesn't have yet.
        func detail(_ n: NoteFile, _ text: String?) -> String? { n.meta.id == nil ? String(localized: .notesNeedsId) : text }

        // A review note covering several classes sits with the latest of them and names the range it covers.
        let classNotes = notes.filter { $0.meta.kind == .rough || $0.meta.kind == .review }
            .map { (note: $0, sessions: file.sessions(pointingAt: $0.meta.id)) }
            .sorted { a, b in
                switch (a.sessions.last, b.sessions.last) {
                case let (x?, y?) where x.id != y.id: x.date > y.date
                case (_?, nil): true
                case (nil, _?): false
                default: a.note.meta.kind == b.note.meta.kind ? byTitle(a.note, b.note) : a.note.meta.kind == .rough
                }
            }
            .map { n, s in
                let covered = s.count > 1 ? file.sessionSpan(of: n.meta.id, calendar: calendar) : s.first.map { $0.date.formatted(.dateTime.month().day().weekday()) }
                return Row(note: n, detail: detail(n, covered.map { "\($0) · \(n.meta.kind.label)" } ?? "\(n.meta.kind.label) · " + String(localized: .notesNoSession)))
            }

        let exams = notes.filter { $0.meta.kind == .examSummary }
            .map { n in (note: n, exam: file.exams.first { $0.id == n.meta.examId }) }
            .sorted { a, b in
                let (x, y) = (a.exam?.start ?? .distantFuture, b.exam?.start ?? .distantFuture)
                return x != y ? x < y : byTitle(a.note, b.note)
            }
            .map { n, e in Row(note: n, detail: detail(n, e.map { $0.title } ?? String(localized: .notesNoExam))) }

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

    func reload() {
        notes = (try? course.store.notes()) ?? []
        folders = course.store.noteFolders()
    }

    /// The note's ID, giving one first to a note moved in from an old folder.
    func open(_ note: NoteFile) -> UUID? {
        if let id = note.meta.id { return id }
        guard let path = course.store.coursePath(of: note.url), let id = workspace.run(NoteAdopt(course: course.id, note: path))?.made else { return nil }
        reload()
        return id
    }

    // MARK: Rename and move

    /// Notes-relative, as `note mv` and the folder menu name places: "" for Notes/ itself.
    static func notesPath(of url: URL, in store: CourseStore) -> String? {
        let prefix = CourseFolder.notes.rawValue + "/"
        return store.coursePath(of: url).flatMap { $0.hasPrefix(prefix) ? String($0.dropFirst(prefix.count)) : nil }
    }

    static func folder(of note: NoteFile, in store: CourseStore) -> String {
        ((notesPath(of: note.url, in: store) ?? "") as NSString).deletingLastPathComponent
    }

    /// The other folders of Notes/ the note can go to.
    func moveTargets(_ note: NoteFile) -> [String] {
        let here = Self.folder(of: note, in: course.store)
        return folders.filter { $0 != here }
    }

    func folderLabel(_ folder: String) -> String {
        folder.isEmpty ? CourseFolder.notes.rawValue : CourseFolder.notes.rawValue + "/" + folder
    }

    /// Asks with the name the note will have there, ` 2` included, since that is what the user approves.
    func move(_ note: NoteFile, into folder: String) {
        let store = course.store
        let path = (folder.isEmpty ? "" : folder + "/") + note.url.lastPathComponent
        guard let source = store.coursePath(of: note.url), let url = store.movedNoteURL(note, to: path, in: course.file),
              let target = Self.notesPath(of: url, in: store) else { return }
        pending = workspace.ask(NoteMove(course: course.id, note: source, to: target)) { [weak self] ctx in
            self?.moves.keep(ctx)
            self?.reload()
        }
    }

    func undoMove() {
        pending = moves.undo(workspace, course: course.id) { [weak self] in self?.reload() }
    }

    /// Sessions let go of the note first: a note left behind by a failed trash is harmless, a link to nothing is not.
    func delete(_ note: NoteFile, then done: @escaping @MainActor () -> Void = {}) {
        guard let path = course.store.coursePath(of: note.url) else { return }
        pending = workspace.ask(NoteRemove(course: course.id, note: path), button: .notesTrash) { [weak self] _ in
            self?.reload()
            done()
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

    /// The note a link by title opens. One moved in from an old folder gets its ID here, as when opened from the list:
    /// the preview draws its link whole, so the link must open it.
    func noteId(titled title: String) -> UUID? {
        guard let note = ((try? course.store.notes()) ?? []).linked(title) else { return nil }
        if let id = note.meta.id { return id }
        guard let path = course.store.coursePath(of: note.url) else { return nil }
        return workspace.run(NoteAdopt(course: course.id, note: path))?.made
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

    init(store: CourseStore, others: [CourseStore] = [], own: URL?) {
        self.store = store
        self.others = others
        self.own = own
    }

    @MainActor convenience init(workspace: Workspace, course: LoadedCourse, own: URL?) {
        self.init(store: course.store, others: workspace.courses.filter { $0.id != course.id }.map(\.store), own: own)
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
                          hasNote: { [self] title in note(titled: title) != nil }) { [self] link in find(link) }
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

    /// From course.json as it is now: `note` is the entry as it was when the editor opened, which `note link` from the
    /// Claude panel or the CLI may have changed since.
    func reloadMeta() {
        let current = (store.note(at: store.notePath(of: note.url), in: course.file) ?? note).meta
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
    /// Outline order: `order` counts among siblings only, so sorting by it alone interleaves chapters and their units.
    var outline: [(unit: FolioDomain.Unit, depth: Int)] { UnitTree.outline(course.file.units) }
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
        case .topic:
            String(localized: .notesLinkTopic(outline.map(\.unit).filter { meta.unitIds.contains($0.id) }.map(\.title).joined(separator: ", ").nilIfEmpty
                                              ?? String(localized: .notesNoUnits)))
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

    func toggleTopic(_ unit: UUID) {
        // The units another kind shows are its session's or exam's, not the note's own, so a new topic note starts empty.
        if meta.kind != .topic {
            meta.unitIds = []
            relink(.topic)
        }
        if let i = meta.unitIds.firstIndex(of: unit) { meta.unitIds.remove(at: i) } else { meta.unitIds.append(unit) }
        saveLinks()
    }

    private func saveLinks() {
        guard let id = meta.id else { return }
        let ran = workspace.run(NoteLink(course: course.id, note: id, kind: meta.kind, session: meta.sessionId, exam: meta.examId, units: meta.unitIds, math: meta.math))
        // A refused link leaves the file as it was; the label would otherwise show a kind the note doesn't have.
        if ran == nil, let saved = store.note(at: store.notePath(of: note.url), in: course.file) { meta = saved.meta }
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
