import FolioActions
import FolioDomain
import FolioStorage
import QuickLook
import SwiftUI

struct MaterialsView: View {
    @State private var model: MaterialsModel
    @Environment(\.accent) private var accent
    @Environment(\.searchTarget) private var target
    @State private var picking = false

    init(workspace: Workspace, course: LoadedCourse) {
        _model = State(initialValue: MaterialsModel(workspace: workspace, course: course))
    }

    var body: some View {
        Group {
            if let m = model.viewed {
                MaterialViewer(model: model, material: m).id(m.id)  // another file starts over: page, zoom and search belong to the old one
            } else {
                list
            }
        }
        .task { await model.load() }
        .quickLookPreview($model.preview)
        .fileImporter(isPresented: Binding(get: { model.relinking != nil }, set: { if !$0 { model.relinking = nil } }), allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { model.relink(to: url) }
            model.relinking = nil
        }
        .confirmationDialog(String(localized: .materialsUntrackConfirm), isPresented: Binding(get: { model.disconnecting != nil }, set: { if !$0 { model.disconnecting = nil } }),
                            presenting: model.disconnecting) { m in
            Button(.materialsUntrack, role: .destructive) { model.untrack(m) }
        } message: { m in
            Text(.materialsUntrackMessage(m.path))
        }
        .sheet(isPresented: Binding(get: { !model.incoming.isEmpty }, set: { if !$0 { model.incoming = [] } })) {
            ImportPlaceSheet(workspace: model.workspace, course: model.course, files: model.incoming, places: model.places)
        }
        .confirmationDialog(String(localized: .materialsTrashConfirm), isPresented: Binding(get: { model.trashing != nil }, set: { if !$0 { model.trashing = nil } }),
                            presenting: model.trashing) { m in
            Button(.materialsTrash, role: .destructive) { model.trash(m) }
        } message: { m in
            Text(.materialsTrashMessage(m.path))
        }
        .alert(String(localized: .materialsRename), isPresented: Binding(get: { model.renaming != nil }, set: { if !$0 { model.renaming = nil } }), presenting: model.renaming) { m in
            TextField(String(localized: .materialsRenameField), text: $model.newName)
            Button(.materialsRenameConfirm) { model.rename(m) }
            Button(.commonCancel, role: .cancel) {}
        } message: { m in
            Text(model.renameMessage(m))
        }
        .onChange(of: target.wrappedValue, initial: true) { _, new in
            guard let new, new.courseId == model.course.id, let id = new.materialId else { return }
            target.wrappedValue = nil
            if let m = model.materials.first(where: { $0.id == id }) { open(m) }
        }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.openPDF, initial: true) { _, new in
            // Fixtures ship without tracked files; register them so there is a PDF to show.
            if new, model.materials.isEmpty { model.workspace.run(MaterialTrack(course: model.course.id)) }
            model.viewing = new ? model.materials.first { $0.isPDF && $0.status == .classified }?.id : nil
        }
        #endif
    }

    var list: some View {
        let materials = model.materials
        let unclassified = model.unclassified
        return Page {
            PageHeader(title: String(localized: .materialsTitle), subtitle: model.subtitle)

            if materials.isEmpty {
                EmptyLine(String(localized: .materialsEmpty))
            }
            HStack {
                Button(.materialsAddFiles) { picking = true }
                    .help(Text(.materialsAddFilesHelp))
                Button(.materialsTrack) { model.track() }
                    .help(Text(.materialsTrackHelp))
                if model.lastBatch != nil {
                    Button(.materialsUndoMove) { model.undo() }
                }
            }
            // On the header row, not the page: two file importers on one view leave only the last one working.
            .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { model.incoming = urls }
            }

            if !unclassified.isEmpty { inbox(unclassified) }

            ForEach(model.sections(), id: \.role) { section in
                Block(section.role.label, note: section.note) {
                    Card {
                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { i, row in
                            CardRow(last: i == section.rows.count - 1) {
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
        .fileDrop { model.incoming = $0 }
    }

    // MARK: Opening

    func open(_ m: FolioDomain.Material) {
        #if os(macOS)
        if m.isFolder {
            NSWorkspace.shared.open(model.fileURL(m.path))
            return
        }
        #endif
        model.open(m)
    }

    /// The chevron and its gap, so a folder's files line up under its folder icon.
    static let indent: CGFloat = 14 + Theme.Space.m

    func folderRow(_ folder: PathTree<FolioDomain.Material>, depth: Int) -> some View {
        let open = model.opened.contains(folder.path)
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
        .accessibilityValue(Text(open ? .materialsExpanded : .materialsCollapsed))
    }

    func toggle(_ folder: PathTree<FolioDomain.Material>) {
        withAnimation(.snappy(duration: 0.2)) { model.toggle(folder) }
    }

    @ViewBuilder func folderMenu(_ folder: PathTree<FolioDomain.Material>) -> some View {
        Button(model.opened.contains(folder.path) ? .materialsCollapse : .materialsExpand) { toggle(folder) }
        #if os(macOS)
        Button(.materialsShowInFinder) { NSWorkspace.shared.activateFileViewerSelecting([model.fileURL(folder.path)]) }
        #endif
    }

    @ViewBuilder func fileContextMenu(_ m: FolioDomain.Material) -> some View {
        if m.status == .missing {
            Button(.materialsRelinkEllipsis) { model.relinking = m.id }
            Divider()
            Button(.materialsUntrackEllipsis, role: .destructive) { model.disconnecting = m }
        } else {
            Button(m.isFolder ? .materialsOpenInFinder : .materialsOpen) { open(m) }
            Button(.materialsLinkEllipsis) { model.linking = m.id }
            if !m.isFolder {
                Divider()
                fileMenuItems(m)
            }
        }
    }

    @ViewBuilder func fileMenuItems(_ m: FolioDomain.Material) -> some View {
        #if os(macOS)
        Button(.materialsOpenWithDefault) { NSWorkspace.shared.open(model.fileURL(m.path)) }
        Button(.materialsShowInFinder) { NSWorkspace.shared.activateFileViewerSelecting([model.fileURL(m.path)]) }
        Divider()
        #endif
        Button(.materialsRenameEllipsis) { model.startRenaming(m) }
        Menu(String(localized: .materialsMoveTo)) {
            ForEach(model.moveTargets(m), id: \.self) { place in
                Button(place) { model.move(m, into: place) }
            }
        }
        Divider()
        Button(.materialsTrashEllipsis, role: .destructive) { model.trashing = m }
    }

    @ViewBuilder func fileRow(_ m: FolioDomain.Material, name: String) -> some View {
        let missing = m.status == .missing
        Image(systemName: m.isFolder ? "folder" : missing ? "exclamationmark.triangle" : m.isPDF ? "doc.richtext" : "doc")
            .foregroundStyle(missing ? Theme.Palette.danger : Theme.Palette.textSecondary)
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(name).lineLimit(1).help(m.path)
            let links = model.linkLine(m)
            if !links.isEmpty { Text(links).font(Theme.Typeface.caption).foregroundStyle(accent.ink).lineLimit(1) }
        }
        .fileDrag(model.fileURL(m.path))
        Spacer()
        if missing {
            Chip(String(localized: .materialsMissing), tone: .danger)
            Button(.materialsRelink) { model.relinking = m.id }.buttonStyle(.ghost)
            Button(.materialsUntrack) { model.disconnecting = m }.buttonStyle(.ghost).tint(Theme.Palette.danger)
        } else {
            Button(.materialsLink) { model.linking = m.id }
                .buttonStyle(.ghost)
                .popover(isPresented: Binding(get: { model.linking == m.id }, set: { if !$0 { model.linking = nil } })) {
                    MaterialLinksEditor(model: model, materialId: m.id)
                }
            Button(m.isFolder ? "Finder" : String(localized: .materialsOpen)) { open(m) }.buttonStyle(.ghost)
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
        let inbox = model.inbox(unclassified)
        let prefix = model.prefix
        NoticeCard(title: String(localized: .materialsInboxTitle(unclassified.count)), detail: String(localized: .materialsInboxDetail),
                   systemImage: "tray.fill", trailing: { EmptyView() }) {
                if model.suggestions == nil {
                    CardRow(last: true) { ProgressView().controlSize(.small); Text(.materialsInboxLoading).foregroundStyle(Theme.Palette.textTertiary) }
                }
                ForEach(Array(inbox.groups.enumerated()), id: \.element) { i, group in
                    let files = model.files(in: group, among: unclassified)
                    CardRow(last: i == inbox.groups.count - 1 && inbox.orphans.isEmpty) {
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            Text(model.source(group))
                                .font(Theme.Typeface.bodyStrong).lineLimit(1)
                            HStack(spacing: Theme.Space.tight) {
                                Image(systemName: "arrow.turn.down.right").foregroundStyle(Theme.Palette.textTertiary)
                                Text(model.target(group))
                                    .font(Theme.Typeface.mono).lineLimit(1)
                                if let reason = group[0].review { Chip(reason.label, tone: .warning) }
                            }
                        }
                        Spacer()
                        Button(.materialsApprove) { model.approve(group) }.buttonStyle(.pointing(.borderedProminent))
                        relocateMenu(group.map(\.from))
                        Button(.materialsIgnore) { model.ignore(files) }.buttonStyle(.ghost)
                    }
                    .contentShape(.rect)
                    .contextMenu {
                        Button(.materialsApprove) { model.approve(group) }
                        relocateMenu(group.map(\.from))
                        Divider()
                        Button(.materialsIgnore) { model.ignore(files) }
                    }
                }
                ForEach(Array(inbox.orphans.enumerated()), id: \.element.id) { i, m in
                    CardRow(last: i == inbox.orphans.count - 1) {
                        Text(m.path).font(Theme.Typeface.bodyStrong).lineLimit(1)
                        Spacer()
                        relocateMenu([prefix + m.path])
                        Button(.materialsIgnore) { model.ignore([m.id]) }.buttonStyle(.ghost)
                    }
                    .contentShape(.rect)
                    .contextMenu {
                        relocateMenu([prefix + m.path])
                        Divider()
                        Button(.materialsIgnore) { model.ignore([m.id]) }
                    }
                }
        }
    }

    func relocateMenu(_ sources: [String]) -> some View {
        Menu(String(localized: .materialsRelocate)) {
            ForEach(model.relocations, id: \.self) { place in
                Button(place) { model.relocate(sources, to: place) }
            }
        }
        .fixedSize()
    }
}

struct MaterialLinksEditor: View {
    let model: MaterialsModel
    let materialId: UUID

    var body: some View {
        let unitIds = model.unitIds(of: materialId)
        let sessions = model.sessions
        let units = model.units
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Block(String(localized: .materialsLinksSessions), note: String(localized: .materialsLinksSessionsNote)) {
                    Card {
                        if sessions.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .materialsLinksNoSessions)) } }
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                            let link = s.materials.first { $0.materialId == materialId }
                            CardRow(last: i == sessions.count - 1) {
                                CheckCircle(on: link != nil) { model.link(materialId, session: s.id, linked: link == nil) }
                                Text(model.sessionTitle(s)).lineLimit(1)
                                Spacer()
                                if let link {
                                    pageField(String(localized: .materialsLinksFirstPage), link.firstPage) { model.setPages(materialId, session: s.id, $0, link.lastPage) }
                                    Text("–").foregroundStyle(Theme.Palette.textTertiary)
                                    pageField(String(localized: .materialsLinksLastPage), link.lastPage) { model.setPages(materialId, session: s.id, link.firstPage, $0) }
                                }
                            }
                        }
                    }
                }
                Block(String(localized: .materialsLinksUnits)) {
                    Card {
                        if units.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .materialsLinksNoUnits)) } }
                        ForEach(Array(units.enumerated()), id: \.element.unit.id) { i, row in
                            let u = row.unit
                            let linked = unitIds.contains(u.id)
                            CardRow(last: i == units.count - 1) {
                                CheckCircle(on: linked) { model.link(materialId, unit: u.id, linked: !linked) }
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
}

extension SessionMaterial {
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

struct ImportPlaceSheet: View {
    @State private var model: ImportPlaceModel
    @Environment(\.dismiss) private var dismiss

    init(workspace: Workspace, course: LoadedCourse, files: [URL], places: [String]) {
        _model = State(initialValue: ImportPlaceModel(workspace: workspace, course: course, files: files, places: places))
    }

    var body: some View {
        let kinds = model.kinds
        SheetForm(title: model.title, confirm: String(localized: .materialsImportConfirm), note: String(localized: .materialsImportNote)) {
            ForEach(Array(kinds.enumerated()), id: \.element.label) { i, kind in
                let chosen = kind.places.contains(model.place)
                let sub = chosen && (kind.isLecture || kind.perItem)
                CardRow(last: i == kinds.count - 1 && !sub) {
                    CheckCircle(on: chosen) { model.pick(kind.places) }
                    Text(kind.label)
                    Spacer()
                    Text(model.shown(kind))
                        .font(Theme.Typeface.mono).foregroundStyle(Theme.Palette.textTertiary)
                }
                .opens { model.pick(kind.places) }
                if sub && kind.isLecture {
                    FormRow(label: String(localized: .materialsImportSession), last: i == kinds.count - 1) {
                        ChoiceMenu(selection: $model.session, options: model.sessionOptions)
                    }
                } else if sub {
                    FormRow(label: kind.label, last: i == kinds.count - 1) {
                        ChoiceMenu(selection: Binding(get: { model.place }, set: { model.choose($0) }), options: kind.places.map { ($0, ($0 as NSString).lastPathComponent) })
                    }
                }
            }
        } onConfirm: {
            model.confirm()
            dismiss()
        }
    }
}
