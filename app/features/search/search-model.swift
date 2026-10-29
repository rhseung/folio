import FolioDomain
import FolioIndex
import Foundation
import Observation

@MainActor @Observable
final class SearchModel {
    enum Scope: Hashable {
        case all, semester(UUID), course(UUID)
    }

    struct KindGroup {
        let kind: SearchKind
        let hits: [SearchHit]
        /// Hits of this kind beyond the ones shown.
        let more: Int
    }

    static let perKind = 8

    let workspace: Workspace
    var query = ""
    var kind: SearchKind?
    var scope = Scope.all
    var index: SearchStore?
    var indexing: (done: Int, total: Int)?
    var hits: [SearchHit] = []
    var selected = 0
    @ObservationIgnored private var searching: Task<Void, Never>?
    /// Progress hops arrive as separate main-actor tasks and may land after the refresh returned; past that they're stale.
    @ObservationIgnored private var caughtUp = false

    init(workspace: Workspace) { self.workspace = workspace }

    var typed: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Kinds in the order their best hit ranks, each capped so one kind can't push the rest out of view;
    /// with one kind chosen, all of it.
    var groups: [KindGroup] {
        var order: [SearchKind] = []
        var byKind: [SearchKind: [SearchHit]] = [:]
        for hit in hits {
            if byKind[hit.item.kind] == nil { order.append(hit.item.kind) }
            byKind[hit.item.kind, default: []].append(hit)
        }
        let cap = kind == nil ? Self.perKind : .max
        return order.map { k in
            let all = byKind[k] ?? []
            return KindGroup(kind: k, hits: Array(all.prefix(cap)), more: max(all.count - cap, 0))
        }
    }

    /// The rows in the order the arrow keys walk them.
    var flat: [SearchHit] { groups.flatMap(\.hits) }

    var emptyMessage: String {
        String(localized: indexing != nil ? .searchEmptyIndexing : kind == nil && scope == .all ? .searchEmpty : .searchEmptyFiltered)
    }

    var scopeOptions: [PickOption<Scope>] {
        let semesters = workspace.semesters.filter { !workspace.courses(in: $0).isEmpty }
        return [PickOption(id: .all, title: String(localized: .searchScopeAll))]
            + semesters.map { PickOption(id: .semester($0.id), title: $0.title, section: String(localized: .searchScopeSemesters)) }
            + semesters.flatMap { s in
                workspace.courses(in: s).map { PickOption(id: .course($0.id), title: $0.title, detail: s.title, section: String(localized: .searchScopeCourses)) }
            }
    }

    func moveSelection(by delta: Int) {
        selected = min(max(selected + delta, 0), max(flat.count - 1, 0))
    }

    /// Where the chosen hit opens: its course's section, and the note or file itself.
    func target(_ hit: SearchHit) -> SearchTarget {
        let item = hit.item
        return SearchTarget(courseId: item.courseId, section: item.kind.section,
                            noteId: item.kind == .note ? item.id : nil, materialId: item.kind == .material ? item.id : nil)
    }

    /// What is already indexed answers at once; changed courses are read again behind it, then the results follow.
    func start() async {
        guard let gist = workspace.gist, let store = try? SearchStore.local(for: gist) else { return }
        index = store
        refresh()
        // Each course read shows up in the results as it lands, not only at the end.
        await Task.detached {
            _ = try? store.refresh(gist) { done, total in
                Task { @MainActor in
                    guard !self.caughtUp else { return }
                    self.indexing = done < total ? (done, total) : nil
                    if done > 0 { self.refresh(keepSelection: true) }
                }
            }
        }.value
        caughtUp = true
        indexing = nil
        refresh(keepSelection: true)
    }

    /// Searched once per change of the query or a filter, not per redraw: every keystroke and arrow press redraws.
    /// Off the main actor, since a word shorter than three letters scans every PDF's text.
    func refresh(keepSelection: Bool = false) {
        if !keepSelection { selected = 0 }
        guard let index else { return }
        let courses: Set<UUID>? = switch scope {
        case .all: nil
        case .course(let id): [id]
        case .semester(let id): Set(workspace.courses.filter { $0.file.course.semesterId == id }.map(\.id))
        }
        let (query, kinds, limit) = (query, kind.map { Set([$0]) }, kind == nil ? 60 : 200)
        searching?.cancel()
        searching = Task {
            let found = await Task.detached { (try? index.search(query, kinds: kinds, courses: courses, limit: limit)) ?? [] }.value
            if !Task.isCancelled { hits = found }
        }
    }

    /// The query's words, for picking them out in titles and snippets.
    var words: [String] {
        query.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// A note's snippet without its markdown: `**bold**`, `[[link]]` and `![](assets/…)` read as noise in one line.
    static func plain(_ snippet: String) -> String {
        snippet
            .replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            // The tail of a link the snippet cut into: `…0](assets/x.png)`.
            .replacingOccurrences(of: #"\]\([^)\s]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[\[([^\]|]*)(\|[^\]]*)?\]\]"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"(^|\s)#{1,6}\s"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\*\*|__|`"#, with: "", options: .regularExpression)
    }
}

extension SearchKind {
    var label: String {
        switch self {
        case .note: String(localized: .searchKindNote)
        case .material: String(localized: .searchKindMaterial)
        case .assignment: String(localized: .searchKindAssignment)
        // Recitations and labs are sessions too; the course pages call them all 회차.
        case .session: String(localized: .searchKindSession)
        case .unit: String(localized: .searchKindUnit)
        case .quiz: String(localized: .searchKindQuiz)
        }
    }

    var symbol: String {
        switch self {
        case .note: "doc.text"
        case .material: "doc"
        case .assignment: "checklist"
        case .session: "calendar"
        case .unit: "list.bullet"
        case .quiz: "rectangle.on.rectangle"
        }
    }

    var section: CourseSection {
        switch self {
        case .note: .notes
        case .material: .materials
        case .assignment: .assignments
        case .session: .sessions
        case .unit: .units
        case .quiz: .quizCards
        }
    }
}
