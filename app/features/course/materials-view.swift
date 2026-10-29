import Algorithms
import FolioActions
import FolioDomain
import FolioStorage
import QuickLook
import SwiftUI

/// Files by role. Unclassified files come first with the cleanup's suggested place; nothing moves until approved.
/// PDFs open in the app; other files in Quick Look or their default app; code-project folders in Finder.
struct MaterialsView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.accent) private var accent
    @Environment(\.searchTarget) private var target
    let course: LoadedCourse
    @State private var suggestions: [PlannedMove]?
    @State private var lastBatch: UUID?
    @State private var assignmentFolders: [String] = []
    @State private var viewing: UUID?
    @State private var preview: URL?
    @State private var linking: UUID?
    @State private var relinking: UUID?
    @State private var disconnecting: FolioDomain.Material?
    @State private var incoming: [URL] = []
    @State private var picking = false
    @State private var renaming: FolioDomain.Material?
    @State private var newName = ""
    @State private var trashing: FolioDomain.Material?
    /// Folder paths opened in the tree; folders start closed so a course with many reports stays short.
    @State private var opened: Set<String> = []

    var body: some View {
        Group {
            if let id = viewing, let m = course.file.materials.first(where: { $0.id == id }) {
                MaterialViewer(course: course, material: m).id(m.id)  // another file starts over: page, zoom and search belong to the old one
            } else {
                list
            }
        }
        .task { await load() }
        .quickLookPreview($preview)
        .fileImporter(isPresented: Binding(get: { relinking != nil }, set: { if !$0 { relinking = nil } }), allowedContentTypes: [.item]) { result in
            if case .success(let url) = result, let id = relinking { workspace.relink(id, to: url, course: course.id) }
            relinking = nil
        }
        .confirmationDialog("이 파일의 추적을 끊을까요?", isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }),
                            presenting: disconnecting) { m in
            Button("연결 끊기", role: .destructive) { workspace.run(MaterialUntrack(course: course.id, material: m.id)) }
        } message: { m in
            Text("\(m.path) 항목을 자료 목록에서 지웁니다. 회차, 단원, 노트에 걸린 참조는 그대로 남습니다.")
        }
        .sheet(isPresented: Binding(get: { !incoming.isEmpty }, set: { if !$0 { incoming = [] } })) {
            ImportPlaceSheet(course: course, files: incoming, places: places)
        }
        .confirmationDialog("휴지통으로 옮길까요?", isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } }),
                            presenting: trashing) { m in
            Button("휴지통으로 옮기기", role: .destructive) { workspace.run(MaterialTrash(course: course.id, material: m.id)) }
        } message: { m in
            Text("\(m.path) 파일을 휴지통으로 옮기고 자료 목록에서 지웁니다. 휴지통에서 되살릴 수 있습니다.")
        }
        .alert("이름 바꾸기", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), presenting: renaming) { m in
            TextField("이름", text: $newName)
            Button("바꾸기") { rename(m) }
            Button("취소", role: .cancel) {}
        } message: { m in
            Text("확장자 .\((m.path as NSString).pathExtension)는 그대로 둡니다. 바꾼 이름은 되돌릴 수 있게 기록합니다.")
        }
        .onChange(of: target.wrappedValue, initial: true) { _, new in
            guard let new, new.courseId == course.id, let id = new.materialId else { return }
            target.wrappedValue = nil
            if let m = course.file.materials.first(where: { $0.id == id }) { open(m) }
        }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.openPDF, initial: true) { _, new in
            // Fixtures ship without tracked files; register them so there is a PDF to show.
            if new, course.file.materials.isEmpty { workspace.run(MaterialTrack(course: course.id)) }
            viewing = new ? workspace.course(course.id)?.file.materials.first { $0.isPDF && $0.status == .classified }?.id : nil
        }
        #endif
    }

    var list: some View {
        let materials = course.file.materials
        let unclassified = materials.filter { $0.status == .unclassified }
        return Page {
            let missing = materials.filter { $0.status == .missing }.count
            PageHeader(title: "자료", subtitle: (["파일 \(materials.count)개"] + (unclassified.isEmpty ? [] : ["미분류 \(unclassified.count)개"])
                                                + (missing == 0 ? [] : ["파일 없음 \(missing)개"])).joined(separator: " · "))

            if materials.isEmpty {
                EmptyLine("아직 추적한 파일이 없습니다. 파일을 추가하거나 이 화면에 끌어다 놓으세요. 과목 폴더에 이미 있는 파일은 파일 추적 갱신으로 등록합니다.")
            }
            HStack {
                Button("파일 추가") { picking = true }
                    .help("파일을 골라 과목 폴더로 복사합니다. 이 화면에 끌어다 놓아도 됩니다.")
                Button("파일 추적 갱신") { workspace.run(MaterialTrack(course: course.id)); Task { await load() } }
                    .help("과목 폴더를 다시 읽어 새 파일을 등록하고 옮겨진 파일을 다시 연결합니다. 파일은 옮기지 않습니다.")
                if let batch = lastBatch {
                    Button("방금 옮긴 것 되돌리기") { workspace.undoMoves(batch, course: course.id); lastBatch = nil; Task { await load() } }
                }
            }
            // On the header row, not the page: two file importers on one view leave only the last one working.
            .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { incoming = urls }
            }

            if !unclassified.isEmpty { inbox(unclassified) }

            ForEach(MaterialRole.allCases, id: \.self) { role in
                // A missing file that was never classified still needs a row to be re-pointed or dropped.
                let items = materials.filter { $0.role == role && $0.status == .classified || ($0.role ?? .other) == role && $0.status == .missing }
                if !items.isEmpty {
                    let tree = PathTree(items) { $0.path }
                    let rows = treeRows(tree, depth: 0)
                    Block(role.label, note: tree.path.isEmpty ? "\(items.count)" : "\(items.count) · \(tree.path)") {
                        Card {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                CardRow(last: i == rows.count - 1) {
                                    switch row {
                                    case .folder(let folder, let depth): folderRow(folder, depth: depth)
                                    case .file(let m, let name, let depth):
                                        // One stack, so the indent moves the row once rather than padding each of its parts.
                                        HStack(spacing: Theme.Space.m) { fileRow(m, name: name) }.padding(.leading, CGFloat(depth) * Self.indent)
                                    }
                                }
                                .contentShape(.rect)
                                .contextMenu {
                                    switch row {
                                    case .folder(let folder, _): folderMenu(folder)
                                    case .file(let m, _, _): fileContextMenu(m)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .fileDrop { incoming = $0 }
    }

    /// Standard folders by hand, with each exam's prep folder; `Lectures` is offered with a session where it is needed.
    var places: [String] {
        let exams = course.file.exams.compactMap { MaterialIntake.folder(of: $0, among: course.file.exams) }
        return Array((MaterialIntake.places(assignmentFolders: assignmentFolders) + exams).uniqued())
    }

    func rename(_ m: FolioDomain.Material) {
        let ext = (m.path as NSString).pathExtension
        let base = newName.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        let name = ext.isEmpty ? base : "\(base).\(ext)"
        guard !base.isEmpty, name != (m.path as NSString).lastPathComponent else { return }
        move(m, to: (dir(m.path) as NSString).appendingPathComponent(name))
    }

    func move(_ m: FolioDomain.Material, to path: String) {
        if let batch = workspace.run(MaterialMove(course: course.id, material: m.id, to: path))?.made { lastBatch = batch }
    }

    func load() async {
        assignmentFolders = (try? course.store.assignmentFolders()) ?? []
        suggestions = await workspace.cleanupSuggestions(for: course.id)
    }

    // MARK: Opening

    func open(_ m: FolioDomain.Material) {
        #if os(macOS)
        if m.isFolder {
            NSWorkspace.shared.open(course.store.fileURL(m.path))
            return
        }
        #endif
        if m.isPDF { viewing = m.id } else { Task { preview = try? await workspace.download(m, course: course.id) } }
    }

    /// `2주차-1 p.3–10 · 5주차-2 · 단원: Matchings`.
    func linkLine(_ m: FolioDomain.Material) -> String {
        let file = course.file
        let sessions = file.sessionLinks(of: m.id).map { s, link in course.file.name(of: s) + link.pageLabel }
        let units = file.units.filter { m.unitIds.contains($0.id) }.map(\.title)
        return (sessions + (units.isEmpty ? [] : ["단원: " + units.joined(separator: ", ")])).joined(separator: " · ")
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

    /// The chevron and its gap, so a folder's files line up under its folder icon.
    static let indent: CGFloat = 14 + Theme.Space.m

    /// Folders first, then files, descending only into opened folders.
    func treeRows(_ tree: PathTree<FolioDomain.Material>, depth: Int) -> [TreeRow] {
        tree.folders.flatMap { f in [TreeRow.folder(f, depth: depth)] + (opened.contains(f.path) ? treeRows(f, depth: depth + 1) : []) }
            + tree.items.map { .file($0.item, name: $0.name, depth: depth) }
    }

    func folderRow(_ folder: PathTree<FolioDomain.Material>, depth: Int) -> some View {
        let open = opened.contains(folder.path)
        return HStack(spacing: Theme.Space.m) {
            Image(systemName: "chevron.right").font(Theme.Glyph.regular)
                .rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(Theme.Palette.textTertiary).frame(width: 14)
            Image(systemName: open ? "folder.fill" : "folder").foregroundStyle(accent.color)
            Text(folder.name).font(Theme.Typeface.bodyStrong).lineLimit(1)
            Text("\(folder.count)").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).monospacedDigit()
            Spacer()
        }
        .padding(.leading, CGFloat(depth) * Self.indent)
        .opens { toggle(folder) }
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(open ? "펼침" : "접힘")
    }

    func toggle(_ folder: PathTree<FolioDomain.Material>) {
        withAnimation(.snappy(duration: 0.2)) { if opened.contains(folder.path) { opened.remove(folder.path) } else { opened.insert(folder.path) } }
    }

    @ViewBuilder func folderMenu(_ folder: PathTree<FolioDomain.Material>) -> some View {
        Button(opened.contains(folder.path) ? "접기" : "펼치기") { toggle(folder) }
        #if os(macOS)
        Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([course.store.fileURL(folder.path)]) }
        #endif
    }

    /// The row's buttons, then the ⋯ menu's items.
    @ViewBuilder func fileContextMenu(_ m: FolioDomain.Material) -> some View {
        if m.status == .missing {
            Button("다른 파일 지정…") { relinking = m.id }
            Divider()
            Button("연결 끊기…", role: .destructive) { disconnecting = m }
        } else {
            Button(m.isFolder ? "Finder에서 열기" : "열기") { open(m) }
            Button("연결…") { linking = m.id }
            if !m.isFolder {
                Divider()
                fileMenuItems(m)
            }
        }
    }

    @ViewBuilder func fileMenuItems(_ m: FolioDomain.Material) -> some View {
        #if os(macOS)
        Button("기본 앱으로 열기") { NSWorkspace.shared.open(course.store.fileURL(m.path)) }
        Button("Finder에서 보기") { NSWorkspace.shared.activateFileViewerSelecting([course.store.fileURL(m.path)]) }
        Divider()
        #endif
        Button("이름 바꾸기…") { newName = ((m.path as NSString).lastPathComponent as NSString).deletingPathExtension; renaming = m }
        Menu("다른 위치로 옮기기") {
            ForEach(([CourseFolder.lectures.rawValue] + places).filter { $0 != dir(m.path) }, id: \.self) { place in
                Button(place) { move(m, to: "\(place)/\((m.path as NSString).lastPathComponent)") }
            }
        }
        Divider()
        Button("휴지통으로 옮기기…", role: .destructive) { trashing = m }
    }

    @ViewBuilder func fileRow(_ m: FolioDomain.Material, name: String) -> some View {
        let missing = m.status == .missing
        Image(systemName: m.isFolder ? "folder" : missing ? "exclamationmark.triangle" : m.isPDF ? "doc.richtext" : "doc")
            .foregroundStyle(missing ? Theme.Palette.danger : Theme.Palette.textSecondary)
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(name).lineLimit(1).help(m.path)
            let links = linkLine(m)
            if !links.isEmpty { Text(links).font(Theme.Typeface.caption).foregroundStyle(accent.ink).lineLimit(1) }
        }
        .fileDrag(course.store.fileURL(m.path))
        Spacer()
        if missing {
            Chip("파일 없음", tone: .danger)
            Button("다른 파일 지정") { relinking = m.id }.buttonStyle(.ghost)
            Button("연결 끊기") { disconnecting = m }.buttonStyle(.ghost).tint(Theme.Palette.danger)
        } else {
            Button("연결") { linking = m.id }
                .buttonStyle(.ghost)
                .popover(isPresented: Binding(get: { linking == m.id }, set: { if !$0 { linking = nil } })) {
                    MaterialLinksEditor(course: course, materialId: m.id)
                }
            Button(m.isFolder ? "Finder" : "열기") { open(m) }.buttonStyle(.ghost)
            if !m.isFolder {
                Menu { fileMenuItems(m) } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless).pointingHand()
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
    }

    // MARK: Unclassified inbox

    @ViewBuilder func inbox(_ unclassified: [FolioDomain.Material]) -> some View {
        let prefix = workspace.coursePrefix(course.id) ?? ""
        let moves = (suggestions ?? []).filter { move in unclassified.contains { covers(move, prefix + $0.path) } }
        // One row per source folder, target folder and reason, so a folder of seven files is one decision.
        let groups = Dictionary(grouping: moves) { [dir($0.from), dir($0.to), $0.review?.rawValue ?? ""] }
            .values.map { $0.sorted { $0.from < $1.from } }.sorted { $0[0].from < $1[0].from }
        let orphans = unclassified.filter { m in !moves.contains { covers($0, prefix + m.path) } }
        NoticeCard(title: "자료 \(unclassified.count)건이 분류를 기다립니다", detail: "승인한 것만 옮기고, 옮긴 기록은 되돌릴 수 있게 남깁니다", systemImage: "tray.fill", trailing: { EmptyView() }) {
                if suggestions == nil {
                    CardRow(last: true) { ProgressView().controlSize(.small); Text("추천 위치를 계산하는 중").foregroundStyle(Theme.Palette.textTertiary) }
                }
                ForEach(Array(groups.enumerated()), id: \.element) { i, group in
                    let files = unclassified.filter { m in group.contains { covers($0, prefix + m.path) } }
                    let source = group.count == 1 ? group[0].from : dir(group[0].from)
                    CardRow(last: i == groups.count - 1 && orphans.isEmpty) {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text(String(source.dropFirst(prefix.count)) + (group.count > 1 ? " · 파일 \(group.count)개" : ""))
                                .font(Theme.Typeface.bodyStrong).lineLimit(1)
                            HStack(spacing: Theme.Space.tight) {
                                Image(systemName: "arrow.turn.down.right").foregroundStyle(Theme.Palette.textTertiary)
                                Text(String((group.count == 1 ? group[0].to : dir(group[0].to) + "/").dropFirst(prefix.count)))
                                    .font(Theme.Typeface.mono).lineLimit(1)
                                if let reason = group[0].review { Chip(reason.label, tone: .warning) }
                            }
                        }
                        Spacer()
                        Button("승인") { approve(group) }.buttonStyle(.pointing(.borderedProminent))
                        relocateMenu(group.map(\.from))
                        Button("무시") { workspace.run(MaterialStatusSet(course: course.id, materials: files.map(\.id), status: .ignored)) }.buttonStyle(.ghost)
                    }
                    .contentShape(.rect)
                    .contextMenu {
                        Button("승인") { approve(group) }
                        relocateMenu(group.map(\.from))
                        Divider()
                        Button("무시") { workspace.run(MaterialStatusSet(course: course.id, materials: files.map(\.id), status: .ignored)) }
                    }
                }
                ForEach(Array(orphans.enumerated()), id: \.element.id) { i, m in
                    CardRow(last: i == orphans.count - 1) {
                        Text(m.path).font(Theme.Typeface.bodyStrong).lineLimit(1)
                        Spacer()
                        relocateMenu([prefix + m.path])
                        Button("무시") { workspace.run(MaterialStatusSet(course: course.id, materials: [m.id], status: .ignored)) }.buttonStyle(.ghost)
                    }
                    .contentShape(.rect)
                    .contextMenu {
                        relocateMenu([prefix + m.path])
                        Divider()
                        Button("무시") { workspace.run(MaterialStatusSet(course: course.id, materials: [m.id], status: .ignored)) }
                    }
                }
        }
    }

    func dir(_ path: String) -> String { (path as NSString).deletingLastPathComponent }

    /// Other standard places for `sources`, each keeping its name.
    func relocateMenu(_ sources: [String]) -> some View {
        let prefix = workspace.coursePrefix(course.id) ?? ""
        // Lectures stays here: an unclassified file keeps its name, and a lecture already named by week is common.
        return Menu("다른 위치") {
            ForEach([CourseFolder.lectures.rawValue] + places, id: \.self) { place in
                Button(place) {
                    approve(sources.map { PlannedMove(from: $0, to: "\(prefix)\(place)/\(($0 as NSString).lastPathComponent)") })
                }
            }
        }
        .fixedSize()
    }

    func approve(_ moves: [PlannedMove]) {
        if let batch = workspace.approve(moves, course: course.id) { lastBatch = batch }
        Task { await load() }
    }

    func covers(_ move: PlannedMove, _ path: String) -> Bool {
        path == move.from || path.hasPrefix(move.from + "/")
    }
}

/// Which sessions (with a page range) and units a material belongs to.
struct MaterialLinksEditor: View {
    @Environment(Workspace.self) private var workspace
    let course: LoadedCourse
    let materialId: UUID

    var body: some View {
        let file = course.file
        let unitIds = file.materials.first { $0.id == materialId }?.unitIds ?? []
        let sessions = file.sessions.sorted { ($0.week, $0.index) < ($1.week, $1.index) }
        // Outline order: `order` counts among siblings only, so sorting by it alone interleaves chapters and their units.
        let units = UnitTree.outline(file.units)
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Block("강의 회차", note: "페이지를 비우면 전체") {
                    Card {
                        if sessions.isEmpty { CardRow(last: true) { EmptyLine("회차가 없습니다") } }
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                            let link = s.materials.first { $0.materialId == materialId }
                            CardRow(last: i == sessions.count - 1) {
                                CheckCircle(on: link != nil) {
                                    workspace.run(MaterialLinkSession(course: course.id, material: materialId, session: s.id, linked: link == nil))
                                }
                                Text(s.topic.isEmpty ? course.file.name(of: s) : "\(course.file.name(of: s)) · \(s.topic)").lineLimit(1)
                                Spacer()
                                if let link {
                                    pageField("처음", link.firstPage) { setPages(s.id, $0, link.lastPage) }
                                    Text("–").foregroundStyle(Theme.Palette.textTertiary)
                                    pageField("끝", link.lastPage) { setPages(s.id, link.firstPage, $0) }
                                }
                            }
                        }
                    }
                }
                Block("단원") {
                    Card {
                        if units.isEmpty { CardRow(last: true) { EmptyLine("단원이 없습니다") } }
                        ForEach(Array(units.enumerated()), id: \.element.unit.id) { i, row in
                            let u = row.unit
                            let linked = unitIds.contains(u.id)
                            CardRow(last: i == units.count - 1) {
                                CheckCircle(on: linked) { workspace.run(MaterialLinkUnit(course: course.id, material: materialId, unit: u.id, linked: !linked)) }
                                    .padding(.leading, CGFloat(row.depth) * Theme.Space.l)
                                Text(u.title).lineLimit(1)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(Theme.Space.l)
        }
        .frame(width: 440, height: 480)
        .background(Theme.Palette.page)
        .font(Theme.Typeface.body)
    }

    func pageField(_ prompt: String, _ value: Int?, set: @escaping (Int?) -> Void) -> some View {
        TextField(prompt, value: Binding(get: { value }, set: { set($0.flatMap { $0 > 0 ? $0 : nil }) }), format: .number)
            .pill(width: 64)
    }

    func setPages(_ session: UUID, _ first: Int?, _ last: Int?) {
        workspace.run(MaterialLinkSession(course: course.id, material: materialId, session: session, firstPage: first, lastPage: last))
    }
}

extension SessionMaterial {
    /// ` p.3–10`, ` p.3–`, ` p.12`, or nothing for the whole file.
    var pageLabel: String {
        switch (firstPage, lastPage) {
        case (nil, nil): ""
        case let (a?, b?) where a == b: " p.\(a)"
        case let (a, b): " p.\(a.map(String.init) ?? "")–\(b.map(String.init) ?? "")"
        }
    }
}

extension FolioDomain.Material {
    var isPDF: Bool { !isFolder && path.lowercased().hasSuffix(".pdf") }
}

/// Where files brought in from the materials screen go: one row per kind, and for a kind with several folders
/// (assignments, exams) a second choice beneath it. A lecture needs its session, which names it by week and links it.
struct ImportPlaceSheet: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.dismiss) private var dismiss
    let course: LoadedCourse
    let files: [URL]
    let places: [String]
    @State private var place = CourseFolder.lectures.rawValue
    @State private var session: UUID?

    /// Places by kind label, in the order first met: `과제` → `Assignments/HW00`, `Assignments/HW01`, …
    var kinds: [(label: String, places: [String])] {
        var result: [(label: String, places: [String])] = []
        for p in [CourseFolder.lectures.rawValue] + places {
            let label = MaterialRole(path: p + "/_")?.label ?? p
            if let i = result.firstIndex(where: { $0.label == label }) { result[i].places.append(p) } else { result.append((label, [p])) }
        }
        return result
    }

    var body: some View {
        let kinds = kinds
        let sessions = course.file.sessions.filter { !$0.isCancelled }.sorted { ($0.week, $0.index) < ($1.week, $1.index) }
        SheetForm(title: files.count == 1 ? "\(files[0].lastPathComponent) 넣기" : "파일 \(files.count)개 넣기", confirm: "넣기",
                  note: "원본은 그대로 두고 복사합니다. 같은 이름이 있으면 덮어쓰지 않고 뒤에 번호를 붙입니다.") {
            ForEach(Array(kinds.enumerated()), id: \.element.label) { i, kind in
                let chosen = kind.places.contains(place)
                let isLecture = kind.places == [CourseFolder.lectures.rawValue]
                // Assignments and exams name which one even when there is one, so the choice reads plainly.
                let perItem = kind.places[0].contains("/") && kind.places != ["\(CourseFolder.exams.rawValue)/\(StandardLayout.pastExamsFolder)"]
                let sub = chosen && (isLecture || perItem)
                CardRow(last: i == kinds.count - 1 && !sub) {
                    CheckCircle(on: chosen) { pick(kind.places) }
                    Text(kind.label)
                    Spacer()
                    Text(chosen ? place : perItem ? "\((kind.places[0] as NSString).deletingLastPathComponent)/…" : kind.places[0])
                        .font(Theme.Typeface.mono).foregroundStyle(Theme.Palette.textTertiary)
                }
                .opens { pick(kind.places) }
                if sub && isLecture {
                    FormRow(label: "회차", last: i == kinds.count - 1) {
                        ChoiceMenu(selection: $session, options: [(nil, "회차 없음")] + sessions.map { ($0.id, course.file.name(of: $0) + ($0.topic.isEmpty ? "" : " · \($0.topic)")) })
                    }
                } else if sub {
                    FormRow(label: kind.label, last: i == kinds.count - 1) {
                        ChoiceMenu(selection: $place, options: kind.places.map { ($0, ($0 as NSString).lastPathComponent) })
                    }
                }
            }
        } onConfirm: {
            let picked = place == CourseFolder.lectures.rawValue ? sessions.first { $0.id == session } : nil
            workspace.importFiles(files, into: place, week: picked?.week, session: picked?.id, course: course.id)
            dismiss()
        }
        .onAppear { session = sessions.last { $0.date <= .now }?.id }
    }

    /// The newest folder of a kind first: the latest assignment or exam is the likely one.
    func pick(_ places: [String]) {
        if !places.contains(place) { place = places.last ?? place }
    }
}
