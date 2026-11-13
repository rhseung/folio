import Algorithms
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

@MainActor @Observable
final class MaterialsModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    private(set) var suggestions: [PlannedMove]?
    let moves: MoveUndo
    private var assignmentFolders: [String] = []
    var viewing: UUID? { didSet { if viewing != oldValue { shownPage = nil } } }
    // 0부터 센 쪽이다.
    var requestedPage: Int?
    // 0부터 센 쪽이다.
    var shownPage: Int?
    var linking: UUID?
    var relinking: UUID?
    var disconnecting: FolioDomain.Material?
    var incoming: [URL] = []
    var newName = ""
    var pending: PendingAction?
    var opened: Set<String> = []
    var creatingFile = false
    var newFileFolder: String?

    init(workspace: Workspace, course: LoadedCourse, moves: MoveUndo = MoveUndo()) {
        self.workspace = workspace
        initial = course
        self.moves = moves
    }

    // 저장한 변경이 페이지에 과목을 다시 넘기지 않아도 보이도록 매번 찾는다.
    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var materials: [FolioDomain.Material] { course.file.materials }
    var viewed: FolioDomain.Material? { viewing.flatMap { id in materials.first { $0.id == id } } }
    var viewedLink: AppLink? { viewing.map { AppLink(.material, $0, anchor: shownPage.map { .page($0 + 1) }) } }

    func load() async {
        assignmentFolders = (try? course.store.assignmentFolders()) ?? []
        suggestions = await cleanupSuggestions()
    }

    var subtitle: String {
        let unclassified = materials.filter { $0.status == .unclassified }.count
        let missing = materials.filter { $0.status == .missing }.count
        return
            ([String(localized: .materialsFileCount(materials.count))]
            + (unclassified == 0 ? [] : [String(localized: .materialsUnclassifiedCount(unclassified))])
            + (missing == 0 ? [] : [String(localized: .materialsMissingCount(missing))])).joined(separator: " · ")
    }

    var unclassified: [FolioDomain.Material] { materials.filter { $0.status == .unclassified } }

    struct Section {
        var role: MaterialRole
        var count: Int
        var note: String
        var rows: [TreeRow]
        var pdfs: [UUID: FolioDomain.Material]
    }

    func sections() -> [Section] {
        MaterialRole.allCases.compactMap { role in
            let all = materials.filter {
                $0.role == role && $0.status == .classified || ($0.role ?? .other) == role && $0.status == .missing
            }
            let items = all.withoutBuiltPDFs()
            guard !items.isEmpty else { return nil }
            let tree = PathTree(items) { $0.path }
            return Section(
                role: role, count: items.count, note: tree.path.isEmpty ? "\(items.count)" : "\(items.count) · \(tree.path)",
                rows: treeRows(tree, depth: 0), pdfs: all.builtPDFsHidden())
        }
    }

    enum TreeRow {
        case folder(PathTree<FolioDomain.Material>, depth: Int)
        case file(FolioDomain.Material, name: String, depth: Int)

        var id: String {
            switch self {
            case .folder(let f, _): "folder:" + f.path
            case .file(let m, _, _): m.id.uuidString
            }
        }
    }

    func treeRows(_ tree: PathTree<FolioDomain.Material>, depth: Int) -> [TreeRow] {
        tree.folders.flatMap { f in [TreeRow.folder(f, depth: depth)] + (opened.contains(f.path) ? treeRows(f, depth: depth + 1) : []) }
            + tree.items.map { .file($0.item, name: $0.name, depth: depth) }
    }

    func toggle(_ folder: PathTree<FolioDomain.Material>) {
        if opened.contains(folder.path) { opened.remove(folder.path) } else { opened.insert(folder.path) }
    }

    var places: [String] {
        let exams = course.file.exams.compactMap { MaterialIntake.folder(of: $0) }
        return Array((MaterialIntake.places(assignmentFolders: assignmentFolders) + exams).uniqued())
    }

    var relocations: [String] { [CourseFolder.lectures.rawValue] + places }

    func moveTargets(_ m: FolioDomain.Material) -> [String] { relocations.filter { $0 != dir(m.path) } }

    func linkLine(_ m: FolioDomain.Material, pdf: FolioDomain.Material?) -> String {
        let own = linkLine(m)
        guard let pdf else { return own }
        let built = linkLine(pdf)
        return built.isEmpty
            ? own : ([own].filter { !$0.isEmpty } + [String(localized: .materialsPairedPdfLinks(built))]).joined(separator: " · ")
    }

    func linkLine(_ m: FolioDomain.Material) -> String {
        let file = course.file
        let sessions = file.sessionLinks(of: m.id).map { s, link in file.day(of: s, calendar: workspace.calendar) + link.pageLabel }
        let units = file.units(of: m)
        let own = { (routes: [MaterialRoute]) in routes.contains(.direct) || routes.contains(.pages) }
        let direct = units.filter { own($0.routes) }.map(\.unit.title)
        let via = units.filter { !own($0.routes) }.map(\.unit.title)
        return
            (sessions
            + (direct.isEmpty ? [] : [String(localized: .materialsLinkUnits(direct.joined(separator: ", ")))])
            + (via.isEmpty ? [] : [String(localized: .materialsLinkUnitsViaSessions(via.joined(separator: ", ")))])).joined(
                separator: " · ")
    }

    // MARK: Actions

    func track() {
        workspace.run(MaterialTrack(course: course.id))
        Task { await load() }
    }

    func undo() {
        pending = moves.undo(workspace, course: course.id) { [weak self] in Task { await self?.load() } }
    }

    #if DEBUG
    func trackFixtureFiles() {
        if materials.isEmpty { workspace.run(MaterialTrack(course: course.id)) }
    }
    #endif

    func acceptsNewFile(_ folder: PathTree<FolioDomain.Material>) -> Bool {
        let file = course.file
        return NewMaterialFile.accepts(
            folder: folder.path,
            places: NewMaterialFile.places(assignments: file.assignments, exams: file.exams, assignmentFolders: assignmentFolders))
    }

    func startNewFile(in folder: String?) {
        newFileFolder = folder
        creatingFile = true
    }

    func created(_ id: UUID) {
        guard let m = materials.first(where: { $0.id == id }) else { return }
        var folder = dir(m.path)
        while !folder.isEmpty {
            opened.insert(folder)
            folder = dir(folder)
        }
        viewing = id
    }

    func untrack(_ m: FolioDomain.Material) { workspace.run(MaterialUntrack(course: course.id, material: m.id)) }
    func ignore(_ ids: [UUID]) { pending = workspace.ask(MaterialStatusSet(course: course.id, status: .ignored, materials: ids)) }

    // 폴더 이름은 전체가 이름이다. `robot.v2`라는 프로젝트에는 지킬 확장자가 없다.
    private func kept(_ m: FolioDomain.Material) -> String { m.isFolder ? "" : (m.path as NSString).pathExtension }

    func startRenaming(_ m: FolioDomain.Material) {
        let name = (m.path as NSString).lastPathComponent
        newName = m.isFolder ? name : (name as NSString).deletingPathExtension
    }

    func renameMessage(_ m: FolioDomain.Material) -> String {
        let ext = kept(m)
        return String(localized: ext.isEmpty ? .materialsRenameMessagePlain : .materialsRenameMessage(ext))
    }

    func renamed(_ m: FolioDomain.Material) -> String? {
        let ext = kept(m)
        let base = newName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        let name = ext.isEmpty ? base : "\(base).\(ext)"
        return base.isEmpty || name == (m.path as NSString).lastPathComponent ? nil : name
    }

    func rename(_ m: FolioDomain.Material) {
        guard let name = renamed(m) else { return }
        moves.keep(
            workspace.run(MaterialMove(course: course.id, material: m.id, to: (dir(m.path) as NSString).appendingPathComponent(name))))
    }

    func move(_ m: FolioDomain.Material, into place: String) {
        let action = MaterialMove(course: course.id, material: m.id, to: "\(place)/\((m.path as NSString).lastPathComponent)")
        pending = workspace.ask(action) { [weak self] ctx in self?.moves.keep(ctx) }
    }

    func relink(to file: URL) {
        guard let id = relinking else { return }
        // iPadOS에서 고른 파일은 security-scoped라서 해시를 읽으려면 접근 권한이 필요하다.
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        workspace.run(MaterialRelink(course: course.id, material: id, file: file.path(percentEncoded: false)))
    }

    func follow(_ link: AppLink) -> FolioDomain.Material? {
        guard link.kind == .material else {
            if link.kind == .course { viewing = nil }
            return nil
        }
        guard let m = materials.first(where: { $0.id == link.id }) else { return nil }
        // 뷰어가 알린 쪽은 창의 링크로 돌아온다. 그 쪽으로 다시 가면 스크롤한 자리에서 페이지 맨 위로 뛴다.
        if case .page(let n) = link.anchor, viewing != m.id || shownPage != n - 1 { requestedPage = n - 1 }
        return m
    }

    func open(_ m: FolioDomain.Material) {
        if !m.isFolder { viewing = m.id }
    }

    func fileURL(_ path: String) -> URL { course.store.fileURL(path) }

    // MARK: Links

    func sessions(linking material: UUID) -> [Session] {
        course.file.linkableSessions { $0.materials.contains { $0.materialId == material } }
    }

    // `order`는 형제 사이에서만 세므로, 그것만으로 정렬하면 장과 그 단원이 섞인다.
    var units: [(unit: FolioDomain.Unit, depth: Int)] { UnitTree.outline(course.file.units) }

    func unitIds(of material: UUID) -> [UUID] { materials.first { $0.id == material }?.unitIds ?? [] }

    func unitsViaSessions(of material: UUID) -> Set<UUID> {
        guard let m = materials.first(where: { $0.id == material }) else { return [] }
        return Set(course.file.units(of: m).filter { !$0.routes.contains(.direct) && !$0.routes.contains(.pages) }.map(\.unit.id))
    }

    func splitPages(of material: UUID, unit: UUID) -> String? {
        course.file.pages(of: unit, in: material).map { String(localized: .materialsLinksUnitPages($0.lowerBound, $0.upperBound)) }
    }

    var exams: [Exam] { course.file.exams.sorted { ($0.start ?? .distantFuture, $0.title) < ($1.start ?? .distantFuture, $1.title) } }

    func routes(of material: UUID, to exam: Exam) -> [MaterialRoute] {
        materials.first { $0.id == material }.map { course.file.routes(of: $0, to: .exam(exam.id)) } ?? []
    }

    func sessionTitle(_ s: Session) -> String { course.file.title(of: s, calendar: workspace.calendar) }

    func link(_ material: UUID, session: UUID, linked: Bool) {
        let s = course.file.sessions.first { $0.id == session }
        let start =
            linked && isLecture(material)
            ? s.map { course.file.suggestedLink(of: material, for: $0, pageCount: pageCounts[material]) } : nil
        workspace.run(
            MaterialLinkSession(
                course: course.id, material: material, session: session, linked: linked,
                firstPage: start?.firstPage, lastPage: start?.lastPage))
    }

    func taught(_ material: UUID, besides session: UUID) -> [PageRangeField.Taught] {
        PageRangeField.Taught.list(course.file, material: material, besides: session, calendar: workspace.calendar)
    }

    func sections(_ material: UUID) -> [PageRangeField.Section] {
        PageRangeField.Section.list(course.file, material: material, pageCount: pageCounts[material])
    }

    func seen(_ material: UUID, in session: Session) -> ClosedRange<Int>? {
        course.file.viewedPages(of: session).first { $0.materialId == material }?.pages
    }

    func setPages(_ material: UUID, session: UUID, _ range: PageRange) {
        workspace.run(
            MaterialLinkSession(course: course.id, material: material, session: session, firstPage: range.first, lastPage: range.last))
    }

    // 읽을 때마다 iCloud에서 파일을 내려받을 수 있으므로, 목록 전체가 아니라 링크를 열 때 읽는다.
    private(set) var pageCounts: [UUID: Int] = [:]

    func loadPageCount(_ material: UUID) async {
        guard pageCounts[material] == nil, let m = materials.first(where: { $0.id == material }),
            let n = await workspace.pageCount(of: m, course: course.id)
        else { return }
        pageCounts[material] = n
    }

    // MARK: Lecture progress

    func linksTitle(_ material: UUID) -> String {
        String(localized: .materialsLinksTitle(((materials.first { $0.id == material }?.path ?? "") as NSString).lastPathComponent))
    }

    func isLecture(_ material: UUID) -> Bool { materials.first { $0.id == material }?.role == .lecture }

    func link(_ material: UUID, unit: UUID, linked: Bool) {
        workspace.run(MaterialLinkUnit(course: course.id, material: material, unit: unit, linked: linked))
    }

    func link(_ material: UUID, exam: UUID, linked: Bool) {
        workspace.run(MaterialLinkExam(course: course.id, material: material, exam: exam, linked: linked))
    }

    // MARK: Unclassified inbox

    var prefix: String {
        guard let gist = workspace.gist else { return "" }
        let root = gist.url.standardizedFileURL.path
        return String(course.store.url.standardizedFileURL.path.dropFirst(root.count + 1)) + "/"
    }

    // GIST 폴더 전체를 읽는 일은 느려서 main actor 밖에서 돌린다.
    private func cleanupSuggestions() async -> [PlannedMove] {
        guard let gist = workspace.gist, workspace.course(initial.id) != nil else { return [] }
        let prefix = self.prefix, url = gist.url, file = course.file
        let labs = [String(prefix.dropLast()): file.labNumbers]
        let labWeeks = [String(prefix.dropLast()): file.labWeeks]
        let moves = await Task.detached {
            (try? GISTStore(url: url).cleanupPlan(labs: labs, labWeeks: labWeeks))?.moves ?? []
        }.value
        return moves.filter { $0.from.hasPrefix(prefix) }
    }

    struct Inbox {
        var groups: [[PlannedMove]]
        var orphans: [FolioDomain.Material]
    }

    func inbox(_ unclassified: [FolioDomain.Material]) -> Inbox {
        let prefix = self.prefix
        let moves = (suggestions ?? []).filter { move in unclassified.contains { covers(move, prefix + $0.path) } }
        let groups = Dictionary(grouping: moves) { [dir($0.from), dir($0.to), $0.review?.rawValue ?? ""] }
            .values.map { $0.sorted { $0.from < $1.from } }.sorted { $0[0].from < $1[0].from }
        return Inbox(groups: groups, orphans: unclassified.filter { m in !moves.contains { covers($0, prefix + m.path) } })
    }

    func files(in group: [PlannedMove], among unclassified: [FolioDomain.Material]) -> [UUID] {
        unclassified.filter { m in group.contains { covers($0, prefix + m.path) } }.map(\.id)
    }

    func source(_ group: [PlannedMove]) -> String {
        String((group.count == 1 ? group[0].from : dir(group[0].from)).dropFirst(prefix.count))
            + (group.count > 1 ? " · " + String(localized: .materialsFileCount(group.count)) : "")
    }

    func target(_ group: [PlannedMove]) -> String {
        String((group.count == 1 ? group[0].to : dir(group[0].to) + "/").dropFirst(prefix.count))
    }

    func relocate(_ sources: [String], to place: String) {
        let prefix = self.prefix
        approve(sources.map { PlannedMove(from: $0, to: "\(prefix)\(place)/\(($0 as NSString).lastPathComponent)") })
    }

    func approve(_ moves: [PlannedMove]) {
        self.moves.keep(workspace.run(CleanupApply(moves: moves, course: course.id)))
        Task { await load() }
    }

    func dir(_ path: String) -> String { (path as NSString).deletingLastPathComponent }

    func covers(_ move: PlannedMove, _ path: String) -> Bool {
        path == move.from || path.hasPrefix(move.from + "/")
    }
}
