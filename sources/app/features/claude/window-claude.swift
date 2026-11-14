import FolioAI
import FolioDomain
import SwiftUI

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

    static let maxHeight: CGFloat = 720

    var body: some View {
        if let target = Self.target(panes: panes, folded: folded, workspace: workspace), let course = workspace.course(target.course) {
            let accent = workspace.accent(target.course)
            VStack(alignment: .trailing, spacing: Theme.Space.m) {
                if shown {
                    ClaudePanel(
                        workspace: workspace, course: course, openNote: target.note, alsoOpen: target.alsoOpen,
                        panes: Self.context(panes: panes, folded: folded, workspace: workspace),
                        openUnit: target.unit, incoming: $incoming,
                        insertIntoNote: { text in if let pane = target.notePane { inserts[pane].text = text } }
                    ) { id in
                        openLink(panes.focused)(AppLink(.note, id), course: target.course)
                    }
                    // 과목마다 패널을 따로 둔다. 초점을 옮겨도 패널 하나를 유지하면 한 과목에서 더한 맥락(`added`,
                    // `removed`)이 다음 과목의 대화로 넘어갔다.
                    .id(target.course)
                    // 유리 안에서는 컨트롤을 단색 채움이 아니라 옅은 색으로 그린다. `floatingGlass()` 안에서 설정해야
                    // 하고, 밖에서 설정하면 유리 대신 옅은 색을 그린다.
                    .environment(\.onGlass, true)
                    // 고정 폭은 좁은 창의 가장자리를 넘었으므로, 칸들이 좁으면 이보다 좁게 둔다.
                    .frame(maxWidth: width, maxHeight: Self.maxHeight)
                    .floatingGlass()
                    .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                    .overlay(alignment: .leading) { resizeHandle }
                    .transition(.scale(scale: 0.9, anchor: .bottomTrailing).combined(with: .opacity))
                }
                Button {
                    shown.toggle()
                } label: {
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
            .animation(Theme.Motion.standard, value: shown)
        }
    }

    // 손가락에는 44pt가 필요하다. 그 대부분을 패널 밖에 두어야 패널의 첫 글자와 입력 칸이 계속 누름을 받는다.
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
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let base = dragBase ?? width
                        dragBase = base
                        width = min(640, max(300, base - drag.translation.width))
                    }
                    .onEnded { _ in dragBase = nil })
    }

    struct Target: Equatable {
        var course: UUID
        var note: UUID?
        var notePane: UUID?
        var alsoOpen: [UUID]
        var unit: UUID?
    }

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
        return Target(
            course: course, note: notes.first?.note, notePane: notes.first?.pane, alsoOpen: notes.dropFirst().map(\.note),
            unit: focused.course == course && focused.link.kind == .unit ? focused.link.id : nil)
    }

    static func context(panes: TabPanes, folded: Set<Int>, workspace: Workspace) -> ContextItem? {
        ContextBuilder.panes(
            panes.ids.indices.map { i in
                let entry = panes.navigators[i].current
                return ContextBuilder.Pane(
                    address: entry.link.string,
                    shows: folded.contains(i) ? nil : workspace.paneMark(of: entry, trail: panes.trails[i]).title,
                    focused: i == panes.focus)
            })
    }
}

@MainActor @Observable final class PaneInsert {
    var text: String?
}

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
    @Entry var paneInsert: PaneInsert?
}
