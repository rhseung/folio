import Foundation

/// The note screen's two views, for what reads and moves them from beside them (the outline, #387). Not observed state:
/// the editor reports its scroll every frame.
@MainActor final class NoteViews {
    weak var editor: SourceTextView?
    weak var page: NotePreviewPage?
    /// The line at the top of the view being read, 1-based in the note's text.
    var scrolled: @MainActor (Int) -> Void = { _ in }

    /// Beside the editor the preview follows it, so the editor says where the reader is whenever it is on screen.
    var editorShown: Bool { editor?.window != nil }

    func editorScrolled(_ line: Int) { scrolled(line) }

    func previewScrolled(_ line: Int) {
        if !editorShown { scrolled(line) }
    }

    /// Puts `line` at the top: in the editor with the caret at its start (`location`), the preview following, or in the
    /// preview alone.
    func show(line: Int, location: Int) {
        if let editor, editorShown {
            editor.reveal(location)
        } else {
            page?.jump(line: line)
        }
    }
}
