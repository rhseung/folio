import FolioDomain
import FolioStorage
import SwiftUI

struct NoteList: View {
    @State private var model: NoteListModel
    @Environment(\.accent) private var accent
    @Binding var selection: UUID?

    init(workspace: Workspace, course: LoadedCourse, selection: Binding<UUID?>, moves: MoveUndo) {
        _model = State(initialValue: NoteListModel(workspace: workspace, course: course, moves: moves))
        _selection = selection
    }

    var body: some View {
        let shown = model.shown
        let parts = model.parts
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            HStack {
                Caption(String(localized: .notesCount(shown.count)))
                Spacer()
                ChoiceMenu(selection: $model.filter, options: model.filterOptions)
                Button {
                    model.adding = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.ghost)
                .help(model.addHelp)
            }
            .padding(.horizontal, Theme.Space.s)
            .padding(.bottom, Theme.Space.xs)
            UndoMoveButton(moves: model.moves) { model.undoMove() }
                .padding(.horizontal, Theme.Space.s)
                .padding(.bottom, Theme.Space.xs)
            if shown.isEmpty {
                Text(model.emptyLine)
                    .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                    .padding(Theme.Inset.listRow)
            }
            ForEach(parts) { part in
                if parts.count > 1 {
                    Caption(String(localized: .notesSection(part.title, part.rows.count)))
                        .padding(.horizontal, Theme.Space.s).padding(.top, Theme.Space.m).padding(.bottom, Theme.Space.xxs)
                }
                ForEach(part.rows) { row($0) }
            }
        }
        .sheet(isPresented: $model.adding) {
            NewNoteSheet(workspace: model.workspace, course: model.course, kind: model.filter ?? .free) { id in
                model.reload()
                selection = id
            }
        }
        .confirming($model.pending)
        .onChange(of: model.notesRevision) { model.reload() }
        .task(id: model.course.id) {
            model.reload()
            #if DEBUG && os(macOS)
            if SnapshotDriver.directory != nil, selection == nil { selection = model.parts.first?.rows.first?.note.meta.id }
            #endif
        }
    }

    func row(_ row: NoteListModel.Row) -> some View {
        let note = row.note
        let selected = note.meta.id != nil && note.meta.id == selection
        return Button {
            open(note)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(note.title).lineLimit(1)
                if let detail = row.detail {
                    Text(detail).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
                }
            }
            .fontWeight(selected ? .semibold : .regular)
            .padding(Theme.Inset.listRow)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? accent.tint : .clear, in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.pointing(.plain))
        .help(note.title)
        .contextMenu {
            NoteMenu(
                courseId: model.course.id, note: note, host: .list, moves: model.moves, open: { open(note) },
                removed: {
                    if note.meta.id != nil && note.meta.id == selection { selection = nil }
                })
        }
    }

    func open(_ note: NoteFile) {
        if let id = model.open(note) { selection = id }
    }
}
