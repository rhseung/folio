import ArgumentParser
import FolioDomain
import FolioIndex
import Foundation

extension SearchKind: ExpressibleByArgument {}

struct SearchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "search", abstract: "모든 과목의 노트, 자료와 PDF 본문, 과제, 회차, 단원, 퀴즈 카드 검색", discussion: """
        모든 낱말이 제목이나 본문에 있는 항목을 찾는다. 제목에 맞은 항목이 먼저 나온다.
        색인은 이 기기의 캐시이고, 검색할 때마다 바뀐 과목만 다시 읽는다.

        예시:
          folio search 매칭
          folio search "Hall theorem" --kind material
          folio search 트리 --course EC4207 --lines
          folio search 중간 --semester 2026-3 --json
          folio search 매칭 --kind quiz
        """)
    @OptionGroup var g: GlobalOptions
    @Argument(help: ArgumentHelp("찾을 낱말", valueName: "word")) var words: [String]
    @Option(help: ArgumentHelp("이 과목에서만", valueName: "course"), completion: .custom(Complete.courses)) var course: [String] = []
    @Option(help: ArgumentHelp("이 학기에서만. 예: 2026-3", valueName: "semester"), completion: .custom(Complete.semesters)) var semester: String?
    @Option(help: "이 종류만. note, material, assignment, session, unit, quiz") var kind: [SearchKind] = []
    @Option(help: "최대 개수") var limit = 60
    @Flag(help: "머리글 없이 한 줄에 하나, 탭으로 나눠서") var lines = false

    func run() throws {
        let r = Resolver(try CLI.context(g))
        var courses: Set<UUID>? = course.isEmpty ? nil : Set(try course.map { try r.course($0).id })
        if let semester {
            let id = try r.semester(semester).id
            let inSemester = Set(r.courses.filter { $0.course.semesterId == id }.map(\.id))
            courses = courses.map { $0.intersection(inSemester) } ?? inSemester
        }
        // Tests point at throwaway folders; an in-memory index keeps them out of the user's caches.
        let index = try CLI.overrides == nil ? SearchStore.local(for: r.ctx.gist) : SearchStore(url: nil)
        // A first build reads every PDF and can take a minute; at a terminal, say how far it is on stderr.
        let showProgress = isatty(STDERR_FILENO) == 1 && !g.json
        try index.refresh(r.ctx.gist) { done, total in
            guard showProgress else { return }
            FileHandle.standardError.write(Data((done < total ? "\r색인 중 \(done)/\(total) 과목" : "\r\u{1B}[2K").utf8))
        }
        let hits = try index.search(words.joined(separator: " "), kinds: kind.isEmpty ? nil : Set(kind), courses: courses, limit: limit)
        if g.json { return try printJSON(hits.map(Hit.init)) }
        let code = Dictionary(r.courses.map { ($0.id, $0.code) }) { a, _ in a }
        let tag = Dictionary(r.courses.map { ($0.id, $0.tag) }) { a, _ in a }
        if lines {
            for h in hits { line(["\(code[h.item.courseId] ?? h.item.courseId.uuidString)/\(h.item.id)", h.item.kind.rawValue, h.item.title, h.snippet ?? ""]) }
            return
        }
        var t = Table(header: ["과목", "종류", "제목", "본문"], shrink: [3, 2])
        for h in hits {
            t.rows.append([tag[h.item.courseId] ?? "", h.item.kind.rawValue.styled(.cyan), h.item.title.highlighting(words),
                           (h.snippet ?? "").highlighting(words)])
        }
        t.print()
        footer(hits.count)
    }

    struct Hit: Encodable {
        var kind: String, course: UUID, id: UUID, title: String, snippet: String?
        init(_ h: SearchHit) { (kind, course, id, title, snippet) = (h.item.kind.rawValue, h.item.courseId, h.item.id, h.item.title, h.snippet) }
    }
}
