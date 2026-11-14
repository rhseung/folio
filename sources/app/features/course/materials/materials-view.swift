import FolioActions
import FolioDomain
import FolioStorage
import SwiftUI

struct MaterialsView: View {
    @State private var model: MaterialsModel
    @Environment(\.accent) private var accent
    @State private var picking = false
    let place: AppLink
    let moved: (AppLink?) -> Void

    init(workspace: Workspace, course: LoadedCourse, place: AppLink, moved: @escaping (AppLink?) -> Void) {
        _model = State(initialValue: MaterialsModel(workspace: workspace, course: course))
        self.place = place
        self.moved = moved
    }

    var body: some View {
        Group {
            if let m = model.viewed {
                FileView(
                    workspace: model.workspace, course: model.course, material: m.id, requestedPage: $model.requestedPage,
                    shownPage: $model.shownPage
                ).id(m.id)
            } else {
                list
            }
        }
        .task { await model.load() }
        .fileImporter(
            isPresented: Binding(get: { model.relinking != nil }, set: { if !$0 { model.relinking = nil } }), allowedContentTypes: [.item]
        ) { result in
            if case .success(let url) = result { model.relink(to: url) }
            model.relinking = nil
        }
        .confirmationDialog(
            String(localized: .materialsUntrackConfirm),
            isPresented: Binding(get: { model.disconnecting != nil }, set: { if !$0 { model.disconnecting = nil } }),
            presenting: model.disconnecting
        ) { m in
            Button(.materialsUntrack, role: .destructive) { model.untrack(m) }
        } message: { m in
            Text(.materialsUntrackMessage(m.path))
        }
        .sheet(isPresented: Binding(get: { !model.incoming.isEmpty }, set: { if !$0 { model.incoming = [] } })) {
            ImportPlaceSheet(workspace: model.workspace, course: model.course, files: model.incoming, places: model.places)
        }
        // `linking`이 비워진 뒤 시트가 닫히는 동안에도 파일을 유지하도록 item으로 띄운다.
        .sheet(item: Binding(get: { model.linking.map(LinkedFile.init) }, set: { model.linking = $0?.id })) { file in
            MaterialLinksEditor(model: model, materialId: file.id)
        }
        .sheet(isPresented: $model.creatingFile) {
            NewMaterialFileSheet(workspace: model.workspace, course: model.course, folder: model.newFileFolder) { model.created($0) }
        }
        .confirming($model.pending)
        .onChange(of: place, initial: true) { _, link in
            if let m = model.follow(link), !m.isFolder { open(m) }
        }
        .onChange(of: model.viewedLink) { _, link in moved(link) }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.openFile, initial: true) { old, ext in
            guard ext != nil || old != nil else { return }
            if ext != nil { model.trackFixtureFiles() }
            model.viewing = ext.flatMap { ext in
                model.materials.first {
                    !$0.isFolder && ($0.path as NSString).pathExtension.lowercased() == ext && $0.status == .classified
                }?.id
            }
            SnapshotDriver.shared.materialsOpenFile = model.viewing != nil
        }
        .onChange(of: SnapshotDriver.shared.linkFile) { _, on in
            if on { model.trackFixtureFiles() }
            model.linking = on ? (model.materials.first { $0.role == .lecture && $0.isPDF } ?? model.materials.first)?.id : nil
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
                Button(.materialsNewFileEllipsis) { model.startNewFile(in: nil) }
                    .help(Text(.materialsNewFileHelp))
                Button(.materialsTrack) { model.track() }
                    .help(Text(.materialsTrackHelp))
                UndoMoveButton(moves: model.moves) { model.undo() }
            }
            // 한 뷰에 file importer를 둘 두면 마지막 것만 동작하므로, 페이지가 아니라 머리 행에 단다.
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
                                    HStack(spacing: Theme.Space.m) { fileRow(m, name: name, pdf: section.pdfs[m.id]) }
                                        .padding(.leading, CGFloat(depth) * Self.indent)
                                }
                            }
                            .contentShape(.rect)
                            .contextMenu {
                                switch row {
                                case .folder(let folder, _): folderMenu(folder)
                                case .file(let m, _, _): menu(m)
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
            Menu {
                folderMenu(folder)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless).pointingHand()
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.leading, CGFloat(depth) * Self.indent)
        .opens { toggle(folder) }
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(open ? .materialsExpanded : .materialsCollapsed))
    }

    func toggle(_ folder: PathTree<FolioDomain.Material>) {
        withAnimation(Theme.Motion.quick) { model.toggle(folder) }
    }

    @ViewBuilder func folderMenu(_ folder: PathTree<FolioDomain.Material>) -> some View {
        if model.acceptsNewFile(folder) {
            Button(.materialsNewFileEllipsis) { model.startNewFile(in: folder.path) }
            Divider()
        }
        Button(model.opened.contains(folder.path) ? .materialsCollapse : .materialsExpand) { toggle(folder) }
        #if os(macOS)
        Button(.materialsShowInFinder) { NSWorkspace.shared.activateFileViewerSelecting([model.fileURL(folder.path)]) }
        #endif
    }

    func menu(_ m: FolioDomain.Material) -> some View {
        MaterialMenu(
            courseId: model.course.id, materialId: m.id, host: .list, moves: model.moves,
            relink: { model.relinking = m.id }, untrack: { model.disconnecting = m })
    }

    @ViewBuilder func fileRow(_ m: FolioDomain.Material, name: String, pdf: FolioDomain.Material?) -> some View {
        let missing = m.status == .missing
        Image(systemName: m.isFolder ? "folder" : missing ? "exclamationmark.triangle" : m.isPDF ? "doc.richtext" : "doc")
            .foregroundStyle(missing ? Theme.Palette.danger : Theme.Palette.textSecondary)
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            Text(name).lineLimit(1).help(m.path)
            let links = model.linkLine(m, pdf: pdf)
            if !links.isEmpty { Text(links).font(Theme.Typeface.caption).foregroundStyle(accent.ink).lineLimit(1) }
        }
        .fileDrag(model.fileURL(m.path))
        Spacer()
        if missing {
            Chip(String(localized: .materialsMissing), tone: .danger)
            Button(.materialsRelink) { model.relinking = m.id }.buttonStyle(.ghost)
            Button(.materialsUntrack) { model.disconnecting = m }.buttonStyle(.ghost).tint(Theme.Palette.danger)
        } else {
            if let pdf {
                Button(.materialsPairedPdf) { model.open(pdf) }.buttonStyle(.ghost).help(Text(.materialsOpenPdf))
            }
            #if os(macOS)
            Button(m.isFolder ? "Finder" : String(localized: .materialsOpen)) { open(m) }.buttonStyle(.ghost)
            #else
            // iPadOS에는 폴더를 넘길 Finder가 없다.
            if !m.isFolder { Button(.materialsOpen) { open(m) }.buttonStyle(.ghost) }
            #endif
            Menu {
                menu(m)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless).pointingHand()
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    // MARK: Unclassified inbox

    @ViewBuilder func inbox(_ unclassified: [FolioDomain.Material]) -> some View {
        let inbox = model.inbox(unclassified)
        let prefix = model.prefix
        NoticeCard(
            title: String(localized: .materialsInboxTitle(unclassified.count)), detail: String(localized: .materialsInboxDetail),
            systemImage: "tray.fill", trailing: { EmptyView() }
        ) {
            if model.suggestions == nil {
                CardRow(last: true) {
                    ProgressView().controlSize(.small); Text(.materialsInboxLoading).foregroundStyle(Theme.Palette.textTertiary)
                }
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
                    Button(.materialsApprove) { model.approve(group) }.buttonStyle(.prominent)
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

private struct LinkedFile: Identifiable {
    let id: UUID
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
