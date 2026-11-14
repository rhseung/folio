import Foundation

@MainActor final class NoteViews {
    weak var editor: SourceTextView?
    weak var page: NotePreviewPage?
    var scrolled: @MainActor (Int) -> Void = { _ in }

    var editorShown: Bool { editor?.window != nil }

    func editorScrolled(_ line: Int) { scrolled(line) }

    func previewScrolled(_ line: Int) {
        if !editorShown { scrolled(line) }
    }

    func show(line: Int, location: Int) {
        if let editor, editorShown {
            editor.reveal(location)
        } else {
            page?.jump(line: line)
        }
    }
}
