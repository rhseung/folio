import FolioDomain
import FolioMarkdown
import FolioStorage
import Foundation

func note(_ ctx: ActionContext, course: UUID, path: String) throws -> NoteFile {
    guard let note = try ctx.store(course).note(at: path, in: ctx.file(course)) else {
        throw ActionError.notFound(String(localized: .errorNotFoundNote("\(path)")))
    }
    return note
}

func note(_ ctx: ActionContext, course: UUID, id: UUID) throws -> NoteFile {
    guard let note = try ctx.store(course).note(id: id, in: ctx.file(course)) else { throw ActionError.notFound(String(localized: .errorNotFoundNote("\(id)"))) }
    return note
}

/// A note in `Notes/` with `body`, or the template for its kind and format. The command reads the body from a file or
/// standard input, so it is written by hand.
@Action("note add", "Notes 폴더에 마크다운이나 LaTeX 노트 만들기. 본문을 주지 않으면 종류의 템플릿", effect: .creates, done: "노트 '{title}'을(를) 만들었습니다",
        phrases: ["노트 만들기", "새 노트", "정리 노트 쓰기"], cli: .manual)
public struct NoteAdd {
    @New var id: Note.ID
    @Arg var course: Course.ID
    @Arg var title: String
    var kind: NoteKind = .free
    var format: NoteFormat = .markdown
    var body: String?
    var session: Session.ID?
    var exam: Exam.ID?
    var units: [FolioDomain.Unit.ID] = []

    public func run(_ ctx: ActionContext) throws {
        let title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { throw ActionError.rule(String(localized: .errorNoteTitleEmpty)) }
        let settings = try ctx.settings()
        var meta = NoteMeta(id: id, kind: kind, math: settings.newNoteMath)
        try NoteLinks(kind: kind, session: session, exam: exam, units: units).apply(to: &meta, in: try ctx.file(course))
        let body = body ?? NoteTemplate.body(for: kind, title: title, sections: settings.noteSections(for: kind), format: format)
        let made = try ctx.createNote(course, title: title, meta: meta, format: format, body: body)
        if let session = meta.sessionId {
            try ctx.edit(course) { f in
                f.linkNote(made, to: session, as: kind)
                // As `session note` does: making a review note is not writing it.
                if kind == .review, let i = f.sessions.firstIndex(where: { $0.id == session }) { f.sessions[i].reviewNoteUnfinished = true }
            }
        }
        ctx.made(made)
    }
}

/// What a note of each kind points at; the others are dropped, so a note has one kind's links at a time.
struct NoteLinks {
    var kind: NoteKind
    var session: Session.ID?
    var exam: Exam.ID?
    var units: [FolioDomain.Unit.ID]

    /// Checked here as well as by the model, for an error that names what is missing.
    func apply(to meta: inout NoteMeta, in course: CourseFile) throws {
        if kind == .rough || kind == .review, let session {
            guard let s = course.sessions.first(where: { $0.id == session }) else { throw ActionError.notFound(String(localized: .errorNotFoundSession)) }
            if s.isCancelled { throw ActionError.rule(String(localized: .errorNoteCancelledSession)) }
            // Taking it would leave the other note pointing at a session that no longer points back.
            if let other = s.note(of: kind), other != meta.id {
                let name = course.name(of: s)
                throw ActionError.rule(String(localized: kind == .rough ? .errorNoteSessionHasRough(name) : .errorNoteSessionHasReview(name)))
            }
        }
        if kind == .examSummary, let exam, !course.exams.contains(where: { $0.id == exam }) { throw ActionError.notFound(String(localized: .errorNotFoundExam)) }
        if kind == .topic, let u = units.first(where: { u in !course.units.contains { $0.id == u } }) { throw ActionError.notFound(String(localized: .errorNotFoundUnitId("\(u)"))) }
        meta.kind = kind
        meta.sessionId = kind == .rough || kind == .review ? session : nil
        meta.examId = kind == .examSummary ? exam : nil
        // Other kinds read their units from the session or exam, so a topic note's units go when it becomes one.
        meta.unitIds = kind == .topic ? units : []
    }
}

/// Writes the whole file as given. With `expected`, refuses when the file is no longer that text: it was changed
/// elsewhere since it was read. The command reads the text from a file and checks `--expect` against a hash.
@Action("note write", "노트 파일 전체를 바꾸기. 노트의 프로퍼티는 course.json에 있어 그대로다", done: "노트 '{note}'을(를) 썼습니다",
        phrases: ["노트 수정", "노트 내용 바꾸기"], cli: .manual)
