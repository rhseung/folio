import FolioActions
import FolioDomain
import FolioStorage
import Foundation

struct CourseRef: Identifiable {
    var course: Course
    var store: CourseStore
    var file: CourseFile
    var code: String
    var color = ""

    var id: UUID { course.id }
    var tag: String { code.course(color) }
}

final class Resolver {
    let ctx: ActionContext
    init(_ ctx: ActionContext) { self.ctx = ctx }

    lazy var courses: [CourseRef] = {
        let catalog = (try? ctx.catalog()) ?? Catalog()
        func code(_ c: Course, folder: String) -> String {
            if let token = folder.split(separator: " ").first, StandardLayout.isCourseFolderName(folder) { return String(token) }
            let prefix = c.codes.first.flatMap { id in catalog.codes.first { $0.id == id }?.prefix } ?? ""
            return prefix + (c.number.split(separator: "-").first.map(String.init) ?? "")
        }
        let stores = (try? ctx.gist.courseStores()) ?? []
        var refs = stores.compactMap { s -> CourseRef? in
            guard let f = try? s.load().model else { return nil }
            return CourseRef(course: f.course, store: s, file: f, code: code(f.course, folder: s.url.lastPathComponent))
        }
        // 앱이 세는 순서(`Workspace.courses(in:)`)와 같아야 색이 없는 과목이 같은 프리셋을 받는다.
        for i in refs.indices {
            let siblings = refs.filter { $0.course.semesterId == refs[i].course.semesterId }.sorted { $0.course.title < $1.course.title }
            refs[i].color = CourseColor.token(refs[i].course.color, position: siblings.firstIndex { $0.id == refs[i].id } ?? 0)
        }
        return refs
    }()

    lazy var semesters: [Semester] = ((try? ctx.transcript().semesters) ?? []).sorted { $0.order < $1.order }

    func currentSemester() throws -> Semester {
        let today = LocalDate(ctx.now, in: ctx.calendar)
        if let s = semesters.current(on: today) { return s }
        throw CLIError(exit: .notFound, message: String(localized: .resolveNoSemester), hints: [String(localized: .resolveNoSemesterHint)])
    }

    func semester(_ ref: String?) throws -> Semester {
        guard let ref else { return try currentSemester() }
        return try pick(
            ref, semesters, what: "학기", names: { [$0.folder?.name ?? "", $0.source ?? "", "\($0.year) \($0.term.rawValue)"] },
            ref: { $0.folder?.name ?? $0.source ?? $0.id.uuidString })
    }

    func course(_ ref: String) throws -> CourseRef {
        try pick(ref, courses, what: "과목", names: { [$0.code, $0.course.title, $0.store.url.lastPathComponent] }, ref: \.code)
    }

    func split(_ ref: String, course: String? = nil) throws -> (CourseRef, String) {
        if let course { return (try self.course(course), ref) }
        guard let slash = ref.firstIndex(of: "/") else {
            if ref.isEmpty || Picker.allowed, let c = try? self.course(ref) { return (c, "") }
            throw CLIError(
                exit: .usage, message: String(localized: .resolveNeedCourse(ref)), hints: [String(localized: .resolveNeedCourseHint(ref))])
        }
        return (try self.course(String(ref[..<slash])), String(ref[ref.index(after: slash)...]))
    }

    func session(_ name: String, in c: CourseRef) throws -> Session {
        let f = c.file
        return try pick(
            name, f.sessions, what: "회차", names: { f.references(of: $0, calendar: self.ctx.calendar) },
            ref: { "\(c.code)/\(f.reference(of: $0, calendar: self.ctx.calendar))" })
    }

    func recording(_ name: String, in c: CourseRef) throws -> Recording {
        let f = c.file
        let session = { (r: Recording) in
            r.sessionId.flatMap { id in f.sessions.first { $0.id == id } }.map { f.references(of: $0, calendar: self.ctx.calendar) } ?? []
        }
        return try pick(
            name, f.recordings, what: "녹음", names: { session($0) + [$0.file, ($0.file as NSString).lastPathComponent] },
            ref: { "\(c.code)/\(($0.file as NSString).lastPathComponent)" })
    }

    func exam(_ name: String, in c: CourseRef) throws -> Exam {
        try pick(name, c.file.exams, what: "시험", names: { [$0.title] }, ref: { "\(c.code)/\($0.title)" })
    }

    func unit(_ name: String, in c: CourseRef) throws -> FolioDomain.Unit {
        try pick(name, c.file.units, what: "단원", names: { [$0.title] }, ref: { "\(c.code)/\($0.title)" })
    }

    func assignment(_ name: String, in c: CourseRef) throws -> Assignment {
        try pick(name, c.file.assignments, what: "과제", names: { [$0.title] }, ref: { "\(c.code)/\($0.title)" })
    }

    func component(_ name: String, in c: CourseRef) throws -> GradeComponent {
        try pick(name, c.file.components, what: "성적 항목", names: { [$0.name] }, ref: { "\(c.code)/\($0.name)" })
    }

    func material(_ name: String, in c: CourseRef) throws -> Material {
        try pick(
            name, c.file.materials, what: "자료", names: { [$0.path, ($0.path as NSString).lastPathComponent] },
            ref: { "\(c.code)/\($0.path)" })
    }

