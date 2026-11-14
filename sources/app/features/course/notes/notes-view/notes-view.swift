import FolioDomain
import FolioStorage
import SwiftUI

struct NotesView: View {
    @State private var model: NotesModel
    let selection: UUID?
    var anchor: AppLink.Anchor?
    var insert: Binding<String?> = .constant(nil)
    let moves: MoveUndo

    init(
        workspace: Workspace, course: LoadedCourse, selection: UUID?, anchor: AppLink.Anchor? = nil,
        insert: Binding<String?> = .constant(nil),
        moves: MoveUndo
    ) {
        _model = State(initialValue: NotesModel(workspace: workspace, course: course))
        self.moves = moves
        self.selection = selection
        self.anchor = anchor
        self.insert = insert
    }

    var body: some View {
        if let note = model.note(selection) {
            if note.format == .tex {
                TextFileView(workspace: model.workspace, course: model.course, note: note, moves: moves).id(note.url)
            } else {
                NoteEditor(workspace: model.workspace, course: model.course, note: note, anchor: anchor, insert: insert, moves: moves)
                    .id(note.url)
            }
        } else {
            ContentUnavailableView(String(localized: .notesChoose), systemImage: "doc.text", description: Text(.notesChooseDetail))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.Palette.page)
        }
    }
}

extension MathSyntax {
    var label: String {
        switch self {
        case .latex: "LaTeX"
        case .asciimath: "AsciiMath"
        }
    }
}

extension NoteKind {
    var label: String {
        switch self {
        case .rough: String(localized: .notesKindRough)
        case .review: String(localized: .notesKindReview)
        case .examSummary: String(localized: .notesKindExamSummary)
        case .unit: String(localized: .notesKindUnit)
        case .free: String(localized: .notesKindFree)
        }
    }
}
