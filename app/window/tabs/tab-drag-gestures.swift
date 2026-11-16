import SwiftUI

extension View {
    func tabDrag(_ drag: TabDrag, _ item: TabDrop.Item) -> some View { modifier(TabDragGesture(drag: drag, item: item)) }

    func tabDragStrip(_ drag: TabDrag, row: [UUID]) -> some View { modifier(TabDragStrip(drag: drag, row: row)) }
}

private struct TabDragGesture: ViewModifier {
    let drag: TabDrag
    let item: TabDrop.Item
    @GestureState private var active = false

    // 길게 누르기 메뉴보다 짧아야 한다. 들어 올린 뒤 손가락을 움직이면 끌기가 되고, 그대로 더 누르고 있으면 메뉴가 뜬다.
    static let lift = 0.25

    func body(content: Content) -> some View {
        let moving = drag.dragged == item
        content
            .offset(x: moving ? drag.offset : 0)
            .opacity(moving && drag.lifted ? Theme.Opacity.soft : 1)
            // offset 밖에서 잰다. 끄는 탭의 자리는 줄이 놓은 자리여야 끄는 거리에서 offset을 다시 셀 수 있다.
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(TabBar.space))
            } action: { frame in
                if case .tab(let id) = item { drag.frames[id] = frame }
            }
            .zIndex(moving ? 1 : 0)
            .simultaneousGesture(gesture)
            .onChange(of: active) { _, now in if !now { drag.finish() } }
    }

    #if os(iOS)
    // 손가락으로는 길게 눌러 들어 올린 뒤에만 끈다. 바로 끌면 탭을 누르는 손과 창을 쓸어 넘기는 손이 탭을 옮겼다.
    var gesture: some Gesture {
        LongPressGesture(minimumDuration: Self.lift)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(TabBar.space)))
            .updating($active) { value, state, _ in
                if case .second(true, _?) = value { state = true }
            }
            .onChanged { value in
                guard case .second(true, let value?) = value else { return }
                drag.changed(item, location: value.location, start: value.startLocation, translation: value.translation.width)
            }
            .onEnded { value in
                guard case .second(true, let value?) = value else { return drag.finish() }
                drag.ended(item, location: value.location)
            }
    }
    #else
    var gesture: some Gesture {
        DragGesture(minimumDistance: Theme.Space.xs, coordinateSpace: .named(TabBar.space))
            .updating($active) { _, state, _ in state = true }
            .onChanged { value in
                drag.changed(item, location: value.location, start: value.startLocation, translation: value.translation.width)
            }
            .onEnded { drag.ended(item, location: $0.location) }
    }
    #endif
}

private struct TabDragStrip: ViewModifier {
    let drag: TabDrag
    let row: [UUID]
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .global)
            } action: {
                drag.strip = $0
            }
            .onChange(of: row, initial: true) { _, row in drag.row = row }
            .overlay(alignment: .leading) {
                if let caret = drag.caret {
                    Capsule().fill(Theme.Palette.chromeSelected)
                        .frame(width: Theme.Space.xxs, height: Theme.Size.toolbarButton)
                        .offset(x: caret - Theme.Space.xxs / 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onAppear { [openWindow] in drag.openWindow = { openWindow(id: FolioApp.mainWindow, value: $0) } }
            #if os(macOS)
        .background { WindowReader { drag.window = $0 } }
            #endif
    }
}
