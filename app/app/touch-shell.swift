#if os(iOS)
import FolioDomain
import SwiftUI

/// The window's frame on a touch screen: the Mac's on the iPad (#25).
extension RootView {
    func touchShell(@ViewBuilder content: () -> some View) -> some View {
        Group {
            padShell(content: content)
        }
        #if DEBUG
        .task {
            // `FOLIO_OPEN="folio://… folio://…"` opens the links in turn, for window snapshots: `simctl openurl` stops
            // at a system prompt.
            let env = ProcessInfo.processInfo.environment
            try? await Task.sleep(for: .seconds(1))
            guard let links = env["FOLIO_OPEN"] else { return }
            for word in links.split(separator: " ") {
                if let url = URL(string: String(word)), let link = AppLink(url: url) { open(link) }
            }
        }
        #endif
    }

    // MARK: iPad

    /// As on the Mac: the toolbar row and the sidebar sit flat on the frame, and each pane is a rounded paper panel
    /// inside it (`PaneRow`). Not a NavigationSplitView, whose toolbar the screens never filled (they have no
    /// NavigationStack) and which left the window with no search, tabs or tools in sight.
    func padShell(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            padRow
            HStack(spacing: 0) {
                if sidebarOpen {
                    sidebar
                        .scrollContentBackground(.hidden)
                        .frame(width: Theme.Size.sidebar)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                content()
                    .padding([.trailing, .bottom], Theme.Size.panelInset)
                    .padding(.leading, sidebarOpen ? 0 : Theme.Size.panelInset)
            }
            // The panel runs down to the screen's bottom edge; the home indicator lies over the page as over any app's.
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(Theme.Palette.frame.ignoresSafeArea())
        .animation(.snappy(duration: 0.25), value: sidebarOpen)
    }

    /// Below this the window's search is a round button, so the trail keeps room for its first and last steps.
    static let padNarrow: CGFloat = 900

    var padRow: some View {
        let narrow = windowWidth <= Self.padNarrow
        let search = narrow ? Theme.Size.toolbarButton : Theme.Size.searchField
        // What the row holds besides the trail, at its widest: the sidebar button, back and forward, the search, the
        // record button and the four tools, the gaps between them, and the row's margins.
        let others = Theme.Size.toolbarButton * 8 + search + Theme.Space.s * 6 + Theme.Space.l * 2
        let room = max(Breadcrumb.minWidth, windowWidth - others - Theme.Space.m * 2)
        return HStack(spacing: Theme.Space.s) {
            Button(sidebarOpen ? .rootSidebarClose : .rootSidebarOpen, systemImage: "sidebar.leading") { sidebarOpen.toggle() }
                .labelStyle(.iconOnly)
                .buttonStyle(.toolbar)
                .toolbarGroup()
            HistoryButtons(navigator: navigator) { workspace.title(of: $0) }
            Breadcrumb(crumbs: crumbs, foldWidth: room, maxWidth: room)
                .toolbarField()
            Spacer(minLength: Theme.Space.s)
            padSearch(round: narrow)
            recordButton
            tools
        }
        .padding(.horizontal, Theme.Space.l)
        .frame(height: Theme.Size.toolbarRow)
    }

    func padSearch(round: Bool) -> some View {
        Button { searching = true } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "magnifyingglass")
                if !round { Text(.commonSearch) }
            }
            .foregroundStyle(Theme.Palette.chromeText)
            .frame(width: round ? Theme.Size.toolbarButton : Theme.Size.searchField - Theme.Space.m * 2, alignment: round ? .center : .leading)
            .padding(.horizontal, round ? 0 : Theme.Space.m)
            .frame(height: Theme.Size.toolbarButton)
            .background(Theme.Palette.text.opacity(Theme.Opacity.wash), in: .capsule)
            .overlay { Capsule().strokeBorder(Theme.Palette.text.opacity(Theme.Opacity.edge)) }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.commonSearch))
    }
}
#endif