public struct NoteWrite {
    @Arg var course: Course.ID
    @Arg var note: Note.Path
    var text: String
    var expected: String?

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let file = try FolioActions.note(ctx, course: course, path: note)
        if let expected, try store.read(file) != expected { throw ActionError.conflict(String(localized: .errorNoteChanged("\(note)"))) }
        try ctx.io(Change(.changed, ctx.relative(file.url))) { try store.write(file, text: text) }
    }
}

/// Changes part of a note without sending the whole text, as `note write` must. Each `old` has to occur exactly
/// once in the text the replacements before it left, which also does `expected`'s job: text changed elsewhere no
/// longer matches. The command pairs `--old` and `--new` by order, so it is written by hand.
@Action("note edit", "노트 일부 고치기. 찾아 바꾸거나 끝에 붙인다. 노트 전체를 다시 쓰지 않는다", done: "노트 '{note}'을(를) 고쳤습니다",
        examples: [#"folio note edit EC4207/2주차-1 --old "non-adjacent" --new "서로 이웃하지 않는""#, #"folio note edit EC4207/2주차-1 --append "질문: 최대 매칭은 어떻게 찾나""#],
        phrases: ["노트 일부 수정", "노트에 덧붙이기", "노트 끝에 추가", "노트 찾아 바꾸기"], cli: .manual)
public struct NoteEdit {
    public struct Replacement: Codable, Sendable, Equatable {
        public var old: String
        public var new: String
        public init(old: String, new: String) {
            self.old = old
            self.new = new
        }
    }
    /// 과목
    @Arg var course: Course.ID
    /// 노트
    @Arg var note: Note.Path
    /// 찾아 바꿀 원문(old)과 새 글(new). old는 노트에 꼭 한 번 나와야 하고, 준 순서대로 바꾼다
    var replacements: [Replacement] = []
    /// 노트 끝에 붙일 글. 새 줄에서 시작한다. 빈 줄을 두려면 앞에 줄바꿈을 넣는다
    var append: String?

    public func run(_ ctx: ActionContext) throws {
        guard !replacements.isEmpty || append?.isEmpty == false else { throw ActionError.rule(String(localized: .errorNoteEditNothing)) }
        let store = try ctx.store(course)
        let file = try FolioActions.note(ctx, course: course, path: note)
        let text = try Self.edited(try store.read(file), replacements, append: append, note: note)
        try ctx.io(Change(.changed, ctx.relative(file.url))) { try store.write(file, text: text) }
    }

    static func edited(_ text: String, _ replacements: [Replacement], append: String?, note: String) throws -> String {
        var text = text
        for (i, r) in replacements.enumerated() {
            let n = i + 1
            guard !r.old.isEmpty else { throw ActionError.rule(String(localized: .errorNoteEditEmptyOld(n))) }
            let ranges = text.ranges(of: r.old)
            // Not there most likely means the note changed since it was read, the case `note write` calls a conflict.
            guard let range = ranges.first else { throw ActionError.conflict(String(localized: .errorNoteEditMissing(n, Self.excerpt(r.old), note))) }
            guard ranges.count == 1 else { throw ActionError.rule(String(localized: .errorNoteEditAmbiguous(n, Self.excerpt(r.old), ranges.count))) }
            text.replaceSubrange(range, with: r.new)
        }
        if let append, !append.isEmpty {
            if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
            text += append.hasSuffix("\n") ? append : append + "\n"
        }
        return text
    }

    static func excerpt(_ s: String) -> String {
        let line = s.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? s
        return line.count > 40 ? line.prefix(40) + "…" : line
    }
}

/// Gives a note made outside Folio an entry in course.json, so sessions and searches can point at it. The file is
/// left as it is.
@Action("note adopt", "Folio 밖에서 만든 노트에 ID 붙이기", done: "노트 '{note}'에 ID를 붙였습니다",
        examples: ["folio note adopt EC4207/Notes/외부.md"], phrases: ["밖에서 만든 노트 등록"])
public struct NoteAdopt {
    /// 과목
    @Arg var course: Course.ID
    /// 노트
    @Arg var note: Note.Path

    public func run(_ ctx: ActionContext) throws {
        let file = try FolioActions.note(ctx, course: course, path: note)
        if let id = file.meta.id {
            ctx.made(id)
            return
        }
        let store = try ctx.store(course)
        let id = UUID()
        try ctx.edit(course) { $0.notes.append(NoteEntry(id: id, device: ctx.device, at: ctx.now, path: store.notePath(of: file.url), meta: NoteMeta(id: id))) }
        ctx.made(id)
    }
}

/// One kind at a time: becoming another kind lets go of the session or exam the old one belonged to. Writes the
/// note's entry and the session's note link together. The command takes each unit as `--unit`, so it is written by hand.
@Action("note link", "노트의 종류와 회차, 시험, 단원 연결, 수식 문법 정하기", done: "노트 '{note}'을(를) 연결했습니다",
        phrases: ["노트 연결", "노트 종류"], cli: .manual)
public struct NoteLink {
    @Arg var course: Course.ID
    @Arg var note: Note.ID
    var kind: NoteKind
    var session: Session.ID?
    var exam: Exam.ID?
    var units: [FolioDomain.Unit.ID] = []
    /// 수식 문법. 빼면 그대로
    var math: MathSyntax?

    public func run(_ ctx: ActionContext) throws {
        var meta = try FolioActions.note(ctx, course: self.course, id: note).meta
        try NoteLinks(kind: kind, session: session, exam: exam, units: units).apply(to: &meta, in: try ctx.file(self.course))
        meta.math = math ?? meta.math
        try ctx.edit(self.course) { f in
            guard let i = f.notes.firstIndex(where: { $0.id == note }) else { return }
            f.notes[i].apply(meta)
            f.notes[i].touch(by: ctx.device, at: ctx.now)
            f.linkNote(note, to: meta.sessionId, as: kind)
        }
    }
}

/// One review note for several classes caught up on at once. Each session points at the note, as a session with its
/// own note does, so course.json keeps its shape. Sessions already linked stay; one holding another review note is
/// refused before anything is written, as `note link` refuses it.
@Action("note link-sessions", "복습 노트를 회차 여러 개에 연결하기. 이미 연결된 회차는 그대로 둔다", done: "노트 '{note}'에 회차를 연결했습니다",
        examples: [#"folio note link-sessions "EC4207/9주차 정리" 9주차-1 9주차-2"#],
        phrases: ["복습 노트 여러 회차", "밀린 수업 한 번에 복습", "회차 여러 개 복습 노트"])
public struct NoteLinkSessions {
    /// 과목
    @Arg var course: Course.ID
    /// 복습 노트
    @Arg var note: Note.ID
    /// 회차. 예: 9주차-1
    @Arg var sessions: [Session.ID]

    public func run(_ ctx: ActionContext) throws {
        var meta = try FolioActions.note(ctx, course: course, id: note).meta
        guard meta.kind == .review else { throw ActionError.rule(String(localized: .errorNoteLinkSessionsKind)) }
        let file = try ctx.file(course)
        for session in sessions { try NoteLinks(kind: .review, session: session, exam: nil, units: []).apply(to: &meta, in: file) }
        try ctx.edit(course) { f in
            for session in sessions { f.linkNote(note, to: session, as: .review) }
        }
    }
}

/// Takes one session off a note; the other sessions a review note covers keep it.
@Action("note unlink-session", "회차 하나에서 노트 떼기. 노트가 맡은 다른 회차는 그대로 둔다", done: "회차 '{session}'에서 노트 '{note}'을(를) 뗐습니다",
        examples: [#"folio note unlink-session "EC4207/9주차 정리" 9주차-1"#], phrases: ["복습 노트 회차 빼기", "노트 회차 연결 풀기"])
public struct NoteUnlinkSession {
    /// 과목
    @Arg var course: Course.ID
    /// 노트
    @Arg var note: Note.ID
    /// 회차
    @Arg var session: Session.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            guard f.notes.contains(where: { $0.id == note }) else { throw ActionError.notFound(String(localized: .errorNotFoundNote("\(note)"))) }
            let s = f.sessions[try index(session, in: f.sessions, .valueSession)]
            // A mistyped session would otherwise report the note taken off a class it was never on.
            guard s.roughNoteId == note || s.reviewNoteId == note else {
                throw ActionError.rule(String(localized: .errorNoteSessionNotLinked(f.name(of: s))))
            }
            f.unlinkNote(note, from: session)
        }
    }
}

/// Moves Folio's properties out of the notes' frontmatter into course.json, once, for notes from before #206. The
/// entries are saved before any file is touched, and a note that already has one is only cleaned, so a run that stops
/// halfway is finished by running it again. A link to a session, unit or exam that is gone is dropped, as is a second
/// note of one kind on a session: the model would refuse the whole file for either. The course may be left out, which generated commands can't take, so the command is
/// written by hand.
@Action("note migrate", "노트 frontmatter의 프로퍼티를 course.json으로 옮기고 파일에서 지우기. 예전 노트를 한 번 정리한다",
        done: "노트 프로퍼티를 course.json으로 옮겼습니다", phrases: ["노트 프로퍼티 옮기기", "frontmatter 정리"], cli: .manual)
public struct NoteMigrate {
    /// 과목. 빼면 모든 과목
    @Arg var course: Course.ID?

    public func run(_ ctx: ActionContext) throws {
        let courses = try course.map { [$0] } ?? ctx.gist.courseStores().map { try $0.load().model.course.id }
        for course in courses {
            let store = try ctx.store(course)
            let notes = try store.frontmatterNotes()
            guard !notes.isEmpty else { continue }
            try ctx.edit(course) { f in
                for n in notes where !f.notes.contains(where: { $0.path == store.notePath(of: n.url) }) {
                    var meta = n.meta
                    meta.sessionId = meta.sessionId.flatMap { id in f.sessions.contains { $0.id == id } ? id : nil }
                    meta.examId = meta.examId.flatMap { id in f.exams.contains { $0.id == id } ? id : nil }
                    meta.unitIds = meta.unitIds.filter { id in f.units.contains { $0.id == id } }
                    // A note copied in Finder carries the original's id; the copy gets its own.
                    let id = meta.id.flatMap { id in f.notes.contains { $0.id == id } ? nil : id } ?? UUID()
                    // Before #206 taking a session's note left the old one's frontmatter pointing at it. The note the
                    // session points back to keeps the link; any other of that kind loses it. The one that keeps it is
                    // linked from the session too, or the session would still ask for that note.
                    if meta.kind == .rough || meta.kind == .review, let s = f.sessions.first(where: { $0.id == meta.sessionId }) {
                        let pointed = s.note(of: meta.kind)
                        if pointed.map({ $0 != id }) ?? false { meta.sessionId = nil } else { f.linkNote(id, to: s.id, as: meta.kind) }
                    }
                    f.notes.append(NoteEntry(id: id, device: ctx.device, at: ctx.now, path: store.notePath(of: n.url), meta: meta))
                }
            }
            for n in notes {
                try ctx.io(Change(.changed, ctx.relative(n.url))) { try store.write(NoteFile(url: n.url, meta: NoteMeta(id: nil)), text: n.text) }
            }
        }
    }
}

/// Renames the session notes still named `10주차-2` the way `session note` names new ones (#273). The files move as one
/// `moves.jsonl` batch (`made`), and `cleanup undo` of it turns names, headings and links back. A taken name gets ` 2`.
/// The course may be left out, which generated commands can't take, so the command is written by hand.
@Action("note retitle", "예전 이름(10주차-2)의 회차 노트를 날짜와 주제 이름으로 바꾸기. 노트의 첫 제목과 다른 노트의 링크도 따라 바뀐다",
        effect: .moves, confirm: "회차 노트의 이름을 날짜와 주제로 바꿉니다.", done: "회차 노트의 이름을 바꿨습니다",
        phrases: ["노트 이름 날짜로", "예전 노트 이름 바꾸기", "주차 이름 노트"], cli: .manual)
public struct NoteRetitleSessions {
    /// 과목. 빼면 모든 과목
    @Arg var course: Course.ID?

    public func run(_ ctx: ActionContext) throws {
        let courses = try course.map { [$0] } ?? ctx.gist.courseStores().map { try $0.load().model.course.id }
        var moves: [PlannedMove] = []
        for course in courses {
            let store = try ctx.store(course)
            var taken = Set<String>()
            for r in try ctx.file(course).legacySessionNoteRetitles(calendar: ctx.calendar) {
                // An entry whose file was renamed or deleted in Finder has nothing to move, and the journal would
                // refuse the whole batch for it.
                let source = store.fileURL(r.path)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                // newNoteURL names a file in Notes/ itself; a note filed deeper would move up a folder, which is more
                // than a rename.
                let url = store.newNoteURL(title: r.title, format: NoteFormat(path: r.path) ?? .markdown, avoiding: taken)
                guard source.deletingLastPathComponent().standardizedFileURL == url.deletingLastPathComponent().standardizedFileURL else { continue }
                taken.insert(url.deletingPathExtension().lastPathComponent)
                moves.append(PlannedMove(from: try ctx.relative(course, r.path), to: ctx.relative(url)))
            }
        }
        guard !moves.isEmpty else { return }
        for move in moves { ctx.record(Change(.moved, move.from, to: move.to)) }
        if let batch = try NoteTitles.follow(moves, ctx, move: { try MoveJournal.apply(moves, in: ctx.gist.url, device: ctx.device, now: ctx.now) }) {
            ctx.made(batch)
        }
    }
}

/// Renames a note or moves it to another folder of Notes/ as `note retitle` renames: one `moves.jsonl` batch (`made`)
/// that `cleanup undo` turns back, with its entry's path, its heading and the links to it following. `to` is
/// Notes-relative; a name another note of the course has gets ` 2`, so the app passes the name it showed. The
/// command prints how to undo the move, so it is written by hand.
@Action("note mv", "노트 이름 바꾸기나 Notes 안의 다른 폴더로 옮기기. 노트의 첫 제목과 다른 노트의 링크도 따라 바뀐다", effect: .moves,
        confirm: "노트 {note}을(를) Notes/{to}(으)로 옮깁니다.", done: "노트 {note}을(를) Notes/{to}(으)로 옮겼습니다",
        phrases: ["노트 이름 바꾸기", "노트 이름 변경", "노트 옮기기", "노트 폴더로"], cli: .manual)
public struct NoteMove {
    @Arg var course: Course.ID
    @Arg var note: Note.Path
    /// Notes-relative, with or without the note's extension: `정리/증명`.
    @Arg var to: String

    public func run(_ ctx: ActionContext) throws {
        let store = try ctx.store(course)
        let source = try FolioActions.note(ctx, course: course, path: note)
        let name = ((to as NSString).lastPathComponent as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw ActionError.rule(String(localized: .errorNoteTitleEmpty)) }
        guard let target = store.movedNoteURL(source, to: to, in: try ctx.file(course)) else {
            throw ActionError.rule(String(localized: .errorNoteMovePlace(to)))
        }
        guard target.standardizedFileURL != source.url.standardizedFileURL else { return }
        let move = PlannedMove(from: ctx.relative(source.url), to: ctx.relative(target))
        ctx.record(Change(.moved, move.from, to: move.to))
        // The PDF this note's build wrote takes the new title in the same batch, so the next build finds it and one undo
        // puts both back. Another file at the new name stays and the PDF keeps its own: nothing is overwritten.
        let file = try ctx.file(course)
        let built = store.builtPDFMove(of: source, to: target, in: file).flatMap { $0.blocked ? nil : $0 }
        let pdf = try built.map { PlannedMove(from: try ctx.relative(course, $0.from), to: try ctx.relative(course, $0.to)) }
        if let pdf { ctx.record(Change(.moved, pdf.from, to: pdf.to)) }
        let moves = [move] + (pdf.map { [$0] } ?? [])
        guard let batch = try NoteTitles.follow(moves, ctx, move: { try MoveJournal.apply(moves, in: ctx.gist.url, device: ctx.device, now: ctx.now) })
        else { return }
        ctx.made(batch)
        if let built, let material = file.materials.first(where: { $0.path == built.from }) {
            try ctx.edit(course) { f in
                let url = store.fileURL(built.to)
                f.relinkMaterial(material.id, to: built.to, hash: material.hash, size: material.size, bookmark: try? url.bookmarkData(), device: ctx.device, now: ctx.now)
            }
        }
    }
}

/// A note's title is its file name, so moving a note's file renames it.
enum NoteTitles {
    /// Runs `move` (`moves` are GIST-relative, as `moves.jsonl` keeps them) and carries each moved note's title
    /// over: its entry's path, the heading its template wrote, its own links to files relative to its folder (a note
    /// moved to another folder), the links to it by title from the course's notes, and
    /// the shown title of links to it by ID (`[[note:<ID>|title]]`) from every course's notes, since an ID reaches
    /// across courses. Moves of other files pass through. The texts are read before `move`, so a dry run reports them
    /// from where they are. Returns what `move` returned; nothing on a dry run.
    static func follow(_ moves: [PlannedMove], _ ctx: ActionContext, move: () throws -> UUID) throws -> UUID? {
        // Loading every course is only worth it when a note moved; an undo of a folder cleanup shouldn't fail on one.
        guard moves.contains(where: { NoteFormat(path: $0.from) != nil }) else { return ctx.dryRun ? nil : try move() }
        struct Edit { var store: CourseStore, url: URL, text: String }
        // `note` is nil for a note file without an entry yet (moved in from an old folder, not opened): its heading,
        // pictures and the links to it by title follow all the same.
        typealias Rename = (note: UUID?, from: String, to: String)
        var renamed: [UUID: [Rename]] = [:]
        var edits: [Edit] = []
        var courses: [(id: UUID, store: CourseStore)] = []
        for store in try ctx.gist.courseStores() {
            let course = try store.load().model.course.id
            courses.append((course, store))
            let file = try ctx.file(course)
            let prefix = ctx.relative(store.url) + "/"
            let byPath = Dictionary(moves.filter { $0.from.hasPrefix(prefix) && $0.to.hasPrefix(prefix) }.map { (String($0.from.dropFirst(prefix.count)), String($0.to.dropFirst(prefix.count))) },
                                    uniquingKeysWith: { a, _ in a })
            let entries = Set(file.notes.map(\.path))
            let bare: [Rename] = byPath.filter { from, _ in
                !entries.contains(from) && from.hasPrefix(CourseFolder.notes.rawValue + "/") && NoteFormat(path: from) != nil
            }.map { (note: nil, from: $0.key, to: $0.value) }
            let notes: [Rename] = file.notes.compactMap { e in byPath[e.path].map { (note: e.id, from: e.path, to: $0) } } + bare
            if !notes.isEmpty { renamed[course] = notes }
        }
        guard !renamed.isEmpty else { return ctx.dryRun ? nil : try move() }
        let title = { (path: String) in ((path as NSString).lastPathComponent as NSString).deletingPathExtension }
        let folder = { (path: String) in (path as NSString).deletingLastPathComponent }
        let everywhere = renamed.values.flatMap { $0 }
        for (course, store) in courses {
            let notes = renamed[course] ?? []
            for n in try ctx.notes(course) where !notes.isEmpty || n.format == .markdown {
                let path = store.notePath(of: n.url)
                let own = notes.first { $0.from == path }
                var text = try store.read(n)
                let before = text
                if let own {
                    text = NoteTemplate.retitled(text, from: title(own.from), to: title(own.to), format: n.format)
                    text = NoteTemplate.rebased(text, from: folder(own.from), to: folder(own.to), format: n.format)
                }
                if n.format == .markdown {
                    for r in notes { text = WikiLink.retargeted(text, from: title(r.from), to: title(r.to)) }
                    for r in everywhere { if let id = r.note { text = WikiLink.retitled(text, note: id, from: title(r.from), to: title(r.to)) } }
                }
                if text != before { edits.append(Edit(store: store, url: own.map { store.fileURL($0.to) } ?? n.url, text: text)) }
            }
        }
        let batch = ctx.dryRun ? nil : try move()
        for (course, notes) in renamed where notes.contains(where: { $0.note != nil }) {
            try ctx.edit(course) { f in
                for n in notes { if let i = f.notes.firstIndex(where: { $0.id == n.note }) { f.notes[i].path = n.to } }
            }
        }
        for e in edits {
            try ctx.io(Change(.changed, ctx.relative(e.url))) { try e.store.write(NoteFile(url: e.url, meta: NoteMeta(id: nil)), text: e.text) }
        }
        return batch
    }
}

/// Sessions let go of the note first: a note left behind by a failed trash is harmless, a link to nothing is not.
/// The note goes to the Trash; its images stay in `assets/`, which other notes may share.
@Action("note rm", "노트를 휴지통으로. 회차의 연결도 뗀다", discussion: "그림은 assets에 남는다.", effect: .removes,
        confirm: "{note}을(를) 휴지통으로 옮깁니다.", done: "{note}을(를) 휴지통으로 옮겼습니다",
        examples: [#"folio note rm "EC4207/시험 메모" --dry-run"#], phrases: ["노트 삭제"])
public struct NoteRemove {
    /// 과목
    @Arg var course: Course.ID
    /// 노트
    @Arg var note: Note.Path

    public func run(_ ctx: ActionContext) throws {
        let file = try FolioActions.note(ctx, course: course, path: note)
        if let id = file.meta.id {
            try ctx.edit(course) { f in
                f.forgetNote(id)
                f.notes.removeAll { $0.id == id }
            }
        }
        let store = try ctx.store(course)
        try ctx.io(Change(.removed, ctx.relative(file.url))) { try store.trashNote(file) }
    }
}

// MARK: Quiz

/// Adds cards or replaces those with the same id. `movedFrom` is the unit an edited card left; it is taken out there
/// only after the new copy is saved. The command reads the cards from a JSON file.
@Action("quiz add", "JSON 파일의 카드를 넣거나 같은 ID의 카드를 바꾸기", done: "카드 {cards}을(를) 저장했습니다",
        phrases: ["카드 만들기", "퀴즈 추가"], cli: .manual)
public struct QuizCardSave {
    @Arg var course: Course.ID
    var cards: [QuizCard]
    var movedFrom: FolioDomain.Unit.ID?

    public func run(_ ctx: ActionContext) throws {
        let units = Set(try ctx.file(course).units.map(\.id))
        for unit in Set(cards.map(\.unitId)) {
            guard units.contains(unit) else { throw ActionError.notFound(String(localized: .errorNotFoundUnit)) }
            try ctx.editQuiz(course, unit: unit) { list in
                for var card in cards where card.unitId == unit {
                    card.touch(by: ctx.device, at: ctx.now)
                    if let i = list.firstIndex(where: { $0.id == card.id }) { list[i] = card } else { list.append(card) }
                }
            }
        }
        if let movedFrom, !cards.contains(where: { $0.unitId == movedFrom }) {
            let ids = Set(cards.map(\.id))
            try ctx.editQuiz(course, unit: movedFrom) { $0.removeAll { ids.contains($0.id) } }
        }
    }
}

/// Past attempts stay in the log. The command finds the card by its prompt among the unit's cards.
@Action("quiz rm", "카드 지우기. 풀이 기록은 남는다", effect: .removes, confirm: "단원 '{unit}'의 카드를 지웁니다. 풀이 기록은 남습니다.",
        done: "단원 '{unit}'의 카드를 지웠습니다", phrases: ["카드 삭제"], cli: .manual)
public struct QuizCardRemove {
    @Arg var course: Course.ID
    @Arg var unit: FolioDomain.Unit.ID
    @Arg var card: QuizCard.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.editQuiz(course, unit: unit) { list in
            _ = try index(card, in: list, .valueCard)
            list.removeAll { $0.id == card }
        }
    }
}

@Action("quiz record", "카드 풀이 결과를 기록", effect: .logs, done: "풀이를 기록했습니다",
        phrases: ["맞았", "틀렸", "맞힘", "퀴즈 풀이", "맞음", "틀림", "카드 결과"], cli: .manual)
public struct QuizRecord {
    @Arg var course: Course.ID
    var attempt: QuizAttemptEvent

    public func run(_ ctx: ActionContext) throws {
        let units = try ctx.file(course).units
        guard try units.contains(where: { try ctx.store(course).loadQuiz(unit: $0.id).model.cards.contains { $0.id == attempt.cardId } }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundCard))
        }
        try ctx.log(attempt, course: course)
    }
}

/// A new set, or the whole of one with the same id. The command builds the set from problem numbers.
@Action("problem-set add", "문제 번호로 문제 묶음 만들기", effect: .creates, done: "문제 묶음을 저장했습니다",
        phrases: ["문제 묶음 만들기", "연습문제 등록"], cli: .manual)
public struct ProblemSetSave {
    @Arg var course: Course.ID
    var set: ProblemSet

    public func run(_ ctx: ActionContext) throws {
        var set = set
        set.touch(by: ctx.device, at: ctx.now)
        try ctx.edit(course) { f in
            if let i = f.problemSets.firstIndex(where: { $0.id == set.id }) { f.problemSets[i] = set } else { f.problemSets.append(set) }
        }
        ctx.made(set.id)
    }
}

/// The number grid and unit links go; problem and solution files and past attempts stay.
@Action("problem-set rm", "문제 묶음 지우기. 문제 파일과 풀이 기록은 남는다", effect: .removes,
        confirm: "문제 묶음 '{set}'을(를) 지웁니다. 문제 파일과 풀이 기록은 남습니다.", done: "문제 묶음 '{set}'을(를) 지웠습니다",
        examples: [#"folio problem-set rm "EC4207/Exercise 1" --dry-run"#], phrases: ["문제 묶음 삭제"])
public struct ProblemSetRemove {
    /// 과목
    @Arg var course: Course.ID
    /// 묶음
    @Arg var set: ProblemSet.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(set, in: f.problemSets, .valueProblemSet)
            try f.remove(ProblemSet.self, set)
        }
    }
}

@Action("problem-set link", "문제를 단원에 연결하거나 떼기", done: "문제 묶음 '{set}'의 {number}번과 단원 '{unit}'의 연결을 바꿨습니다",
        examples: [#"folio problem-set link "EC4207/Exercise 1" 3a 매칭"#, #"folio problem-set link "EC4207/Exercise 1" 3a 매칭 --off"#],
        phrases: ["문제 단원 연결"])
public struct ProblemLinkUnit {
    /// 과목
    @Arg var course: Course.ID
    /// 묶음
    @Arg var set: ProblemSet.ID
    /// 문제 번호
    @Arg var number: String
    /// 같은 과목의 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 연결 떼기
    @Off("off") var linked = true

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            let s = try index(set, in: f.problemSets, .valueProblemSet)
            _ = try index(unit, in: f.units, .valueUnit)
            guard let p = f.problemSets[s].problems.firstIndex(where: { $0.number == number }) else { throw ActionError.notFound(String(localized: .errorNotFoundProblem(number))) }
            guard f.problemSets[s].problems[p].unitIds.contains(unit) != linked else { return }
            if linked { f.problemSets[s].problems[p].unitIds.append(unit) } else { f.problemSets[s].problems[p].unitIds.removeAll { $0 == unit } }
            f.problemSets[s].touch(by: ctx.device, at: ctx.now)
        }
    }
}

