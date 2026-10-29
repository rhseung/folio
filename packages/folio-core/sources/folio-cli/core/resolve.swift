import FolioActions
import FolioDomain
import FolioStorage
import Foundation

/// A course as the CLI sees it: one with a folder has a file, a record-only one (credited terms) lives in transcript.json.
struct CourseRef: Identifiable {
    var course: Course
    var store: CourseStore?
    var file: CourseFile?
    /// `EC4207`: the folder's code, or the catalog's prefix and number.
    var code: String
    /// The color token the app shows this course in: its own, or the preset for its place in the semester.
    var color = ""

    var id: UUID { course.id }
    /// The code in the course's color, for tables and lists a person reads.
    var tag: String { code.course(color) }

    func requireFile() throws -> CourseFile {
        guard let file else { throw CLIError(exit: .rule, message: "\(course.title)은(는) 과목 폴더가 없습니다") }
        return file
    }
}

/// Turns what people type (`EC4207`, `9주차-1`, `Quiz1`, a UUID) into ids (docs/SPEC.md "명령 구조").
final class Resolver {
    let ctx: ActionContext
    init(_ ctx: ActionContext) { self.ctx = ctx }

    lazy var courses: [CourseRef] = {
        let catalog = (try? ctx.catalog()) ?? Catalog()
        func code(_ c: Course, folder: String?) -> String {
            if let folder, let token = folder.split(separator: " ").first, StandardLayout.isCourseFolderName(folder) { return String(token) }
            let prefix = c.codes.first.flatMap { id in catalog.codes.first { $0.id == id }?.prefix } ?? ""
            return prefix + (c.number.split(separator: "-").first.map(String.init) ?? "")
        }
        let stores = (try? ctx.gist.courseStores()) ?? []
        var refs = stores.compactMap { s -> CourseRef? in
            guard let f = try? s.load().model else { return nil }
            return CourseRef(course: f.course, store: s, file: f, code: code(f.course, folder: s.url.lastPathComponent))
        }
        let known = Set(refs.map(\.id))
        for c in ((try? ctx.transcript().courses) ?? []) where !known.contains(c.id) {
            refs.append(CourseRef(course: c, code: code(c, folder: nil)))
        }
        // Same order the app counts in (Workspace.courses(in:)), so a course without a color gets the same preset.
        for i in refs.indices {
            let siblings = refs.filter { $0.course.semesterId == refs[i].course.semesterId }.sorted { $0.course.title < $1.course.title }
            refs[i].color = CourseColor.token(refs[i].course.color, position: siblings.firstIndex { $0.id == refs[i].id } ?? 0)
        }
        return refs
    }()

    lazy var semesters: [Semester] = ((try? ctx.transcript().semesters) ?? []).sorted { $0.order < $1.order }

    /// The semester holding today, else the latest that has started, else the latest.
    func currentSemester() throws -> Semester {
        let today = LocalDate(ctx.now, in: ctx.calendar)
        if let s = semesters.last(where: { ($0.start.map { $0 <= today } ?? false) && ($0.end.map { today <= $0 } ?? true) }) { return s }
        if let s = semesters.last(where: { $0.start.map { $0 <= today } ?? false }) ?? semesters.last { return s }
        throw CLIError(exit: .notFound, message: "학기가 없습니다", hints: ["folio semester add 2026 가을"])
    }

    func semester(_ ref: String?) throws -> Semester {
        guard let ref else { return try currentSemester() }
        return try pick(ref, semesters, what: "학기", names: { [$0.folder?.name ?? "", "\($0.year) \($0.term.rawValue)"] }, ref: { $0.folder?.name ?? $0.id.uuidString })
    }

    func course(_ ref: String) throws -> CourseRef {
        try pick(ref, courses, what: "과목", names: { [$0.code, $0.course.title, $0.store?.url.lastPathComponent ?? ""] }, ref: \.code)
    }

    /// `EC4207/9주차-1`, or the item alone when `course` is given separately. An empty ref, or a course alone, leaves
    /// the item empty so the kind's lookup picks it with fzf.
    func split(_ ref: String, course: String? = nil) throws -> (CourseRef, String) {
        if let course { return (try self.course(course), ref) }
        guard let slash = ref.firstIndex(of: "/") else {
            if ref.isEmpty || Picker.allowed, let c = try? self.course(ref) { return (c, "") }
            throw CLIError(exit: .usage, message: "과목을 함께 적어 주세요: <과목>/\(ref)", hints: ["예: EC4207/\(ref)"])
        }
        return (try self.course(String(ref[..<slash])), String(ref[ref.index(after: slash)...]))
    }

    func session(_ name: String, in c: CourseRef) throws -> Session {
        let f = try c.requireFile()
        return try pick(name, f.sessions, what: "회차", names: { [f.name(of: $0)] }, ref: { "\(c.code)/\(f.name(of: $0))" })
    }

    func exam(_ name: String, in c: CourseRef) throws -> Exam {
        try pick(name, try c.requireFile().exams, what: "시험", names: { [$0.title] }, ref: { "\(c.code)/\($0.title)" })
    }

    func unit(_ name: String, in c: CourseRef) throws -> FolioDomain.Unit {
        try pick(name, try c.requireFile().units, what: "단원", names: { [$0.title] }, ref: { "\(c.code)/\($0.title)" })
    }

    func assignment(_ name: String, in c: CourseRef) throws -> Assignment {
        try pick(name, try c.requireFile().assignments, what: "과제", names: { [$0.title] }, ref: { "\(c.code)/\($0.title)" })
    }

