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
        .animation(Theme.Motion.standard, value: sidebarOpen)
    }

    /// The toolbar is not the Mac's (2026-11-13): the search field is the sidebar's top, and of the tools only the mic
    /// and quick add stay out, the two a class can't wait for; the rest are one "…". The room they leave goes to the
    /// window's tabs, as on the Mac (`TabBar`), which fold to icons and a "+n" menu as it runs out.
    var padRow: some View {
        // Laid out as the Mac's `TitleRow`: nothing between the history buttons and the tabs, which keep their own
        // lead (`ToolbarRow.lead`) so the first tab lines up with the panel's edge.
        HStack(spacing: 0) {
            HStack(spacing: Self.historyGap) {
                Button(sidebarOpen ? .rootSidebarClose : .rootSidebarOpen, systemImage: "sidebar.leading") { sidebarOpen.toggle() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.toolbar)
                    .toolbarGroup()
                HistoryButtons(navigator: navigator) { workspace.title(of: $0) }
            }
            TabBar(
                tabs: tabs, workspace: workspace, crumbs: crumbs, toolbar: row, moveToWindow: moveToWindow,
                nameLayout: { namingLayout = $0 }, manageLayouts: manageLayouts)
            Spacer(minLength: 0)
            HStack(spacing: Theme.Space.s) {
                if let manual = StudyTracker.shared.manual {
                    // Out of the "…" while it runs: its time is what a timer is for, and stopping it is one press.
                    ManualTimerButton(courseID: manual.courseId)
                        .buttonStyle(.toolbar)
                        .toolbarGroup()
                }
                recordButton
                padTools
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { row.trailingWidth = $0 }
        }
        .padding(.leading, padLead)
        .padding(.trailing, TitleRowEdges.trailing)
        .frame(height: Theme.Size.toolbarRow)
        // A windowed iPad draws its window controls over the row's top-leading corner, where the sidebar button was.
        .onGeometryChange(for: CGFloat.self, of: { $0.containerCornerInsets.topLeading.width }) { windowControls = $0 }
        .onChange(of: padLead, initial: true) { _, lead in row.leadingX = lead }
        .onChange(of: windowWidth, initial: true) { _, width in row.windowWidth = width }
        .onChange(of: sidebarOpen, initial: true) { row.panelEdge = panelEdge }
    }

    var padLead: CGFloat { max(TitleRowEdges.lead(fullScreen: true), windowControls) }

    var padTools: some View {
        HStack(spacing: Theme.Space.xxs) {
            Button(.rootQuickAdd, systemImage: "plus") { quickAdding = true }
                .popover(isPresented: $quickAdding, arrowEdge: .bottom) {
                    QuickAddField(
                        workspace: workspace, defaultCourse: navigator.current.course, showsEmptyChips: true, focusOnAppear: true,
                        floating: true
                    )
                    .padding(Theme.Space.l)
                    .frame(width: 440)
                    .fixedSize(horizontal: false, vertical: true)
                }
            Menu {
                padMenu
            } label: {
                Label(.rootMore, systemImage: "ellipsis")
            }
        }
        .labelStyle(.iconOnly)
        .toolbarGroup()
        .buttonStyle(.toolbar)
        .menuStyle(.button)
    }

    @ViewBuilder var padMenu: some View {
        if !sidebarOpen {
            // The sidebar's search field is folded away with it.
            Button(.commonSearch, systemImage: "magnifyingglass") { searching = true }
            Divider()
        }
        if StudyTracker.shared.manual == nil, case .course(let id) = selection {
            Button(.timerStart, systemImage: "timer") { StudyTracker.shared.startManual(id, workspace: workspace) }
        }
        if let panes = tabs.front {
            LayoutMenu(choices: workspace.layoutChoices(for: panes, save: { namingLayout = panes }, manage: manageLayouts))
        }
        Divider()
        Button(
            workspace.gradesUnlocked ? .rootLockGrades : .commonUnlockGrades, systemImage: workspace.gradesUnlocked ? "lock.open" : "lock"
        ) {
            if workspace.gradesUnlocked { workspace.lockGrades() } else { Task { await workspace.unlockGrades() } }
        }
        Button(.rootReload, systemImage: "arrow.clockwise") { workspace.reload() }
    }

    /// The sidebar's top, where the iPad's search is (as in Mail and Notes): the same palette as ⌘K.
    var sidebarSearch: some View {
        Button {
            searching = true
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "magnifyingglass")
                Text(.commonSearch)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.Palette.chromeText)
            .padding(.horizontal, Theme.Space.m)
            .frame(height: Theme.Size.toolbarButton)
            .background(Theme.Palette.text.opacity(Theme.Opacity.wash), in: .rect(cornerRadius: Theme.Radius.control))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(.commonSearch))
        .padding(.horizontal, Theme.Space.s)
        .padding(.bottom, Theme.Space.s)
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
        let tab: PhoneTab? =
            if kind == .today { .today } else if kind == .grades || kind == .requirements { .grades } else {
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
            QuickAddField(
                workspace: workspace, defaultCourse: navigator.current.course, showsEmptyChips: true, focusOnAppear: true, floating: true
            )
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
            PaneRow(
                workspace: workspace, panes: panes, front: id == tabs.selected && !phoneSearching, openLink: openLink(from:),
                play: { [tabs] pane, pause in tabs.play(id, pane: pane, pause: pause) }
            )
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
                Picker(
                    selection: Binding {
                        navigator.screen == .requirements ? Screen.requirements : Screen.grades
                    } set: {
                        open($0 == .requirements ? .place(.requirements) : .place(.grades))
                    }
                ) {
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
            Button {
                quickAdding = true
            } label: {
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
/// Where the toolbar row's items begin and end across the window (`ToolbarRow`): the row's margins, as on the Mac
/// in full screen. A windowed iPad's controls push the lead further (`RootView.padLead`).
enum TitleRowEdges {
    static func lead(fullScreen: Bool) -> CGFloat { Theme.Space.l }
    static let trailing = Theme.Space.l
}
#endif