@Action("problem-set record", "문제 풀이 결과를 기록", effect: .logs, done: "풀이를 기록했습니다",
        phrases: ["풀었", "못 풀", "문제 풀이 결과", "풀었음", "못 풂"], cli: .manual)
public struct ProblemRecord {
    @Arg var course: Course.ID
    var attempt: ProblemAttemptEvent

    public func run(_ ctx: ActionContext) throws {
        guard let set = try ctx.file(course).problemSets.first(where: { $0.id == attempt.problemSetId }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundProblemSet))
        }
        guard set.problems.contains(where: { $0.number == attempt.number }) else { throw ActionError.notFound(String(localized: .errorNotFoundProblem(attempt.number))) }
        try ctx.log(attempt, course: course)
    }
}

// MARK: Review

/// The review result and the time spent, in this device's log.
@Action("review record", "단원 복습 결과와 걸린 시간을 기록", effect: .logs, done: "단원 '{unit}'의 복습을 기록했습니다",
        examples: [#"folio review record EC4207/매칭 good --start "2026-10-28 20:00" --end "2026-10-28 20:40""#],
        phrases: ["복습했", "공부했", "복습 완료", "복습 기록", "공부함"])
public struct ReviewRecord {
    /// 과목
    @Arg var course: Course.ID
    /// 단원
    @Arg var unit: FolioDomain.Unit.ID
    /// 결과
    @Arg var result: ReviewResult
    /// 시작 시각
    var start: Date
    /// 끝난 시각
    var end: Date

    public func run(_ ctx: ActionContext) throws {
        guard result != .skip else { throw ActionError.rule(String(localized: .errorReviewRecordSkip)) }
        guard end >= start else { throw ActionError.rule(String(localized: .errorReviewEndBeforeStart)) }
        try ctx.log(ReviewEvent(unitId: unit, result: result, seconds: Int(end.timeIntervalSince(start).rounded())), course: course, at: end)
        try ctx.log(StudySessionEvent(courseId: course, start: start, end: end, screen: "review"), course: course, at: end)
    }
}

/// Marks units as not needing review, one `skip` event each. The time counts only when the unit was open (the review
/// screen passes when it opened); skipped from a list, nothing was studied. Units may come from several courses, so
/// the command is written by hand.
@Action("review skip", "단원을 복습하지 않아도 되는 것으로 표시. 단원을 열어 본 시간이 있으면 공부 시간으로 남긴다. 여러 개면 확인을 받는다", effect: .logs,
        confirm: "단원 {units}의 복습을 건너뜁니다.", done: "단원 {units}을(를) 건너뛰었습니다",
        phrases: ["복습 안 해도", "복습 빼기", "복습 건너뛰기", "복습 필요 없음"], cli: .manual)
public struct ReviewSkip {
    public struct Target: Codable, Sendable, Equatable {
        public var course: UUID
        public var unit: UUID
        public init(course: UUID, unit: UUID) {
            self.course = course
            self.unit = unit
        }
    }
    var units: [Target]
    /// 단원을 연 시각. 끝 시각과 함께, 단원 하나에만 준다
    var start: Date?
    /// 건너뛴 시각
    var end: Date?

    public func run(_ ctx: ActionContext) throws {
        guard let start, let end else {
            guard start == nil, end == nil else { throw ActionError.rule(String(localized: .errorReviewSkipTimes)) }
            for t in units { try ctx.log(ReviewEvent(unitId: t.unit, result: .skip, seconds: 0), course: t.course) }
            return
        }
        guard units.count == 1, let t = units.first else { throw ActionError.rule(String(localized: .errorReviewSkipTimes)) }
        guard end >= start else { throw ActionError.rule(String(localized: .errorReviewEndBeforeStart)) }
        try ctx.log(ReviewEvent(unitId: t.unit, result: .skip, seconds: Int(end.timeIntervalSince(start).rounded())), course: t.course, at: end)
        try ctx.log(StudySessionEvent(courseId: t.course, start: start, end: end, screen: "review"), course: t.course, at: end)
    }
}
