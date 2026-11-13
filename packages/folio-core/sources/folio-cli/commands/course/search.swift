import ArgumentParser
import FolioDomain
import FolioIndex
import Foundation

extension SearchKind: ExpressibleByArgument {}

struct SearchCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "search", abstract: String(localized: .searchAbstract), discussion: String(localized: .searchDiscussion))
    @OptionGroup var g: GlobalOptions
    @Argument(help: ArgumentHelp(String(localized: .searchHelpWords), valueName: "word")) var words: [String]
    @Option(help: ArgumentHelp(String(localized: .searchHelpCourse), valueName: "course"), completion: .custom(Complete.courses)) var course: [String] = []
    @Option(help: ArgumentHelp(String(localized: .searchHelpSemester), valueName: "semester"), completion: .custom(Complete.semesters)) var semester: String?
    @Option(help: ArgumentHelp(String(localized: .searchHelpKind))) var kind: [SearchKind] = []
    @Option(help: ArgumentHelp(String(localized: .searchHelpLimit))) var limit = 60
    @Flag(help: ArgumentHelp(String(localized: .commonHelpLines))) var lines = false

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
            FileHandle.standardError.write(Data((done < total ? "\r" + String(localized: .searchIndexing(done, total)) : "\r\u{1B}[2K").utf8))
        }
        let hits = try index.search(words.joined(separator: " "), kinds: kind.isEmpty ? nil : Set(kind), courses: courses, limit: limit)
        if g.json { return try printJSON(hits.map(Hit.init)) }
        let code = Dictionary(r.courses.map { ($0.id, $0.code) }) { a, _ in a }
        let tag = Dictionary(r.courses.map { ($0.id, $0.tag) }) { a, _ in a }
        if lines {
            for h in hits { line(["\(code[h.item.courseId] ?? h.item.courseId.uuidString)/\(h.item.id)", h.item.kind.rawValue, h.item.title, h.snippet ?? ""]) }
            return
        }
        var t = Table(header: [String(localized: .searchHeaderCourse), String(localized: .searchHeaderKind), String(localized: .searchHeaderTitle), String(localized: .searchHeaderBody)], shrink: [3, 2])
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
