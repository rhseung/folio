import FolioDomain
import FolioStorage
import SwiftUI

struct NotesView: View {
    @State private var model: NotesModel
    let note: NoteFile
    var anchor: AppLink.Anchor?
    var insert: Binding<String?> = .constant(nil)
    let moves: MoveUndo

    init(
        workspace: Workspace, course: LoadedCourse, note: NoteFile, anchor: AppLink.Anchor? = nil,
        insert: Binding<String?> = .constant(nil),
        moves: MoveUndo
    ) {
        _model = State(initialValue: NotesModel(workspace: workspace, course: course))
        self.moves = moves
        self.note = note
        self.anchor = anchor
        self.insert = insert
    }

    var body: some View {
        if note.format == .tex {
            TextFileView(workspace: model.workspace, course: model.course, note: note, moves: moves).id(note.url)
        } else {
            NoteEditor(workspace: model.workspace, course: model.course, note: note, anchor: anchor, insert: insert, moves: moves)
                .id(note.url)
        }
    }
}

extension MathSyntax {
    var label: String { String(localized: name) }
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