    func problemSet(_ name: String, in c: CourseRef) throws -> ProblemSet {
        try pick(name, c.file.problemSets, what: "문제 묶음", names: { [$0.title] }, ref: { "\(c.code)/\($0.title)" })
    }

    func note(_ name: String, in c: CourseRef) throws -> NoteFile {
        let store = c.store
        let notes = try store.notes()
        let path = { (n: NoteFile) in store.coursePath(of: n.url) ?? n.url.lastPathComponent }
        return try pick(name, notes, what: "노트", id: { $0.meta.id }, names: { [path($0), $0.title] }, ref: { "\(c.code)/\(path($0))" })
    }

    // MARK: Matching

    func pick<T: Identifiable>(_ ref: String, _ items: [T], what: String, names: (T) -> [String], ref label: (T) -> String) throws -> T
    where T.ID == UUID {
        try pick(ref, items, what: what, id: { $0.id }, names: names, ref: label)
    }

    func pick<T>(_ ref: String, _ items: [T], what: String, id: (T) -> UUID?, names: (T) -> [String], ref label: (T) -> String) throws -> T
    {
        if ref.isEmpty {
            guard !items.isEmpty else { throw CLIError(exit: .notFound, message: String(localized: .resolveEmpty(what))) }
            if let chosen = Picker.choose(items.map(label), prompt: what) { return items[items.map(label).firstIndex(of: chosen)!] }
            throw CLIError(
                exit: .usage, message: String(localized: .resolveNeed(what)), candidates: items.count <= 12 ? items.map(label) : [],
                hints: [String(localized: .resolvePickHint)])
        }
        if let uuid = UUID(uuidString: ref) {
            if let hit = items.first(where: { id($0) == uuid }) { return hit }
            throw CLIError(exit: .notFound, message: String(localized: .resolveNotFound(what, ref)))
        }
        let key = Self.normalized(ref)
        let exact = items.filter { names($0).contains { Self.normalized($0) == key } }
        let hits = exact.isEmpty ? items.filter { names($0).contains { !key.isEmpty && Self.normalized($0).contains(key) } } : exact
        if hits.count == 1 { return hits[0] }
        if hits.count > 1, let chosen = Picker.choose(hits.map(label), prompt: what) {
            return hits[hits.map(label).firstIndex(of: chosen)!]
        }
        if hits.isEmpty {
            throw CLIError(
                exit: .notFound, message: String(localized: .resolveNotFound(what, ref)),
                candidates: items.count <= 12 ? items.map(label) : [])
        }
        throw CLIError(exit: .notFound, message: String(localized: .resolveAmbiguous(what, ref)), candidates: hits.map(label))
    }

    func many(_ given: [String], from names: [String], what: String) throws -> [String] {
        guard given.isEmpty else { return given }
        let picked = Picker.chooseMany(names, prompt: what)
        guard picked.isEmpty else { return picked }
        throw CLIError(exit: .usage, message: String(localized: .resolveNeedMany(what)), hints: [String(localized: .resolvePickManyHint)])
    }

    static func normalized(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace }
    }
}

// 에이전트가 기다리는 프롬프트가 아니라 종료 코드 3을 받도록, fzf는 사람이 터미널에 있을 때만 쓴다.
enum Picker {
    nonisolated(unsafe) static var allowed = false
    nonisolated(unsafe) static var gist: String?

    static func enable(_ options: GlobalOptions) {
        // 테스트는 overrides로 명령을 나란히 돌리는데, 각각 이 static을 보호 없이 쓰면 테스트 프로세스가 멈췄다.
        guard CLI.overrides == nil else { return }
        let env = ProcessInfo.processInfo.environment
        allowed = !options.json && !options.noPick && env["FOLIO_NO_PICK"] == nil && isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
        gist = try? CLI.gist(options).url.path
    }

    static func choose(_ lines: [String], prompt: String) -> String? {
        run(lines, prompt: prompt, multi: false).first
    }

    static func chooseMany(_ lines: [String], prompt: String) -> [String] {
        run(lines, prompt: prompt, multi: true)
    }

    static let previews = [
        "과목": "course", "학기": "semester", "회차": "session", "시험": "exam", "단원": "unit", "과제": "assignment", "노트": "note", "자료": "material",
    ]

    static func run(_ lines: [String], prompt: String, multi: Bool) -> [String] {
        guard allowed else { return [] }
        let quoted = { (s: String) in "'" + s.replacing("'", with: "'\\''") + "'" }
        let folder = gist.map { " --gist " + quoted($0) } ?? ""
        let preview = previews[prompt].map { ["--preview=\(quoted(CommandLine.arguments[0])) \($0) show {}\(folder)"] } ?? []
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/env")
        let extra = (ProcessInfo.processInfo.environment["FOLIO_FZF_OPTS"] ?? "").split(separator: " ").map(String.init)
        p.arguments = ["fzf", "--height=40%", "--reverse", "--prompt=\(prompt)> "] + (multi ? ["--multi"] : []) + preview + extra
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        guard (try? p.run()) != nil else { return [] }
        input.fileHandleForWriting.write(Data(lines.joined(separator: "\n").utf8))
        try? input.fileHandleForWriting.close()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return [] }
        let picked = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(
            String.init)
        return picked.filter(lines.contains)
    }
}
