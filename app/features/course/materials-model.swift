import Algorithms
import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

/// Unclassified files come first with the cleanup's suggested place; nothing moves until approved.
@MainActor @Observable
final class MaterialsModel {
    let workspace: Workspace
    private let initial: LoadedCourse
    private(set) var suggestions: [PlannedMove]?
    var lastBatch: UUID?
    private var assignmentFolders: [String] = []
    var viewing: UUID?
    var preview: URL?
    var linking: UUID?
    var relinking: UUID?
    var disconnecting: FolioDomain.Material?
    var incoming: [URL] = []
    var renaming: FolioDomain.Material?
    var newName = ""
    var trashing: FolioDomain.Material?
    /// Folder paths opened in the tree; folders start closed so a course with many reports stays short.
    var opened: Set<String> = []

    init(workspace: Workspace, course: LoadedCourse) {
        self.workspace = workspace
        initial = course
    }

    /// Looked up each time, so a saved change shows without the page being handed the course again.
    var course: LoadedCourse { workspace.course(initial.id) ?? initial }
    var materials: [FolioDomain.Material] { course.file.materials }
    var viewed: FolioDomain.Material? { viewing.flatMap { id in materials.first { $0.id == id } } }

    func load() async {
        assignmentFolders = (try? course.store.assignmentFolders()) ?? []
        suggestions = await cleanupSuggestions()
    }

    var subtitle: String {
        let unclassified = materials.filter { $0.status == .unclassified }.count
        let missing = materials.filter { $0.status == .missing }.count
        return ([String(localized: .materialsFileCount(materials.count))] + (unclassified == 0 ? [] : [String(localized: .materialsUnclassifiedCount(unclassified))])
                + (missing == 0 ? [] : [String(localized: .materialsMissingCount(missing))])).joined(separator: " · ")
    }

    var unclassified: [FolioDomain.Material] { materials.filter { $0.status == .unclassified } }

    struct Section {
        var role: MaterialRole
        var count: Int
        var note: String
        var rows: [TreeRow]
    }

