import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension MaterialRole: ExpressibleByArgument {}

extension CourseRef {
    /// A second ref in the same course may be written with or without `<course>/` in front.
    func local(_ ref: String) -> String {
        ref.hasPrefix(code + "/") ? String(ref.dropFirst(code.count + 1)) : ref
    }
}

/// An absolute path for a file argument, which may be relative to where the command runs.
func absolute(_ path: String) -> String {
    URL(filePath: (path as NSString).expandingTildeInPath, relativeTo: URL(filePath: FileManager.default.currentDirectoryPath + "/")).standardizedFileURL.path
}

struct MaterialCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "material", abstract: "자료 파일: 추적, 회차·단원 연결, 이동과 휴지통",
        subcommands: [List.self, Show.self, Link.self, Status.self, Relink.self, Track.self, Import.self, Move.self]
            + GeneratedCommands.material)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목의 자료 목록", discussion: """
            예시:
              folio material list EC4207
              folio material list EC4207 --lines
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String = ""
        @Flag(help: "무시한 자료까지") var all = false
        @Flag(help: "머리글 없이 한 줄에 하나, 탭으로 나눠서") var lines = false

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let c = try r.course(course)
            let f = try c.requireFile()
            let materials = f.materials.sorted { $0.path < $1.path }.filter { all || $0.status != .ignored }
            if g.json { return try printJSON(materials) }
            func sessions(_ m: Material) -> String {
                f.sessions.filter { s in s.materials.contains { $0.materialId == m.id } }.map { f.name(of: $0) }.joined(separator: ", ")
            }
            if lines {
                for m in materials { line(["\(c.code)/\(m.path)", m.role?.rawValue ?? "", m.status.rawValue, sessions(m)]) }
                return
            }
            courseHeader(c, catalog: try? r.ctx.catalog())
            var t = Table(header: ["경로", "역할", "상태", "회차"], shrink: [3])
            for m in materials {
                t.rows.append([m.path, m.role?.rawValue ?? "", m.status.rawValue.toned, sessions(m)])
            }
            t.print()
            footer(materials.count, hidden: all ? nil : "--all로 무시한 것까지")
        }
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "자료 하나의 자세한 내용", discussion: """
            예시:
              folio material show EC4207/Lectures/05_Matchings.pdf
              folio material show EC4207/05_Matchings.pdf
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<경로 또는 파일 이름>", valueName: "material"), completion: Complete.materials) var material: String = ""

        func run() throws {
            let r = Resolver(try CLI.context(g))
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            if g.json { return try printJSON(m) }
            let f = try c.requireFile()
            courseHeader(c, catalog: try? r.ctx.catalog())
            let url = c.store.map { $0.url.appending(path: m.path) }
            say((url.map { m.path.link($0) } ?? m.path).styled(.bold))
            say("  역할  \(m.role?.rawValue ?? "-")")
            say("  상태  \(m.status.rawValue.toned)")
            let sessions = f.sessionLinks(of: m.id)
            if !sessions.isEmpty {
                say("  회차")
                for (s, link) in sessions {
                    let pages = link.firstPage.map { first in " p.\(first)\(link.lastPage.map { "-\($0)" } ?? "")" } ?? ""
                    say("    \(f.name(of: s))\(pages)")
                }
            }
            let units = m.unitIds.compactMap { id in f.units.first { $0.id == id }?.title }
            if !units.isEmpty {
                say("  단원")
                for u in units { say("    \(u)") }
            }
        }
    }

    struct Link: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "자료를 회차에 연결하거나 떼기", discussion: """
            예시:
              folio material link EC4207/05_Matchings.pdf 9주차-1 --pages 3-12
              folio material link EC4207/05_Matchings.pdf 9주차-1 --off
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<자료>", valueName: "material"), completion: Complete.materials) var material: String
        @Argument(help: ArgumentHelp("같은 과목의 회차. 예: 9주차-1", valueName: "session"), completion: Complete.sessions) var session: String = ""
        @Option(help: ArgumentHelp("쪽 범위. 예: 3-12 또는 5", valueName: "pages")) var pages: String?
        @Flag(help: "연결 떼기") var off = false

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            let s = try r.session(c.local(session), in: c)
            let bounds = pages?.split(separator: "-").compactMap { Int($0) } ?? []
            guard pages == nil || (1...2).contains(bounds.count) else { throw CLIError(exit: .usage, message: "쪽 범위는 3-12 또는 5 형식입니다") }
            try perform(spec: MaterialLinkSession(course: c.id, material: m.id, session: s.id, linked: !off, firstPage: bounds.first, lastPage: bounds.last),
                        g, ctx: ctx)
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "자료의 상태 바꾸기. 여러 개면 확인을 받는다", discussion: """
            예시:
              folio material status ignored EC4207/Seating.pdf
              folio material status classified EC4207/Problems.pdf Guideline.pdf
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: "상태") var status: MaterialStatus
        @Argument(help: ArgumentHelp("<과목>/<자료>. 둘째부터는 자료만 써도 된다", valueName: "material"), completion: Complete.materials) var materials: [String]

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            guard let first = materials.first else { throw CLIError(exit: .usage, message: "자료를 주세요") }
            let (c, name) = try r.split(first)
            let ids = try ([name] + materials.dropFirst().map { c.local($0) }).map { try r.material($0, in: c).id }
            try perform(spec: MaterialStatusSet(course: c.id, materials: ids, status: status), g, ctx: ctx)
        }
    }

    struct Relink: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "사라진 자료를 과목 폴더 안의 다른 파일에 다시 잇기", discussion: """
            예시:
              folio material relink EC4207/05_Matchings.pdf "Lectures/05_Matchings v2.pdf"
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<자료>", valueName: "material"), completion: Complete.materials) var material: String
        @Argument(help: ArgumentHelp("새 파일. 과목 폴더 기준 경로나 절대 경로", valueName: "file"), completion: .file()) var file: String

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            let path = file.hasPrefix("/") || file.hasPrefix("~") ? absolute(file) : c.store?.url.appending(path: file).path ?? absolute(file)
            try perform(spec: MaterialRelink(course: c.id, material: m.id, file: path), g, ctx: ctx)
        }
    }

    struct Track: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "과목 폴더의 새 파일을 등록하고 과제 폴더에 과제를 만든다", discussion: """
            옮기거나 이름을 바꾸지 않는다. 과목을 빼면 모든 과목에 한다. 지난 학기의 새 과제는 제출함으로 둔다.

            예시:
              folio material track EC4207
              folio material track --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목. 빼면 모든 과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let id = try course.map { try Resolver(ctx).course($0).id }
            try perform(spec: MaterialTrack(course: id), g, ctx: ctx)
        }
    }

    struct Import: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "바깥 파일을 과목 폴더로 복사해 등록하고 회차에 연결", discussion: """
            --week를 주면 Lectures 규칙대로 이름 앞에 주차를 붙인다. 이미 과목 안에 있는 파일은 복사하지 않고 연결만 한다.

            예시:
              folio material import EC4207 ~/Downloads/06_Coloring.pdf --folder Lectures --week 6 --session 6주차-1
              folio material import EC4207 ~/Downloads/HW4.pdf --folder Assignments/HW04 --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("과목", valueName: "course"), completion: .custom(Complete.courses)) var course: String
        @Argument(help: ArgumentHelp("가져올 파일", valueName: "file"), completion: .file()) var files: [String]
        @Option(help: ArgumentHelp("넣을 폴더. 과목 폴더 기준. 예: Lectures", valueName: "folder"), completion: .directory) var folder: String
        @Option(help: ArgumentHelp("주차", valueName: "week")) var week: Int?
        @Option(help: ArgumentHelp("연결할 회차", valueName: "session"), completion: Complete.sessions) var session: String?

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let c = try r.course(course)
            let s = try session.map { try r.session(c.local($0), in: c).id }
            try perform(spec: MaterialImport(course: c.id, files: files.map(absolute), folder: folder, week: week, session: s), g, ctx: ctx)
        }
    }

    struct Move: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "mv", abstract: "자료 파일을 옮기거나 이름 바꾸기. ID와 연결은 그대로", discussion: """
            moves.jsonl에 남겨서 folio cleanup undo로 되돌릴 수 있다. 확인을 받는다.

            예시:
              folio material mv EC4207/Seating.pdf Exams/Midterm/자리.pdf --dry-run
            """)
        @OptionGroup var g: GlobalOptions
        @Argument(help: ArgumentHelp("<과목>/<자료>", valueName: "material"), completion: Complete.materials) var material: String
        @Argument(help: ArgumentHelp("새 경로. 과목 폴더 기준", valueName: "path"), completion: .file(extensions: ["json"])) var to: String

        func run() throws {
            let ctx = try CLI.context(g)
            let r = Resolver(ctx)
            let (c, name) = try r.split(material)
            let m = try r.material(name, in: c)
            let result = try perform(spec: MaterialMove(course: c.id, material: m.id, to: to), g, ctx: ctx)
            if !g.json, let batch = result.made { say("  되돌리기: folio cleanup undo \(batch.uuidString)".styled(.dim)) }
        }
    }
}
