import ArgumentParser
import CryptoKit
import FolioActions
import FolioDomain
import FolioStorage
import Foundation

extension Resolver {
    /// The note and its course-relative path, the form `note write`, `adopt` and `rm` take.
    func notePath(_ ref: String) throws -> (CourseRef, NoteFile, String) {
        let (c, name) = try split(ref)
        let n = try note(name, in: c)
        return (c, n, c.store?.coursePath(of: n.url) ?? name)
    }
}

/// What `note show --json` reports and `note write --expect` checks: the note as it was read.
func contentHash(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}

/// Text from a file, or from standard input for `-`.
func readText(_ source: String) throws -> String {
    if source == "-" { return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self) }
    do {
        return try String(contentsOf: URL(filePath: absolute(source)), encoding: .utf8)
    } catch {
        throw CLIError(exit: .usage, message: "파일을 읽지 못했습니다: \(source)")
    }
}

struct NoteCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "note", abstract: "과목 노트: 목록, 읽기, 만들기, 쓰기, 연결",
        subcommands: [List.self, Show.self, Add.self, Write.self, Link.self] + GeneratedCommands.note)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목의 노트 목록", discussion: """
            예시:
              folio note list EC4207
              folio note list EC4207 --lines
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: "머리글 없이 한 줄에 하나, 탭으로 나눠서") var lines = false

        struct Item: Encodable {
            var id: UUID?
            var path: String
            var kind: NoteKind
            var sessionId: UUID?
            var examId: UUID?
            var unitIds: [UUID]
        }

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            guard let store = c.store else { throw CLIError(exit: .rule, message: "\(c.course.title)은(는) 과목 폴더가 없습니다") }
            let notes = try store.notes()
            let path = { (n: NoteFile) in store.coursePath(of: n.url) ?? n.url.lastPathComponent }
            if g.json {
                return try printJSON(notes.map { Item(id: $0.meta.id, path: path($0), kind: $0.meta.kind, sessionId: $0.meta.sessionId, examId: $0.meta.examId, unitIds: $0.meta.unitIds) })
            }
            let f = c.file
            let session = { (n: NoteFile) in n.meta.sessionId.flatMap { id in f?.sessions.first { $0.id == id } }.map { f!.name(of: $0) } ?? "" }
            if lines {
                for n in notes { line(["\(c.code)/\(path(n))", n.title, n.meta.kind.rawValue, session(n)]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: ["노트", "종류", "회차", "경로"], shrink: [3])
            for n in notes { t.rows.append([n.title, n.meta.kind.rawValue, session(n), path(n)]) }
            t.print()
            footer(notes.count)
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "노트 파일을 그대로 출력", discussion: """
            예시:
              folio note show EC4207/2주차-1
              folio note show EC4207/Notes/2주차-1.md
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<노트 제목 또는 경로>", valueName: "note"), completion: Complete.notes) var note: String = ""

        struct Body: Encodable {
            var id: UUID?
            var path: String
            var text: String
            /// Pass to `note write --expect` so a change made meanwhile isn't overwritten.
            var hash: String
        }

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, n, path) = try r.notePath(note)
            let text = try c.store!.read(n)
            if g.json { return try printJSON(Body(id: n.meta.id, path: path, text: text, hash: contentHash(text))) }
            say(text)
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Notes 폴더에 노트 만들기. 본문을 주지 않으면 종류의 템플릿", discussion: """
            예시:
              folio note add EC4207 "매칭 정리" --kind topic
              echo "# 메모" | folio note add EC4207 "시험 메모" --body -
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String
        @Argument(help: ArgumentHelp("제목. 파일 이름이 된다", valueName: "title")) var title: String
        @Option(help: "종류") var kind: NoteKind = .free
        @Option(help: ArgumentHelp("본문 파일. -이면 표준 입력", valueName: "file"), completion: .file()) var body: String?
        @Option(help: .hidden) var id: UUID?

        func run() throws {
            let ctx = try CLI.context(g)
            let c = try Resolver(ctx).course(course)
            try perform(spec: NoteAdd(id: id ?? UUID(), course: c.id, title: title, kind: kind, body: try body.map(readText)), g, ctx: ctx)
        }
    }

    struct Write: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "노트 파일 전체를 바꾸기. frontmatter까지 그대로 쓴다", discussion: """
            --expect에 `folio note show --json`의 hash를 주면, 그 뒤에 앱이나 다른 기기에서 노트가 바뀌었을 때 쓰지 않고 종료 코드 6으로 끝난다.
            에이전트는 읽고 고쳐 쓸 때 항상 --expect를 준다.

            예시:
              folio note write EC4207/2주차-1 --file 2주차-1.md
              folio note show EC4207/2주차-1 | sed 's/매칭/짝짓기/' | folio note write EC4207/2주차-1 --file -
              folio note write EC4207/2주차-1 --file 2주차-1.md --expect 9f2c…
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<노트>", valueName: "note"), completion: Complete.notes) var note: String = ""
        @Option(help: ArgumentHelp("새 내용 파일. -이면 표준 입력", valueName: "file"), completion: .file()) var file: String
        @Option(help: ArgumentHelp("읽을 때의 hash(note show --json). 다르면 쓰지 않는다", valueName: "hash")) var expect: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let (c, n, path) = try Resolver(ctx).notePath(note)
            var expected: String?
            if let expect {
                let current = try c.store!.read(n)
                guard contentHash(current) == expect.lowercased() else {
                    throw CLIError(exit: .conflict, message: "노트가 읽은 뒤에 바뀌었습니다: \(path)",
                                   hints: ["folio note show \(c.code)/\(path) --json으로 다시 읽고 고쳐서 쓰기"])
                }
                // The action checks again right before writing, so a change between here and there is caught too.
                expected = current
            }
            try perform(spec: NoteWrite(course: c.id, note: path, text: try readText(file), expected: expected), g, ctx: ctx)
        }
    }

    struct Link: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "노트의 종류와 회차·시험·단원 연결 정하기", discussion: """
            러프·복습 노트는 --session, 시험 종합 정리는 --exam, 주제 노트는 --unit을 받는다. 종류를 바꾸면 예전 연결은 떨어진다.

            예시:
              folio note link EC4207/2주차-1 --kind review --session 2주차-1
              folio note link "EC4207/매칭 정리" --kind topic --unit 매칭 --unit "이분 그래프"
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<노트>", valueName: "note"), completion: Complete.notes) var note: String = ""
        @Option(help: "종류") var kind: NoteKind
        @Option(help: ArgumentHelp("회차", valueName: "session"), completion: Complete.sessions) var session: String?
        @Option(help: ArgumentHelp("시험", valueName: "exam"), completion: Complete.exams) var exam: String?
        @Option(help: ArgumentHelp("단원. 여러 번 줄 수 있다", valueName: "unit"), completion: Complete.units) var unit: [String] = []

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(note)
            try perform(spec: NoteLink(course: c.id, note: try r.noteID(name, in: c), kind: kind, session: try session.map { try r.session(c.local($0), in: c).id },
                                 exam: try exam.map { try r.exam(c.local($0), in: c).id }, units: try unit.map { try r.unit(c.local($0), in: c).id }),
                        g, ctx: ctx)
        }
    }
}
