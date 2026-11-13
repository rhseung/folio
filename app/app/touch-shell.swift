#if os(iOS)
import FolioDomain
import SwiftUI

/// The window's frame on a touch screen: the Mac's on an iPad wide enough (#25), a tab bar on an iPhone and on an iPad
/// window as narrow as one (#134). Which one follows the horizontal size class, so an iPad app in Split View or a small
/// Stage Manager window takes the iPhone's frame and gets the Mac's back as it widens.
extension RootView {
    func touchShell(@ViewBuilder content: () -> some View) -> some View {
        Group {
            if sizeClass == .compact {
                phoneShell
            } else {
                padShell(content: content)
            }
        }
        #if DEBUG
        .task {
            // `FOLIO_OPEN="folio://… folio://…"` opens the links in turn, for window snapshots: `simctl openurl` stops
            // at a system prompt.
            let env = ProcessInfo.processInfo.environment
            try? await Task.sleep(for: .seconds(1))
            // `FOLIO_PHONE_TAB=courses|grades|search` fronts that tab of the iPhone's bar first.
            if let name = env["FOLIO_PHONE_TAB"], let tab = PhoneTab.allCases.first(where: { "\($0)" == name }) {
                phoneSelection.wrappedValue = tab
            }
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

    // MARK: iPhone

    /// The tab bar's three places, each a tab of `tabs` with its own history, and search beside them.
    enum PhoneTab: Int, Hashable, CaseIterable {
        case today, courses, grades, search
    }

    var phoneSelection: Binding<PhoneTab> {
        Binding {
            if phoneSearching { return .search }
            let index = tabs.ids.firstIndex(of: tabs.selected) ?? 0
            return PhoneTab(rawValue: min(index, PhoneTab.grades.rawValue)) ?? .today
        } set: { tab in
            if tab == .search {
                phoneSearching = true
            } else {
                phoneSearching = false
                ensurePhoneTabs()
                tabs.select(number: tab.rawValue + 1)
            }
        }
    }

    /// The tabs the tab bar's places stand for: the window's first tab is 오늘, whatever it shows, and the courses' and
    /// grades' tabs are opened at their roots the first time the window is this narrow.
    func ensurePhoneTabs() {
        guard tabs.count < 3 else { return }
        let front = tabs.selected
        let roots: [AppLink] = [phoneCoursesRoot, .place(.grades)]
        for link in roots.suffix(3 - tabs.count) {
            tabs.open(Navigator(workspace.entry(for: link) ?? Navigator.Entry(link: link)))
        }
        tabs.select(front)
    }

    /// The courses' tab opens on this term's page, which lists its courses; the rest of what the Mac's sidebar holds is
    /// in the tab's menu (`phoneCoursesMenu`).
    var phoneCoursesRoot: AppLink {
        workspace.currentSemester.map { AppLink(.semester, $0.id) } ?? .place(.people)
    }

    /// Where a link opened on the iPhone goes: the places that are the tab bar's own open in their tab, the rest in
    /// the tab in front. Nil leaves it to `pane`.
    func phoneRoute(_ entry: Navigator.Entry) -> Navigator? {
        guard sizeClass == .compact else { return nil }
        ensurePhoneTabs()
        let kind = entry.link.kind
        // Not a switch over every kind: all the others stay in the tab in front.
        let tab: PhoneTab? = if kind == .today { .today } else if kind == .grades || kind == .requirements { .grades } else {
            phoneSearching ? .courses : nil
        }
        guard let tab else { return nil }
        phoneSelection.wrappedValue = tab
        return tabs.navigator(tabs.ids[tab.rawValue])
    }

    var phoneShell: some View {
        TabView(selection: phoneSelection) {
            Tab(String(localized: .rootNavToday), systemImage: "house", value: PhoneTab.today) { phonePage(.today) }
            Tab(String(localized: .rootNavCourses), systemImage: "book.closed", value: PhoneTab.courses) { phonePage(.courses) }
            Tab(String(localized: .rootNavGrades), systemImage: "chart.line.uptrend.xyaxis", value: PhoneTab.grades) { phonePage(.grades) }
            Tab(value: PhoneTab.search, role: .search) { phoneSearch }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory { phoneAccessory }
        .onAppear { ensurePhoneTabs() }
        .sheet(isPresented: $quickAdding) {
            QuickAddField(workspace: workspace, defaultCourse: navigator.current.course, showsEmptyChips: true, focusOnAppear: true, floating: true)
                .padding(Theme.Space.l)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingRecording) {
            RecordingBar(workspace: workspace) { link in
                showingRecording = false
                open(link)
            }
            .padding(Theme.Space.l)
            .presentationDetents([.medium])
        }
        .onChange(of: workspace.recorder.isActive) { _, active in if !active { showingRecording = false } }
    }

    @ViewBuilder func phonePage(_ tab: PhoneTab) -> some View {
        if tabs.ids.indices.contains(tab.rawValue), let panes = tabs.panes(tabs.ids[tab.rawValue]) {
            let id = tabs.ids[tab.rawValue]
            PaneRow(workspace: workspace, panes: panes, front: id == tabs.selected && !phoneSearching, openLink: openLink(from:),
                    play: { [tabs] pane, pause in tabs.play(id, pane: pane, pause: pause) })
                .controlSize(.large)
                .environment(\.barePanes, true)
                .environment(\.pageGutter, Theme.Space.l)
                .environment(\.showSettings) { showSettings($0) }
                .environment(\.showInputGuide) { showInputGuide($0) }
                .safeAreaInset(edge: .top, spacing: 0) { phoneBar(tab, navigator: panes.focused) }
        } else {
            Theme.Palette.page.ignoresSafeArea()
        }
    }

    /// Round glass buttons over the page, as an iOS 26 app's: back on the left, the tab's own tools on the right. The
    /// screen keeps its own large title under them.
    func phoneBar(_ tab: PhoneTab, navigator: Navigator) -> some View {
        HStack(spacing: Theme.Space.s) {
            if navigator.history.canGoBack {
                Button(.navigationBack, systemImage: "chevron.backward") { navigator.back() }
                    .phoneGlass()
            }
            Spacer(minLength: 0)
            switch tab {
            case .today:
                Button(.rootNavSettings, systemImage: "gearshape") { open(.place(.settings)) }
                    .phoneGlass()
            case .courses:
                // At the tab's root only: a course's own page has its menu in its header.
                if !navigator.history.canGoBack { phoneCoursesMenu }
            case .grades:
                Picker(selection: Binding {
                    navigator.screen == .requirements ? Screen.requirements : Screen.grades
                } set: { open($0 == .requirements ? .place(.requirements) : .place(.grades)) }) {
                    Text(.rootNavGrades).tag(Screen.grades)
                    Text(.rootNavRequirements).tag(Screen.requirements)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .fixedSize()
            case .search:
                EmptyView()
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
        .background(Theme.Palette.page)
    }

    /// What the Mac's sidebar holds past the tab bar's places: the terms, the people and the course codes.
    var phoneCoursesMenu: some View {
        Menu {
            Section(String(localized: .rootSemesters)) {
                ForEach(sidebarSemesters.reversed(), id: \.id) { semester in
                    Button(semester.title) { open(AppLink(.semester, semester.id)) }
                }
            }
            Section {
                Button(.rootNavPeople, systemImage: "person") { open(.place(.people)) }
                Button(.rootNavCodes, systemImage: "number") { open(.place(.codes)) }
                Button(.rootNavSettings, systemImage: "gearshape") { open(.place(.settings)) }
            }
        } label: {
            Label(.rootMore, systemImage: "ellipsis")
        }
        .phoneGlass()
    }

    var phoneSearch: some View {
        // `phoneRoute` takes the result out of the search tab: to the courses' tab, or a place's own tab.
        SearchPalette(workspace: workspace, close: { phoneSelection.wrappedValue = .today }) { link, course in
            open(link, course: course)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.page)
    }

    /// Over the tab bar, where a thumb reaches: quick add, or the recording while one runs (its card opens in a sheet).
    @ViewBuilder var phoneAccessory: some View {
        if workspace.recorder.isActive {
            HStack {
                RecordingCapsule(workspace: workspace, expanded: true, openCard: { showingRecording = true }) { EmptyView() }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Space.s)
        } else {
            Button { quickAdding = true } label: {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "plus")
                    Text(.rootQuickAdd).foregroundStyle(Theme.Palette.chromeText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Space.l)
                .frame(maxWidth: .infinity, minHeight: Theme.Size.touchTarget)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

}

private extension View {
    /// A round glass button a finger's size, as the iPhone's bars draw theirs.
    func phoneGlass() -> some View {
        labelStyle(.iconOnly)
            .font(Theme.Glyph.toolbar)
            .foregroundStyle(Theme.Palette.chromeIcon)
            .frame(width: Theme.Size.touchTarget, height: Theme.Size.touchTarget)
            .contentShape(.circle)
            .glassEffect(.regular.interactive(), in: .circle)
            .buttonStyle(.plain)
    }
}
#endif
