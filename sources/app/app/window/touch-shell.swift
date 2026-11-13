#if os(iOS)
import FolioDomain
import SwiftUI

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
            // `simctl openurl`은 시스템 요청에서 멈추므로, 창 스냅숏에서는 `FOLIO_OPEN`의 링크를 차례로 연다.
            let env = ProcessInfo.processInfo.environment
            try? await Task.sleep(for: .seconds(1))
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

    // NavigationSplitView를 쓰지 않는다. 화면들에는 NavigationStack이 없어 그 toolbar를 채우지 못했고, 창에 검색, 탭, 도구가
    // 보이지 않았다.
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
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .background(Theme.Palette.frame.ignoresSafeArea())
        .animation(Theme.Motion.standard, value: sidebarOpen)
    }

    var padRow: some View {
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

    func ensurePhoneTabs() {
        guard tabs.count < 3 else { return }
        let front = tabs.selected
        let roots: [AppLink] = [phoneCoursesRoot, .place(.grades)]
        for link in roots.suffix(3 - tabs.count) {
            tabs.open(Navigator(workspace.entry(for: link) ?? Navigator.Entry(link: link)))
        }
        tabs.select(front)
    }

    var phoneCoursesRoot: AppLink {
        workspace.currentSemester.map { AppLink(.semester, $0.id) } ?? .place(.people)
    }

    func phoneRoute(_ entry: Navigator.Entry) -> Navigator? {
        guard sizeClass == .compact else { return nil }
        ensurePhoneTabs()
        let kind = entry.link.kind
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
        SearchPalette(workspace: workspace, close: { phoneSelection.wrappedValue = .today }) { link, course in
            open(link, course: course)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.top, Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.page)
    }

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
enum TitleRowEdges {
    static func lead(fullScreen: Bool) -> CGFloat { Theme.Space.l }
    static let trailing = Theme.Space.l
}
#endif