    func component(_ name: String, in c: CourseRef) throws -> GradeComponent {
        try pick(name, try c.requireFile().components, what: "성적 항목", names: { [$0.name] }, ref: { "\(c.code)/\($0.name)" })
    }

    func material(_ name: String, in c: CourseRef) throws -> Material {
        try pick(name, try c.requireFile().materials, what: "자료", names: { [$0.path, ($0.path as NSString).lastPathComponent] }, ref: { "\(c.code)/\($0.path)" })
    }

    func problemSet(_ name: String, in c: CourseRef) throws -> ProblemSet {
        try pick(name, try c.requireFile().problemSets, what: "문제 묶음", names: { [$0.title] }, ref: { "\(c.code)/\($0.title)" })
    }

    func note(_ name: String, in c: CourseRef) throws -> NoteFile {
        guard let store = c.store else { throw CLIError(exit: .rule, message: "\(c.course.title)은(는) 과목 폴더가 없습니다") }
        let notes = try store.notes()
        let path = { (n: NoteFile) in store.coursePath(of: n.url) ?? n.url.lastPathComponent }
        return try pick(name, notes, what: "노트", id: { $0.meta.id }, names: { [path($0), $0.title] }, ref: { "\(c.code)/\(path($0))" })
    }

    // MARK: Matching

    func pick<T: Identifiable>(_ ref: String, _ items: [T], what: String, names: (T) -> [String], ref label: (T) -> String) throws -> T where T.ID == UUID {
        try pick(ref, items, what: what, id: { $0.id }, names: names, ref: label)
    }

    /// A UUID, then an exact name (ignoring case and spacing), then a name that contains it. More than one match is an
    /// error listing them, never a guess.
    func pick<T>(_ ref: String, _ items: [T], what: String, id: (T) -> UUID?, names: (T) -> [String], ref label: (T) -> String) throws -> T {
        if ref.isEmpty {
            guard !items.isEmpty else { throw CLIError(exit: .notFound, message: "\(what)이(가) 없습니다") }
            if let chosen = Picker.choose(items.map(label), prompt: what) { return items[items.map(label).firstIndex(of: chosen)!] }
            throw CLIError(exit: .usage, message: "\(what)을(를) 주세요", candidates: items.count <= 12 ? items.map(label) : [],
                           hints: ["터미널에서 fzf가 있으면 빼고 실행해 고를 수 있다"])
        }
        if let uuid = UUID(uuidString: ref) {
            if let hit = items.first(where: { id($0) == uuid }) { return hit }
            throw CLIError(exit: .notFound, message: "\(what)을(를) 찾지 못했습니다: \(ref)")
        }
        let key = Self.normalized(ref)
        let exact = items.filter { names($0).contains { Self.normalized($0) == key } }
        let hits = exact.isEmpty ? items.filter { names($0).contains { !key.isEmpty && Self.normalized($0).contains(key) } } : exact
        if hits.count == 1 { return hits[0] }
        if hits.count > 1, let chosen = Picker.choose(hits.map(label), prompt: what) { return hits[hits.map(label).firstIndex(of: chosen)!] }
        if hits.isEmpty {
            throw CLIError(exit: .notFound, message: "\(what)을(를) 찾지 못했습니다: \(ref)", candidates: items.count <= 12 ? items.map(label) : [])
        }
        throw CLIError(exit: .notFound, message: "\(what) '\(ref)'이(가) 여러 개에 맞습니다", candidates: hits.map(label))
    }

    /// `given`, or when it is empty several names picked at a terminal; otherwise a usage error.
    func many(_ given: [String], from names: [String], what: String) throws -> [String] {
        guard given.isEmpty else { return given }
        let picked = Picker.chooseMany(names, prompt: what)
        guard picked.isEmpty else { return picked }
        throw CLIError(exit: .usage, message: "\(what)을(를) 하나 이상 주세요", hints: ["터미널에서 fzf가 있으면 빼고 실행해 여러 개를 고를 수 있다"])
    }

    static func normalized(_ s: String) -> String {
        s.lowercased().filter { !$0.isWhitespace }
    }
}

/// fzf for ambiguous names, only where a person is at the terminal: an agent must get exit 3, not a prompt that waits
/// (docs/SPEC.md "fzf와 셸 완성").
enum Picker {
    nonisolated(unsafe) static var allowed = false
    nonisolated(unsafe) static var gist: String?

    static func enable(_ options: GlobalOptions) {
        let env = ProcessInfo.processInfo.environment
        allowed = !options.json && !options.noPick && env["FOLIO_NO_PICK"] == nil && isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
        gist = try? CLI.gist(options).url.path
    }

    static func choose(_ lines: [String], prompt: String) -> String? {
        run(lines, prompt: prompt, multi: false).first
    }

    /// Tab marks several; nothing picked is an empty list.
    static func chooseMany(_ lines: [String], prompt: String) -> [String] {
        run(lines, prompt: prompt, multi: true)
    }

    /// The `show` that previews a picked line, by what is being picked.
    static let previews = ["과목": "course", "학기": "semester", "회차": "session", "시험": "exam", "단원": "unit", "과제": "assignment", "노트": "note", "자료": "material"]

    static func run(_ lines: [String], prompt: String, multi: Bool) -> [String] {
        guard allowed else { return [] }
        // The same binary that is running, so a preview never reads another install's data.
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
        let picked = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init)
        return picked.filter(lines.contains)
    }
}
