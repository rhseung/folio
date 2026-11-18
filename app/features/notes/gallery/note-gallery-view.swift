import FolioDomain
import FolioStorage
import SwiftUI

struct NoteGalleryView: View {
    @State private var model: NoteGalleryModel
    let open: (UUID) -> Void

    init(workspace: Workspace, course: LoadedCourse, moves: MoveUndo, open: @escaping (UUID) -> Void) {
        _model = State(initialValue: NoteGalleryModel(workspace: workspace, course: course, moves: moves))
        self.open = open
    }

    var body: some View {
        let sections = model.sections
        Page {
            header
            let missing = model.missingReviews
            if !missing.isEmpty { missingCard(missing) }
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                tools
                if model.searching {
                    SearchField(prompt: String(localized: .notesGallerySearch), text: $model.query)
                }
            }
            if sections.isEmpty {
                EmptyCard(systemImage: "doc.text", title: model.emptyTitle)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    ForEach(sections) { section in
                        NoteSection(model: model, section: section, open: open)
                    }
                }
            }
        }
        .sheet(isPresented: $model.adding) {
            NewNoteSheet(workspace: model.workspace, course: model.course, kind: model.newKind) { id in
                model.reload()
                open(id)
            }
        }
        .confirming($model.pending)
        .onChange(of: model.notesRevision) { model.reload() }
        .task(id: model.course.id) { model.reload() }
    }

    var header: some View {
        HStack(alignment: .bottom, spacing: Theme.Space.s) {
            PageHeader(title: String(localized: .notesGalleryTitle), subtitle: model.subtitle)
            Spacer(minLength: Theme.Space.s)
            UndoMoveButton(moves: model.moves) { model.undoMove() }
            // 좁은 폭에서는 도구 줄에 돋보기가 들어갈 자리가 없어 새 노트 옆에 둔다.
            if model.compact { searchButton }
            Button(.notesGalleryNew) { model.adding = true }
                .buttonStyle(.prominent)
        }
    }

    func missingCard(_ sessions: [Session]) -> some View {
        let shown = sessions.prefix(3)
        return NoticeCard(
            title: String(localized: .notesGalleryMissingReview(sessions.count)), systemImage: "square.and.pencil",
            trailing: { EmptyView() },
            rows: {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, s in
                    CardRow(last: i == shown.count - 1 && sessions.count <= shown.count) {
                        Text(model.sessionTitle(s)).lineLimit(1)
                        Spacer(minLength: Theme.Space.m)
                        Button(.notesGalleryMakeNote) { if let id = model.makeReviewNote(s) { open(id) } }
                            .buttonStyle(.ghost)
                    }
                }
                if sessions.count > shown.count {
                    CardRow(last: true) { EmptyLine(String(localized: .commonMoreCount(sessions.count - shown.count))) }
                }
            })
    }

    var tools: some View {
        HStack(spacing: Theme.Space.s) {
            SegmentedControl(selection: $model.kind, options: model.kindOptions, size: model.compact ? .small : .regular)
            Spacer(minLength: 0)
            if model.compact {
                viewMenu
            } else {
                Select(selection: $model.sort, options: model.sortOptions)
                if model.choosesGrouping {
                    Select(selection: $model.grouping, options: model.groupingOptions)
                }
                searchButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { model.width = $0 }
    }

    var searchButton: some View {
        Button {
            withAnimation(Theme.Motion.quick) { model.searching.toggle() }
        } label: {
            Image(systemName: "magnifyingglass")
                .frame(width: Theme.Size.touchTarget, height: Theme.Size.touchTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.ghost)
        .help(Text(.notesGallerySearchHelp))
        .accessibilityLabel(Text(.notesGallerySearchHelp))
    }

    // 정렬과 묶기를 한 메뉴의 두 묶음으로 담는다. 캡슐 둘이 들어갈 자리가 없는 폭에서 쓴다.
    var viewMenu: some View {
        Menu {
            Picker(selection: $model.sort) {
                ForEach(model.sorts, id: \.self) { Text($0.label).tag($0) }
            } label: {
                Text(.notesGallerySort)
            }
            .pickerStyle(.inline)
            if model.choosesGrouping {
                Picker(selection: $model.grouping) {
                    ForEach(model.groupings, id: \.self) { Text($0.label).tag($0) }
                } label: {
                    Text(.notesGalleryGroup)
                }
                .pickerStyle(.inline)
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(Theme.Palette.text)
                .frame(width: Theme.Size.touchTarget, height: Theme.Size.touchTarget)
                .background(Theme.Palette.fill, in: .circle)
                .contentShape(.circle)
                .accessibilityLabel(Text(.notesGalleryViewHelp))
        }
        .menuButton(indicator: .hidden)
        .fixedSize()
        .help(Text(.notesGalleryViewHelp))
    }
}

private struct NoteSection: View {
    let model: NoteGalleryModel
    let section: NoteGallery.Section
    let open: (UUID) -> Void

    var body: some View {
        let isOpen = model.isOpen(section)
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            if let heading = section.heading { head(heading, isOpen: isOpen) }
            if isOpen {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: model.compact ? Theme.Size.noteCardCompact : Theme.Size.noteCard), spacing: Theme.Space.m,
                            alignment: .top)
                    ],
                    alignment: .leading, spacing: Theme.Space.m
                ) {
                    ForEach(section.items, id: \.url) { item in card(item) }
                }
            }
        }
    }

    func head(_ heading: NoteGallery.Heading, isOpen: Bool) -> some View {
        Button {
            withAnimation(Theme.Motion.quick) { model.toggle(section) }
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "chevron.right")
                    .font(Theme.Glyph.small)
                    .foregroundStyle(Theme.Palette.textTertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .accessibilityHidden(true)
                Text(model.title(heading))
                    .font(Theme.Typeface.bodyLarge.weight(.semibold))
                    .foregroundStyle(isOpen ? Theme.Palette.text : Theme.Palette.textSecondary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(section.items.count, format: .number).monospacedDigit().foregroundStyle(Theme.Palette.textTertiary).fixedSize()
                if let detail = model.detail(section) {
                    Text(detail).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Size.touchTarget, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .contextMenu {
            Button(.notesGalleryCollapseAll) { withAnimation(Theme.Motion.quick) { model.setAll(open: false) } }
            Button(.notesGalleryExpandAll) { withAnimation(Theme.Motion.quick) { model.setAll(open: true) } }
        }
    }

    @ViewBuilder func card(_ item: NoteGallery.Item) -> some View {
        if let note = model.note(item) {
            Button {
                if let id = model.open(note) { open(id) }
            } label: {
                NoteCard(text: model.card(item), compact: model.compact)
            }
            .buttonStyle(.pointing(.plain))
            .help(item.title)
            .contextMenu {
                NoteMenu(
                    courseId: model.course.id, note: note, host: .list, moves: model.moves,
                    open: { if let id = model.open(note) { open(id) } })
            }
        }
    }
}
