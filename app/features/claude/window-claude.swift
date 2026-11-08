import FolioAI
import FolioDomain
import SwiftUI

/// The tab's one Claude (#62): a button at the content's corner and the panel it opens, over all the tab's panes
/// rather than one in each. It answers in the focused pane's course (else the first open pane's in a course) and
/// sees every pane the tab shows.
struct WindowClaude: View {
    let workspace: Workspace
    let panes: TabPanes
    let folded: Set<Int>
    @Binding var shown: Bool
    @Binding var incoming: ContextItem?
    let inserts: PaneInserts
    let openLink: (Navigator) -> OpenLinkAction
    @State private var width = Theme.Size.claudePanel
    @State private var dragBase: CGFloat?

    /// Past this the panel stops growing with the window: a full-height panel read as a sidebar laid over the page.
    static let maxHeight: CGFloat = 720

    var body: some View {
        if let target = Self.target(panes: panes, folded: folded, workspace: workspace), let course = workspace.course(target.course) {
            let accent = workspace.accent(target.course)
            VStack(alignment: .trailing, spacing: Theme.Space.m) {
                if shown {
                    ClaudePanel(workspace: workspace, course: course, openNote: target.note, alsoOpen: target.alsoOpen,
                                panes: Self.context(panes: panes, folded: folded, workspace: workspace),
                                openUnit: target.unit, incoming: $incoming,
                                insertIntoNote: { text in if let pane = target.notePane { inserts[pane].text = text } }) { id in
                        openLink(panes.focused)(AppLink(.note, id), course: target.course)
                    }
                    // A panel per course: the one panel kept across a focus move took the context added in one course
                    // (`added`, `removed`) into the next one's chat.
                    .id(target.course)
                    // Inside the glass, controls wash instead of standing on it as solid fills. Set inside
                    // `floatingGlass()`, which would otherwise draw a wash instead of the glass itself.
                    .environment(\.onGlass, true)
                    // At most this wide, narrower when the panes are: a fixed width ran past a narrow window's edge.
                    .frame(maxWidth: width, maxHeight: Self.maxHeight)
                    .floatingGlass()
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                    .overlay(alignment: .leading) { resizeHandle }
                    .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
                }
                Button { shown.toggle() } label: {
                    Image(systemName: shown ? "xmark" : "sparkle")
                        .font(Theme.Glyph.fab)
                        .foregroundStyle(shown ? Theme.Palette.textSecondary : accent.color)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: Theme.Size.fab, height: Theme.Size.fab)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.pointing(.plain))
                .help(String(localized: shown ? .courseClaudeClose : .courseClaudeAsk))
                .accessibilityLabel(shown ? String(localized: .courseClaudeClose) : "Claude")
            }
            .padding(Theme.Space.l)
            .courseAccent(accent)
            .animation(.snappy(duration: 0.25), value: shown)
        }
    }

    /// The panel's leading edge. A finger needs 44pt, which stands mostly outside the panel so its first words and
    /// field still take a press.
    var resizeHandle: some View {
        #if os(iOS)
        let reach: CGFloat = 44, inside = Theme.Space.s
        #else
        let reach = Theme.Space.s, inside = Theme.Space.s
        #endif
        return Color.clear.frame(width: reach).contentShape(.rect)
            .offset(x: inside - reach)
            #if os(macOS)
            .pointerStyle(.columnResize)
            #endif
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let base = dragBase ?? width
                    dragBase = base
                    width = min(640, max(300, base - drag.translation.width))
                }
                .onEnded { _ in dragBase = nil })
    }

    /// What the panel answers about: a course, the note it writes into and the notes and unit it reads.
    struct Target: Equatable {
        var course: UUID
        var note: UUID?
        /// The pane whose note an answer is inserted into.
        var notePane: UUID?
        var alsoOpen: [UUID]
        var unit: UUID?
    }

    /// The focused pane first, then the open ones left to right; a folded pane's screen isn't in view.
    static func order(panes: TabPanes, folded: Set<Int>) -> [Int] {
        [panes.focus] + panes.ids.indices.filter { $0 != panes.focus && !folded.contains($0) }
    }

    static func target(panes: TabPanes, folded: Set<Int>, workspace: Workspace) -> Target? {
        let order = order(panes: panes, folded: folded)
        guard let course = order.lazy.compactMap({ panes.navigators[$0].current.course }).first(where: { workspace.course($0) != nil })
        else { return nil }
        let notes = order.compactMap { i -> (pane: UUID, note: UUID)? in
            let entry = panes.navigators[i].current
            guard entry.course == course, entry.link.kind == .note, let id = entry.link.id else { return nil }
            return (panes.ids[i], id)
        }
        let focused = panes.navigators[panes.focus].current
        return Target(course: course, note: notes.first?.note, notePane: notes.first?.pane, alsoOpen: notes.dropFirst().map(\.note),
                      unit: focused.course == course && focused.link.kind == .unit ? focused.link.id : nil)
    }

    static func context(panes: TabPanes, folded: Set<Int>, workspace: Workspace) -> ContextItem? {
        ContextBuilder.panes(panes.ids.indices.map { i in
            let entry = panes.navigators[i].current
            return ContextBuilder.Pane(address: entry.link.string,
                                       shows: folded.contains(i) ? nil : workspace.paneMark(of: entry, trail: panes.trails[i]).title,
                                       focused: i == panes.focus)
        })
    }
}

/// An answer's text on its way to the note a pane shows: the pane's course screen takes it (`noteInsert`).
@MainActor @Observable final class PaneInsert {
    var text: String?
}

/// One `PaneInsert` for each pane, made as first asked for. Not watched: the panes watch their own.
@MainActor final class PaneInserts {
    private var boxes: [UUID: PaneInsert] = [:]

    subscript(pane: UUID) -> PaneInsert {
        if let box = boxes[pane] { return box }
        let box = PaneInsert()
        boxes[pane] = box
        return box
    }
}

extension EnvironmentValues {
    /// Where the window's Claude puts text for the note this pane shows.
    @Entry var paneInsert: PaneInsert?
}
