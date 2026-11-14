import FolioActions
import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation
import Observation
import UniformTypeIdentifiers

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
