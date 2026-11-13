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
    // 진행 알림은 따로따로 main actor task로 와서 refresh가 끝난 뒤에 닿을 수 있다. 그 뒤에 온 것은 낡은 값이다.
    @ObservationIgnored private var caughtUp = false

    init(workspace: Workspace) { self.workspace = workspace }

    var typed: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

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

    var flat: [SearchHit] { groups.flatMap(\.hits) }

    var emptyMessage: String {
        String(localized: indexing != nil ? .searchEmptyIndexing : kind == nil && scope == .all ? .searchEmpty : .searchEmptyFiltered)
    }

    var scopeOptions: [PickOption<Scope>] {
        let semesters = workspace.semesters.filter { !workspace.courses(in: $0).isEmpty }
        return [PickOption(id: .all, title: String(localized: .searchScopeAll))]
            + semesters.map { PickOption(id: .semester($0.id), title: $0.title, section: String(localized: .searchScopeSemesters)) }
            + semesters.flatMap { s in
                workspace.courses(in: s).map {
                    PickOption(id: .course($0.id), title: $0.title, detail: s.title, section: String(localized: .searchScopeCourses))
                }
            }
    }

    func moveSelection(by delta: Int) {
        selected = min(max(selected + delta, 0), max(flat.count - 1, 0))
    }

    func start() async {
        guard let gist = workspace.gist, let store = try? SearchStore.local(for: gist) else { return }
        index = store
        refresh()

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

    // 모든 키 입력과 화살표가 다시 그리므로, 다시 그릴 때마다가 아니라 검색어나 필터가 바뀔 때 한 번 찾는다. 세
    // 글자보다 짧은 낱말은 모든 PDF의 글을 훑으므로 main actor 밖에서 찾는다.
    func refresh(keepSelection: Bool = false) {
        if !keepSelection { selected = 0 }
        guard let index else { return }
        let courses: Set<UUID>? =
            switch scope {
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

    var words: [String] {
        query.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func plain(_ snippet: String) -> String {
        snippet
            .replacingOccurrences(of: #"!?\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\]\([^)\s]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[\[([^\]|]*?)\\?(\|[^\]]*)?\]\]"#, with: "$1", options: .regularExpression)
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
        case .exam: String(localized: .searchKindExam)
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
        case .exam: "pencil.and.list.clipboard"
        case .session: "calendar"
        case .unit: "list.bullet"
        case .quiz: "rectangle.on.rectangle"
        }
    }
}
