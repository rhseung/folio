import FolioDomain
import SwiftUI

// 앞의 화면만 보이고 포인터와 키를 받는다. 그렇지 않으면 남겨 둔 화면의 ⌘S나 ⌘E, 그 화면이 보이는 파일의 확대 키가
// 보이지 않는 페이지에 작용한다.
struct TabScreens: View {
    let tabs: WindowTabs
    let workspace: Workspace
    let openLink: (Navigator) -> OpenLinkAction
    @State private var sizes = ScreenSizes()
    #if os(iOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var newTab: ((Navigator, ColumnPrefs) -> Void)? {
        let here: (Navigator, ColumnPrefs) -> Void = { [tabs] navigator, columns in tabs.open(navigator, columns: columns, fromLink: true) }
        #if os(macOS)
        return here
        #else
        if sizeClass == .regular { return here }
        guard multipleWindows else { return nil }
        return { [openWindow] navigator, columns in
            var request = WindowRequest(link: navigator.current.link, course: navigator.current.course, history: navigator.history)
            request.columns = [columns.names]
            openWindow(id: FolioApp.mainWindow, value: request)
        }
        #endif
    }

    var body: some View {
        ZStack {
            ForEach(tabs.ids.filter { tabs.alive.contains($0) }, id: \.self) { id in
                if let panes = tabs.panes(id) {
                    let front = id == tabs.selected
                    let kept = front ? nil : sizes[id]
                    PaneRow(
                        workspace: workspace, panes: panes, front: front, openLink: openLink,
                        play: { [tabs] pane, pause in tabs.play(id, pane: pane, pause: pause) },
                        newTab: newTab
                    )
                    .onGeometryChange(for: CGSize.self, of: \.size) { sizes[id] = $0 }
                    .frame(width: kept?.width, height: kept?.height, alignment: .topLeading)
                    // 안의 화면과 상관없이 창 크기를 준다. 최소 크기가 없으면 뒤의 화면이 stack을 자기 크기로 정해 앞의 화면을 창 밖으로
                    // 밀어냈다.
                    .frame(
                        minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity,
                        alignment: kept == nil ? .center : .topLeading
                    )
                    .opacity(front ? 1 : 0)
                    .allowsHitTesting(front)
                    .disabled(!front)
                    .accessibilityHidden(!front)
                    .zIndex(front ? 1 : 0)
                }
            }
        }
        .onChange(of: tabs.alive) { _, alive in sizes.keep(alive) }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            tabs.contentFrame = $0
        }
        .overlay { MergeMark(tabs: tabs) }
    }
}

private struct MergeMark: View {
    let tabs: WindowTabs

    var body: some View {
        let drop = tabs.drop
        GeometryReader { proxy in
            if let drop {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.floating)
                shape.fill(Theme.Palette.chromeSelected.opacity(Theme.Opacity.tint))
                    .overlay { shape.strokeBorder(Theme.Palette.chromeSelected, lineWidth: 1) }
                    .frame(width: proxy.size.width * drop.share)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: drop.edge == .leading ? .leading : .trailing)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(Theme.Motion.quick, value: drop)
    }
}
