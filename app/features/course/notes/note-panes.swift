import FolioDomain
import Foundation
import SwiftUI

/// What the note panel shows. A narrow panel can't fit two columns, so there `split` shows the source alone.
/// A `.tex` shows the same three ways, its built PDF standing for the preview.
struct NotePanes: Equatable {
    typealias Mode = NoteViewMode

    /// Below this a panel is too narrow for the source and the preview side by side.
    static let sideBySide: CGFloat = 880

    private(set) var mode = Mode.split
    /// The way back from reading, so ⌘E and a narrow panel's 편집 return to the column(s) last written in.
    private(set) var editing = Mode.split

    init() {}

    /// Opened the way the note was last left (`PaneMemory`). Left reading, ⌘E still goes to the split.
    init(remembered: Mode) { choose(remembered) }

    func shown(wide: Bool) -> Mode { mode == .split && !wide ? .write : mode }

    mutating func choose(_ mode: Mode) {
        self.mode = mode
        if mode != .read { editing = mode }
    }

    /// A narrow panel offers only reading and writing; writing there brings back the split too, should the panel widen.
    mutating func chooseNarrow(_ mode: Mode) { choose(mode == .read ? .read : editing) }

    mutating func toggle() { choose(mode == .read ? editing : .read) }
}

/// The bar's switch between the preview, both, and the source, for a markdown note and a `.tex` alike.
struct NotePanesPicker: View {
    @Binding var panes: NotePanes
    let wide: Bool

    var body: some View {
        if wide {
            Segmented(selection: Binding { panes.mode } set: { panes.choose($0) },
                      options: [(.read, String(localized: .notesModeRead)), (.split, String(localized: .notesModeSplit)),
                                (.write, String(localized: .notesModeWrite))],
                      compact: true)
            .help(Text(.notesModeToggle))
        } else {
            Segmented(selection: Binding { panes.shown(wide: false) } set: { panes.chooseNarrow($0) },
                      options: [(.read, String(localized: .notesModeRead)), (.write, String(localized: .notesModeWrite))],
                      compact: true)
            .help(Text(.notesModeToggle))
        }
    }
}

extension View {
    /// Opens `panes` the way the item `id` was last left on this device and remembers each change, with ⌘E toggling.
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
            // The pane's own first: a class's layout brought back shows its note as it was left there, before how the
            // note was last shown anywhere (#62).
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
