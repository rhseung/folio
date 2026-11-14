import FolioDomain
import Foundation
import SwiftUI

struct NotePanes: Equatable {
    typealias Mode = NoteViewMode

    static let sideBySide: CGFloat = 880

    private(set) var mode = Mode.split
    private(set) var editing = Mode.split

    init() {}

    init(remembered: Mode) { choose(remembered) }

    func shown(wide: Bool) -> Mode { mode == .split && !wide ? .write : mode }

    mutating func choose(_ mode: Mode) {
        self.mode = mode
        if mode != .read { editing = mode }
    }

    mutating func chooseNarrow(_ mode: Mode) { choose(mode == .read ? .read : editing) }

    mutating func toggle() { choose(mode == .read ? editing : .read) }
}

extension View {
    func rememberingPanes(_ panes: Binding<NotePanes>, id: UUID?) -> some View {
        modifier(RememberingPanes(panes: panes, id: id))
    }
}

private struct RememberingPanes: ViewModifier {
    @Binding var panes: NotePanes
    let id: UUID?
    @Environment(\.paneMemory) private var paneMemory
    @Environment(\.paneNotes) private var paneNotes

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard let id else { return }
                if let mode = paneNotes?.mode(of: id) ?? paneMemory?.memory.noteMode(note: id) {
                    panes = NotePanes(remembered: mode)
                }
                paneMemory?.touch(note: id)
            }
            .onChange(of: panes.mode) { _, mode in
                guard let id else { return }
                paneNotes?.show(mode, of: id)
                paneMemory?.remember(mode, note: id)
            }
            .background {
                Button("") { panes.toggle() }.keyboardShortcut("e")
                    .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}
