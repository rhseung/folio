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
                // Another file starts over: page, zoom, search and unsaved text belong to the old one.
                FileView(workspace: model.workspace, course: model.course, material: m.id, requestedPage: $model.requestedPage,
                         shownPage: $model.shownPage).id(m.id)
            } else {
                list
            }
        }
        .task { await model.load() }
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
        .sheet(isPresented: $model.creatingFile) {
            NewMaterialFileSheet(workspace: model.workspace, course: model.course, folder: model.newFileFolder) { model.created($0) }
        }
        .confirming($model.pending)
        .alert(String(localized: .materialsRename), isPresented: Binding(get: { model.renaming != nil }, set: { if !$0 { model.renaming = nil } }), presenting: model.renaming) { m in
            TextField(String(localized: .materialsRenameField), text: $model.newName)
            Button(.materialsRenameConfirm) { model.rename(m) }
            Button(.commonCancel, role: .cancel) {}
        } message: { m in
            Text(model.renameMessage(m))
        }
        // The window's place opens a file, at a page if the link names one; back to the section closes it.
        .onChange(of: place, initial: true) { _, link in
            if let m = model.follow(link), !m.isFolder { open(m) }
        }
        .onChange(of: model.viewedLink) { _, link in moved(link) }
        #if DEBUG && os(macOS)
        .onChange(of: SnapshotDriver.shared.openFile, initial: true) { _, ext in
            // Fixtures ship without tracked files; register them so there is a file to show.
            if ext != nil, model.materials.isEmpty { model.workspace.run(MaterialTrack(course: model.course.id)) }
            model.viewing = ext.flatMap { ext in
                model.materials.first { !$0.isFolder && ($0.path as NSString).pathExtension.lowercased() == ext && $0.status == .classified }?.id
            }
            SnapshotDriver.shared.materialsOpenFile = model.viewing != nil
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
                                    HStack(spacing: Theme.Space.m) { fileRow(m, name: name, pdf: section.pdfs[m.id]) }
                                        .padding(.leading, CGFloat(depth) * Self.indent)
                                }
                            }
                            .contentShape(.rect)
                            .contextMenu {
                                switch row {
                                case .folder(let folder, _): folderMenu(folder)
                                case .file(let m, _, _): fileContextMenu(m, pdf: section.pdfs[m.id])
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
            Menu { folderMenu(folder) } label: {
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
        withAnimation(.snappy(duration: 0.2)) { model.toggle(folder) }
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

    @ViewBuilder func fileContextMenu(_ m: FolioDomain.Material, pdf: FolioDomain.Material?) -> some View {
        if m.status == .missing {
            Button(.materialsRelinkEllipsis) { model.relinking = m.id }
            Divider()
            Button(.materialsUntrackEllipsis, role: .destructive) { model.disconnecting = m }
        } else {
            #if os(macOS)
            Button(m.isFolder ? .materialsOpenInFinder : .materialsOpen) { open(m) }
            #else
            if !m.isFolder { Button(.materialsOpen) { open(m) } }
            #endif
            Button(.materialsLinkEllipsis) { model.linking = m.id }
            if !m.isFolder { LinkMenu(link: AppLink(.material, m.id), course: model.course.id, trailing: true) }
            Divider()
            fileMenuItems(m)
            if let pdf { pdfMenu(pdf) }
        }
    }

    /// Everything the PDF's own row had, since the list shows it only through its `.tex` (#109): links that exams and
    /// units count, renaming, and trashing a bad build.
    @ViewBuilder func pdfMenu(_ pdf: FolioDomain.Material) -> some View {
        Divider()
        // Titled by the file name, which is data rather than a phrase to translate.
        Menu((pdf.path as NSString).lastPathComponent) {
            Button(.materialsOpen) { model.open(pdf) }
            Button(.materialsLinkEllipsis) { model.linking = pdf.id }
            LinkMenu(link: AppLink(.material, pdf.id), course: model.course.id, trailing: true)
            Divider()
            fileMenuItems(pdf)
        }
    }

    @ViewBuilder func fileMenuItems(_ m: FolioDomain.Material) -> some View {
        #if os(macOS)
        // A folder's own app is Finder, which "Finder에서 열기" already is.
        if !m.isFolder { Button(.materialsOpenWithDefault) { NSWorkspace.shared.open(model.fileURL(m.path)) } }
        Button(.materialsShowInFinder) { NSWorkspace.shared.activateFileViewerSelecting([model.fileURL(m.path)]) }
        if m.isFolder { EditorMenu(url: model.fileURL(m.path)) }
        Divider()
        #endif
        Button(.materialsRenameEllipsis) { model.startRenaming(m) }
        Menu(String(localized: .materialsMoveTo)) {
            ForEach(model.moveTargets(m), id: \.self) { place in
                Button(place) { model.move(m, into: place) }
            }
        }
        Divider()
        Button(.materialsTrashEllipsis, role: .destructive) { model.trash(m) }
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
            Button(.materialsLink) { model.linking = m.id }
                .buttonStyle(.ghost)
                // The hidden PDF's links are edited from its `.tex` row, the only place left to anchor them.
                .popover(isPresented: Binding(get: { model.linking == m.id || model.linking != nil && model.linking == pdf?.id },
                                              set: { if !$0 { model.linking = nil } })) {
                    MaterialLinksEditor(model: model, materialId: model.linking ?? m.id)
                }
            // The list shows a `.tex` and its PDF as one row (#109); the PDF opens from here.
            if let pdf {
                Button(.materialsPairedPdf) { model.open(pdf) }.buttonStyle(.ghost).help(Text(.materialsOpenPdf))
            }
            #if os(macOS)
            Button(m.isFolder ? "Finder" : String(localized: .materialsOpen)) { open(m) }.buttonStyle(.ghost)
            #else
            // iPadOS has no Finder to hand a folder to.
            if !m.isFolder { Button(.materialsOpen) { open(m) }.buttonStyle(.ghost) }
            #endif
            Menu {
                fileMenuItems(m)
                if let pdf { pdfMenu(pdf) }
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
        let viaSessions = model.unitsViaSessions(of: materialId)
        let sessions = model.sessions(linking: materialId)
        let units = model.units
        let exams = model.exams
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                if model.isLecture(materialId) { LectureProgressBlock(workspace: model.workspace, course: model.course.id, material: materialId) }
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
                                if !linked && viaSessions.contains(u.id) {
                                    Text(.commonViaSessions).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                }
                            }
                        }
                    }
                }
                Block(String(localized: .materialsLinksExams)) {
                    Card {
                        if exams.isEmpty { CardRow(last: true) { EmptyLine(String(localized: .materialsLinksNoExams)) } }
                        ForEach(Array(exams.enumerated()), id: \.element.id) { i, exam in
                            let routes = model.routes(of: materialId, to: exam)
                            let linked = routes.contains(.direct)
                            CardRow(last: i == exams.count - 1) {
                                CheckCircle(on: linked) { model.link(materialId, exam: exam.id, linked: !linked) }
                                Text(exam.title).lineLimit(1)
                                Spacer()
                                if routes.contains(.folder) {
                                    Text(.materialsLinksInFolder).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                                }
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
        PageField(prompt: prompt, value: value, set: set)
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