    func sections() -> [Section] {
        MaterialRole.allCases.compactMap { role in
            // A missing file that was never classified still needs a row to be re-pointed or dropped.
            let items = materials.filter { $0.role == role && $0.status == .classified || ($0.role ?? .other) == role && $0.status == .missing }
            guard !items.isEmpty else { return nil }
            let tree = PathTree(items) { $0.path }
            return Section(role: role, count: items.count, note: tree.path.isEmpty ? "\(items.count)" : "\(items.count) · \(tree.path)",
                           rows: treeRows(tree, depth: 0))
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

    /// Standard folders by hand, with each exam's prep folder; `Lectures` is offered with a session where it is needed.
    var places: [String] {
        let exams = course.file.exams.compactMap { MaterialIntake.folder(of: $0, among: course.file.exams) }
        return Array((MaterialIntake.places(assignmentFolders: assignmentFolders) + exams).uniqued())
    }

    /// Lectures stays in: an unclassified file keeps its name, and a lecture already named by week is common.
    var relocations: [String] { [CourseFolder.lectures.rawValue] + places }

    func moveTargets(_ m: FolioDomain.Material) -> [String] { relocations.filter { $0 != dir(m.path) } }

    func linkLine(_ m: FolioDomain.Material) -> String {
        let file = course.file
        let sessions = file.sessionLinks(of: m.id).map { s, link in file.name(of: s) + link.pageLabel }
        let units = file.units.filter { m.unitIds.contains($0.id) }.map(\.title)
        return (sessions + (units.isEmpty ? [] : [String(localized: .materialsLinkUnits(units.joined(separator: ", ")))])).joined(separator: " · ")
    }

    // MARK: Actions

    func track() {
        workspace.run(MaterialTrack(course: course.id))
        Task { await load() }
    }

    func undo() {
        guard let batch = lastBatch else { return }
        workspace.run(CleanupUndo(batch: batch, course: course.id))
        lastBatch = nil
        Task { await load() }
    }

    func untrack(_ m: FolioDomain.Material) { workspace.run(MaterialUntrack(course: course.id, material: m.id)) }
    func trash(_ m: FolioDomain.Material) { workspace.run(MaterialTrash(course: course.id, material: m.id)) }
    func ignore(_ ids: [UUID]) { workspace.run(MaterialStatusSet(course: course.id, materials: ids, status: .ignored)) }

    func startRenaming(_ m: FolioDomain.Material) {
        newName = ((m.path as NSString).lastPathComponent as NSString).deletingPathExtension
        renaming = m
    }

    func renameMessage(_ m: FolioDomain.Material) -> String {
        String(localized: .materialsRenameMessage((m.path as NSString).pathExtension))
    }

    func rename(_ m: FolioDomain.Material) {
        let ext = (m.path as NSString).pathExtension
        let base = newName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        let name = ext.isEmpty ? base : "\(base).\(ext)"
        guard !base.isEmpty, name != (m.path as NSString).lastPathComponent else { return }
        move(m, to: (dir(m.path) as NSString).appendingPathComponent(name))
    }

    func move(_ m: FolioDomain.Material, to place: String) {
        if let batch = workspace.run(MaterialMove(course: course.id, material: m.id, to: place))?.made { lastBatch = batch }
    }

    func move(_ m: FolioDomain.Material, into place: String) { move(m, to: "\(place)/\((m.path as NSString).lastPathComponent)") }

    func relink(to file: URL) {
        guard let id = relinking else { return }
        // Files picked on iPadOS are security-scoped; reading the hash needs access.
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        workspace.run(MaterialRelink(course: course.id, material: id, file: file.path(percentEncoded: false)))
    }

    /// A PDF opens here, a folder in Finder (by the view), anything else in Quick Look.
    func open(_ m: FolioDomain.Material) {
        if m.isPDF { viewing = m.id } else { Task { preview = try? await workspace.download(m, course: course.id) } }
    }

    func fileURL(_ path: String) -> URL { course.store.fileURL(path) }

    // MARK: Viewer

    /// The file, downloaded if iCloud holds only a placeholder, and the page it was last left at on any device.
    func pdf(_ m: FolioDomain.Material) async -> (url: URL, page: Int)? {
        guard let url = try? await workspace.download(m, course: course.id) else { return nil }
        let page = ((try? course.store.log.readAll()) ?? [])
            .events(MaterialViewEvent.self)
            .last { $0.event.materialId == m.id }?.event.page
        return (url, page ?? 0)
    }

    func recordPage(_ page: Int, of m: FolioDomain.Material) {
        let store = course.store
        // folio:not-an-action page views are activity logs, not data changes (docs/SPEC.md "액션")
        workspace.perform { try store.log.append(MaterialViewEvent(materialId: m.id, page: page), device: workspace.device, at: .now) }
    }

    // MARK: Links

    var sessions: [Session] { course.file.sessions.sorted { ($0.week, $0.index) < ($1.week, $1.index) } }
    /// Outline order: `order` counts among siblings only, so sorting by it alone interleaves chapters and their units.
    var units: [(unit: FolioDomain.Unit, depth: Int)] { UnitTree.outline(course.file.units) }

    func unitIds(of material: UUID) -> [UUID] { materials.first { $0.id == material }?.unitIds ?? [] }

    func sessionTitle(_ s: Session) -> String {
        s.topic.isEmpty ? course.file.name(of: s) : "\(course.file.name(of: s)) · \(s.topic)"
    }

    func link(_ material: UUID, session: UUID, linked: Bool) {
        workspace.run(MaterialLinkSession(course: course.id, material: material, session: session, linked: linked))
    }

    func setPages(_ material: UUID, session: UUID, _ first: Int?, _ last: Int?) {
        workspace.run(MaterialLinkSession(course: course.id, material: material, session: session, firstPage: first, lastPage: last))
    }

    func link(_ material: UUID, unit: UUID, linked: Bool) {
        workspace.run(MaterialLinkUnit(course: course.id, material: material, unit: unit, linked: linked))
    }

    // MARK: Unclassified inbox

    /// The course folder relative to the GIST root, with a trailing slash.
    var prefix: String {
        guard let gist = workspace.gist else { return "" }
        let root = gist.url.standardizedFileURL.path
        return String(course.store.url.standardizedFileURL.path.dropFirst(root.count + 1)) + "/"
    }

    /// The one-time cleanup's moves for files still left in this course, including the ones it was unsure about.
    /// Reading the whole GIST tree is slow, so this runs off the main actor.
    private func cleanupSuggestions() async -> [PlannedMove] {
        guard let gist = workspace.gist, workspace.course(initial.id) != nil else { return [] }
        let prefix = self.prefix, url = gist.url, file = course.file
        let labs = [String(prefix.dropLast()): file.labNumbers]
        let labWeeks = [String(prefix.dropLast()): file.labWeeks]
        let moves = await Task.detached {
            (try? GISTStore(url: url).readTree()).map { CleanupPlanner.plan($0, labs: labs, labWeeks: labWeeks).moves } ?? []
        }.value
        return moves.filter { $0.from.hasPrefix(prefix) }
    }

    struct Inbox {
        /// One per source folder, target folder and reason, so a folder of seven files is one decision.
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

    /// Moves files only after the user approved this exact move; the batch goes to `moves.jsonl` so it can be undone.
    func approve(_ moves: [PlannedMove]) {
        if let batch = workspace.run(CleanupApply(moves: moves, course: course.id))?.made { lastBatch = batch }
        Task { await load() }
    }

    func dir(_ path: String) -> String { (path as NSString).deletingLastPathComponent }

    func covers(_ move: PlannedMove, _ path: String) -> Bool {
        path == move.from || path.hasPrefix(move.from + "/")
    }
}

/// Where files brought in from the materials screen go: one row per kind, and for a kind with several folders
/// (assignments, exams) a second choice beneath it. A lecture needs its session, which names it by week and links it.
@MainActor @Observable
final class ImportPlaceModel {
    let workspace: Workspace
    let course: LoadedCourse
    let files: [URL]
    let places: [String]
    private(set) var place = CourseFolder.lectures.rawValue
    var session: UUID?

    init(workspace: Workspace, course: LoadedCourse, files: [URL], places: [String]) {
        self.workspace = workspace
        self.course = course
        self.files = files
        self.places = places
        session = sessions.last { $0.date <= workspace.now }?.id
    }

    var sessions: [Session] { course.file.sessions.filter { !$0.isCancelled }.sorted { ($0.week, $0.index) < ($1.week, $1.index) } }

    var title: String {
        String(localized: files.count == 1 ? .materialsImportOne(files[0].lastPathComponent) : .materialsImportMany(files.count))
    }

    struct Kind {
        var label: String
        var places: [String]
        var isLecture: Bool { places == [CourseFolder.lectures.rawValue] }
        /// Assignments and exams name which one even when there is one, so the choice reads plainly.
        var perItem: Bool { places[0].contains("/") && places != ["\(CourseFolder.exams.rawValue)/\(StandardLayout.pastExamsFolder)"] }
    }

    /// Places by kind label, in the order first met: `과제` → `Assignments/HW00`, `Assignments/HW01`, …
    var kinds: [Kind] {
        var result: [Kind] = []
        for p in [CourseFolder.lectures.rawValue] + places {
            let label = MaterialRole(path: p + "/_")?.label ?? p
            if let i = result.firstIndex(where: { $0.label == label }) { result[i].places.append(p) } else { result.append(Kind(label: label, places: [p])) }
        }
        return result
    }

    func shown(_ kind: Kind) -> String {
        kind.places.contains(place) ? place : kind.perItem ? "\((kind.places[0] as NSString).deletingLastPathComponent)/…" : kind.places[0]
    }

    var sessionOptions: [(UUID?, String)] {
        [(nil, String(localized: .materialsImportNoSession))] + sessions.map { ($0.id, course.file.name(of: $0) + ($0.topic.isEmpty ? "" : " · \($0.topic)")) }
    }

    /// The newest folder of a kind first: the latest assignment or exam is the likely one.
    func pick(_ places: [String]) {
        if !places.contains(place) { place = places.last ?? place }
    }

    func choose(_ place: String) { self.place = place }

    func confirm() {
        let picked = place == CourseFolder.lectures.rawValue ? sessions.first { $0.id == session } : nil
        workspace.importFiles(files, into: place, week: picked?.week, session: picked?.id, course: course.id)
    }
}
