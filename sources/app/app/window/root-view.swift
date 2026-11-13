import FolioDomain
import SwiftUI

struct RootView: View {
    @Environment(Workspace.self) var workspace
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @Environment(\.supportsMultipleWindows) private var multipleWindows
    @Environment(\.paneMemory) private var paneMemory
    @State var tabs: WindowTabs
    let request: WindowRequest?
    @State private var addingSemester = false
    @State private var addingCourse = false
    @State private var toggledTerms: Set<UUID> = []
    @State private var hoveredTerm: UUID?
    @State private var navHeight: CGFloat?
    @State var searching = false
    @AppStorage("sidebarOpen") var sidebarOpen = true
    @State var showingRecording = false
    @State var quickAdding = false
    @State var namingLayout: TabPanes?
    @State var row = ToolbarRow()
    #if os(iOS)
    @State var windowControls: CGFloat = 0
    #endif
    @State private var inputGuide: InputGuideRequest?
    @State private var contentHeight: CGFloat?
    @Environment(\.colorScheme) private var colorScheme
    #if os(macOS)
    @State private var madeAt = Date.now
    @State private var host = WindowHost()
    @State private var fullScreen = false
    #else
    @State var windowWidth: CGFloat = 1200
    @Environment(\.horizontalSizeClass) var sizeClass
    @State var phoneSearching = false
    #endif

    init(request: WindowRequest? = nil) {
        self.request = request
        if let request, let histories = request.panes,
            let panes = TabPanes(histories: histories, shares: request.shares, focus: request.focus ?? 0, columns: request.columns)
        {
            _tabs = State(initialValue: WindowTabs(panes))
            return
        }
        let navigator =
            if let history = request?.history {
                Navigator(history: history)
            } else {
                Navigator(request.map { Navigator.Entry(link: $0.link, course: $0.course) } ?? Navigator.Entry(link: .place(.today)))
            }
        _tabs = State(initialValue: WindowTabs(TabPanes(navigator, columns: ColumnMemory.shared.pane(request?.columns?.first))))
    }

    var navigator: Navigator { tabs.current }

    var selection: Screen? { navigator.screen }

    var selectionBinding: Binding<Screen?> {
        Binding {
            navigator.screen
        } set: { new in
            if let new, new != navigator.screen, let link = new.link { open(link) }
        }
    }

    func open(_ link: AppLink, in placement: LinkPlacement = .here, course hint: UUID? = nil, from pane: Navigator? = nil) {
        guard let entry = workspace.entry(for: link, hint: hint) else {
            workspace.error = String(localized: .linkNotFound(link.string))
            return
        }
        #if os(iOS)
        let pane = (placement == .here ? phoneRoute(entry) : nil) ?? pane ?? navigator
        #else
        let pane = pane ?? navigator
        #endif
        switch placement {
        case .here:
            if pane.current.link.withoutAnchor != entry.link.withoutAnchor, let tab = tabs.panes(holding: pane),
                restoresSession(entry, in: tab)
            {
                return
            }
            pane.go(entry)
        case .beside:
            (tabs.panes(holding: pane) ?? tabs.front)?.openBeside(entry, from: pane)
        case .tab:
            #if os(iOS)
            guard sizeClass == .regular else { return openInWindow(entry, else: pane) }
            #endif
            let tab = TabPanes(Navigator(entry))
            restoresSession(entry, in: tab)
            tabs.open(tab, fromLink: true)
        case .window:
            openInWindow(entry, else: pane)
        }
    }

    func manageLayouts() { open(.settings(.general)) }

    @discardableResult
    func restoresSession(_ entry: Navigator.Entry, in tab: TabPanes) -> Bool {
        guard tab.count == 1, let paneMemory, let file = entry.course.flatMap({ workspace.course($0) })?.file,
            let session = file.session(holding: entry.link),
            let saved = paneMemory.memory.restoring(entry.link, session: session)
        else { return false }
        let entries = saved.panes.indices.map { i in
            i == saved.focus ? entry : workspace.entry(for: saved.panes[i].link, hint: entry.course)
        }
        return tab.restore(saved, entries: entries)
    }

    func openTab(_ layout: PaneLayout, course hint: UUID?) {
        let found = layout.panes.indices.compactMap { i in workspace.entry(for: layout.panes[i].link, hint: hint).map { (i, $0) } }
        guard !found.isEmpty else { return }
        #if os(iOS)
        if sizeClass == .regular { return openTabHere(layout, found: found) }
        #endif
        #if os(macOS)
        openTabHere(layout, found: found)
        #else
        let histories = found.map { LinkHistory($0.1) }
        let shares = found.map { layout.panes[$0.0].share }
        let focus = found.firstIndex { $0.0 == layout.focus } ?? 0
        if multipleWindows {
            let focused = found[focus].1
            var request = WindowRequest(link: focused.link, course: focused.course)
            request.panes = histories
            request.shares = shares
            request.focus = focus
            openWindow(id: FolioApp.mainWindow, value: request)
        } else {
            navigator.go(found[0].1)
            for (_, entry) in found.dropFirst() { tabs.front?.openBeside(entry) }
        }
        #endif
    }

    func openTabHere(_ layout: PaneLayout, found: [(Int, Navigator.Entry)]) {
        if let kept = layout.keeping({ i in found.contains { $0.0 == i } }),
            let panes = TabPanes(layout: kept, entries: found.map(\.1))
        {
            tabs.open(panes, fromLink: true)
        }
    }

    func openInWindow(_ entry: Navigator.Entry, else pane: Navigator) {
        guard multipleWindows else { return pane.go(entry) }
        openWindow(id: FolioApp.mainWindow, value: WindowRequest(link: entry.link, course: entry.course))
    }

    var openLink: OpenLinkAction { openLink(from: navigator) }

    // 앞 탭 뒤에 살아 있는 화면이나 초점 칸 옆의 화면도 자기 칸을 움직여야 하므로 칸마다 따로 만든다.
    func openLink(from pane: Navigator) -> OpenLinkAction {
        OpenLinkAction { link, placement, course in open(link, in: placement, course: course, from: pane) }
    }

    func moveToWindow(_ id: UUID) {
        guard let moved = tabs.take(id) else { return }
        let focused = moved.focused
        var request = WindowRequest(link: focused.current.link, course: focused.current.course, history: focused.history)
        if moved.count > 1 {
            request.panes = moved.navigators.map(\.history)
            request.shares = moved.shares
            request.focus = moved.focus
        }
        request.columns = moved.columns.map(\.names)
        openWindow(id: FolioApp.mainWindow, value: request)
    }

    func openFromOutside(_ link: AppLink) {
        #if os(macOS)
        open(link, in: navigator.outsidePlacement(windowAge: Date.now.timeIntervalSince(madeAt)))
        NSApp.activate()
        host.window?.makeKeyAndOrderFront(nil)
        #else
        open(link)
        #endif
    }

    func bringForward() {
        #if os(macOS)
        NSApp.activate()
        host.window?.makeKeyAndOrderFront(nil)
        #endif
    }

    var body: some View {
        Group {
            if workspace.isInFirstRun {
                FirstRunView(workspace: workspace)
            } else {
                shell {
                    detail
                        .controlSize(.large)
                        .environment(\.showSettings) { showSettings($0) }
                        .environment(\.showInputGuide) { showInputGuide($0) }
                        .background {
                            Button(.commonSearch) { searching = true }.keyboardShortcut("k").opacity(0).accessibilityHidden(true)
                        }
                }
                .environment(\.openLink, openLink)
                .environment(\.sheetRoom, contentHeight)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height - $0.safeAreaInsets.top - $0.safeAreaInsets.bottom
                } action: {
                    contentHeight = $0
                }
                .classStartPrompt(
                    workspace, open: { open($0.link, in: $0.placement) }, openSplit: { openTab($0, course: $1) },
                    showing: { navigator.current }, bringForward: bringForward
                )
                .whatsNewPrompt(workspace) { open($0) }
                #if os(iOS)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { windowWidth = $0 }
                #endif
                .controlSize(.regular)
                .overlay {
                    if searching {
                        // overlay의 내용은 기본으로 가운데에 놓여 팔레트가 창 중간에 뜨므로, 위로 정렬한 stack을 직접 둔다.
                        ZStack(alignment: .top) {
                            Theme.Palette.scrim.ignoresSafeArea().onTapGesture { searching = false }
                            SearchPalette(workspace: workspace, close: { searching = false }) { link, course in
                                open(link, course: course)
                            }
                            .padding(.top, 90)
                        }
                    }
                }
                .animation(Theme.Motion.standard, value: workspace.recorder.isActive)
                .itemSheets(workspace, openLink: openLink)
                #if os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    workspace.recorder.stopNow()
                }
                #endif
                .focusedSceneValue(\.showSettings) { showSettings($0) }
                .focusedSceneValue(\.showInputGuide) { showInputGuide($0) }
                .focusedSceneValue(\.openPlace) { open($0) }
                .sheet(item: $inputGuide) { InputGuideSheet(workspace: workspace, syntax: $0.syntax) }
                .focusedSceneValue(\.navigator, navigator)
                .focusedSceneValue(\.columnCommand, tabs.trail(tabs.selected)?.column)
                .focusedSceneValue(\.outlineCommand, tabs.trail(tabs.selected)?.outline)
                .focusedSceneValue(\.frontPanes, tabs.front)
                .focusedSceneValue(
                    \.layoutChoices,
                    tabs.front.map { panes in
                        workspace.layoutChoices(for: panes, save: { namingLayout = panes }, manage: manageLayouts)
                    }
                )
                .modifier(LayoutNaming(workspace: workspace, panes: $namingLayout))
                .onAppear { MemoryPressure.start() }
                .onReceive(MemoryPressure.publisher) { _ in tabs.dropBackground() }
                .onChange(of: workspace.liveNow) { tabs.tick() }
                #if os(macOS)
                .focusedSceneValue(\.windowTabs, tabs)
                .onChange(of: tabs.selected) { host.window?.makeFirstResponder(nil) }
                .background { SwipeNavigation(back: { navigator.back() }, forward: { navigator.forward() }) }
                .background {
                    WindowReader { window in
                        host.window = window
                        tabs.closeWindow = { [weak window] in window?.performClose(nil) }
                    }
                }
                .background { WindowWidth { row.windowWidth = $0 } }
                .onChange(of: sidebarOpen, initial: true) { row.panelEdge = panelEdge }
                #endif
                #if DEBUG && os(macOS)
                .onChange(of: SnapshotDriver.shared.searchQuery) { _, query in searching = query != nil }
                .onChange(of: SnapshotDriver.shared.quickAddOpen) { _, open in quickAdding = open }
                #endif
            }
        }
        .onOpenURL { url in if let link = AppLink(url: url) { openFromOutside(link) } }
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        #if os(macOS) && (DEBUG || RESIZE_PROBE)
        .task {
            await ResizeProbe.run(
                window: { host.window }, workspace: workspace,
                openTab: { link, course in tabs.open(Navigator(Navigator.Entry(link: link, course: course))) },
                front: { tabs.select(number: $0) },
                openBeside: { link, course in tabs.front?.openBeside(Navigator.Entry(link: link, course: course)) },
                frontPanes: { tabs.front })
        }
        #endif
        #if DEBUG
        .task { await PaneBundleProbe.run(tabs: tabs, workspace: workspace) }
        #endif
        #if DEBUG && os(macOS)
        .task {
            await TabMemoryProbe.run(tabs: tabs, workspace: workspace)
            await PaneSessionProbe.run(tabs: tabs, workspace: workspace, memory: paneMemory) { open($0, in: .tab) }
            if SnapshotDriver.directory != nil { workspace.gradesUnlocked = true }
            if SnapshotDriver.recording, let course = workspace.currentCourses.first, let session = course.file.sessions.first {
                let recording = Recording(device: workspace.device, at: .now, sessionId: session.id, file: "")
                workspace.recorder.stage(
                    recording, course: course.id,
                    title: "\(course.title) · \(course.file.title(of: session, calendar: workspace.calendar))",
                    paused: SnapshotDriver.recordingPaused, level: SnapshotDriver.recordingLevel)
            }
            if LayoutSnapshots.mode != nil { return await LayoutSnapshots.run(tabs: tabs, workspace: workspace) }
            let ids = workspace.currentCourses.map(\.id)
            if SnapshotDriver.strip != nil,
                let lecture = workspace.currentCourses.lazy.compactMap({ c in
                    c.file.lectureFiles.first { m in
                        c.file.sessions.contains { $0.materials.contains { $0.materialId == m.id && $0.pages != nil } }
                    }
                }).first ?? workspace.currentCourses.lazy.compactMap({ $0.file.lectureFiles.first }).first
            {
                if let now = SnapshotDriver.stripNow { workspace.pinnedNow = now }
                await SnapshotDriver.shared.runStrip(open: { open($0) }, lecture: AppLink(.material, lecture.id))
                return
            }
            if SnapshotDriver.quickAdd, let course = workspace.currentCourses.first {
                await SnapshotDriver.shared.runQuickAdd(
                    open: { open($0) }, course: course.id, other: workspace.currentCourses.dropFirst().first?.id,
                    named: String(course.title.split(separator: " ").first ?? ""))
                return
            }
            if SnapshotDriver.math, let note = workspace.currentCourses.lazy.compactMap({ $0.file.notes.first }).first {
                await SnapshotDriver.shared.runMath(open: { open($0) }, note: AppLink(.note, note.id))
                return
            }
            if SnapshotDriver.split != nil,
                let lecture = workspace.currentCourses.lazy.compactMap({ c in
                    c.file.lectureFiles.first { c.file.isSplit($0.id) }
                }).first
            {
                await SnapshotDriver.shared.runSplit(open: { open($0) }, lecture: AppLink(.material, lecture.id)) {
                    workspace.splitAsk = lecture.id
                }
                return
            }
            if SnapshotDriver.tabs > 1 {
                let notes = workspace.currentCourses.compactMap { c in c.file.notes.first.map { AppLink(.note, $0.id) } }
                let links: [AppLink] =
                    [.place(.grades)] + notes + ids.map { AppLink.course($0) } + [.place(.people), .place(.settings), .place(.today)]
                for i in 1..<SnapshotDriver.tabs {
                    let link = links[(i - 1) % links.count]
                    tabs.open(Navigator(workspace.entry(for: link) ?? Navigator.Entry(link: .place(.today))))
                }
                tabs.select(number: 1)
            }
            if SnapshotDriver.panes > 1, let course = workspace.currentCourses.first {
                let pdfs = course.file.materials.filter { $0.path.lowercased().hasSuffix(".pdf") }
                let paged = pdfs.first { m in
                    course.file.sessions.contains { $0.materials.contains { $0.materialId == m.id && $0.pages != nil } }
                }
                let lecture = (paged ?? pdfs.first).map { AppLink(.material, $0.id) }
                let besides = [lecture, AppLink.course(course.id, page: .quiz)].compactMap { $0 }.prefix(SnapshotDriver.panes - 1)
                for tab in tabs.ids.prefix(2) {
                    for link in besides { if let entry = workspace.entry(for: link) { tabs.panes(tab)?.openBeside(entry) } }
                }
            }
            if SnapshotDriver.coursePanes, workspace.currentCourses.count > 1, let tab = tabs.ids.first,
                let entry = workspace.entry(for: .course(workspace.currentCourses[1].id))
            {
                tabs.panes(tab)?.openBeside(entry)
                tabs.panes(tab)?.press(0)
            }
            let exam = workspace.currentCourses.first?.file.exams.min { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
            let replay = workspace.currentCourses.lazy.compactMap { $0.file.recordings.first }.first
            let links =
                (exam.map { [("link-exam", AppLink(.exam, $0.id))] } ?? [])
                + (replay.map { [("link-recording", AppLink(.recording, $0.id, anchor: .time(1700)))] } ?? [])
                + (workspace.catalog.people.first.map { [("link-person", AppLink(.person, $0.id))] } ?? [])
            await SnapshotDriver.shared.run(
                select: { if let link = $0.link { open(link) } }, open: { open($0) }, courses: ids,
                semester: workspace.currentSemester?.id, links: links)
        }
        #endif
        .environment(\.gradesLocked, !workspace.gradesUnlocked)
        .environment(\.unlockGrades) { Task { await workspace.unlockGrades() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { workspace.lockGrades() }
            if phase == .active { workspace.reload() }
        }
        .alert(Text(.rootErrorTitle), isPresented: .constant(workspace.error != nil)) {
            Button(.commonOk) { workspace.error = nil }
        } message: {
            Text(workspace.error ?? "")
        }
    }

    var listSelection: Binding<Screen?> { .constant(nil) }

    var sidebar: some View {
        LiveTime(workspace) { now in
            VStack(spacing: 0) {
                #if os(iOS)
                sidebarSearch
                #endif
                List(selection: listSelection) {
                    Label {
                        Text(.rootNavToday)
                    } icon: {
                        sidebarIcon("house", .today)
                    }.sidebarRow(.today, selectionBinding)
                    let waiting = workspace.lmsInbox.proposals.count
                    if waiting > 0 || selection == .proposals {
                        Label {
                            HStack {
                                Text(.rootNavProposals).lineLimit(1)
                                if waiting > 0 {
                                    Spacer(minLength: Theme.Space.xs)
                                    Text("\(waiting)").font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit()
                                        .foregroundStyle(Theme.Palette.chromeText).fixedSize()
                                }
                            }
                        } icon: {
                            sidebarIcon("tray", .proposals)
                        }.sidebarRow(.proposals, selectionBinding)
                    }
                    Label {
                        Text(.rootNavGrades)
                    } icon: {
                        sidebarIcon("chart.line.uptrend.xyaxis", .grades)
                    }.sidebarRow(.grades, selectionBinding)
                    Label {
                        Text(.rootNavRequirements)
                    } icon: {
                        sidebarIcon("flag", .requirements)
                    }.sidebarRow(.requirements, selectionBinding)
                    Label {
                        Text(.rootNavPeople)
                    } icon: {
                        sidebarIcon("person", .people)
                    }.sidebarRow(.people, selectionBinding)
                    Label {
                        Text(.rootNavCodes)
                    } icon: {
                        sidebarIcon("number", .codes)
                    }.sidebarRow(.codes, selectionBinding)
                    Label {
                        Text(.rootNavSettings)
                    } icon: {
                        sidebarIcon("gearshape", .settings)
                    }.sidebarRow(.settings, selectionBinding)
                }
                .scrollDisabled(true)
                .onScrollGeometryChange(for: CGFloat.self) {
                    $0.contentSize.height
                } action: { _, height in
                    navHeight = height
                }
                #if os(iOS)
                .frame(height: max(navHeight ?? 0, Theme.Size.sidebarRow * 6 + Theme.Space.s))
                #else
                .frame(height: navHeight)
                #endif
                .focusable(false)
                List(selection: listSelection) {
                    Section {
                        let summary = TodaySummary.build(
                            courses: workspace.currentCourses.map(\.file), now: now, settings: workspace.settings,
                            calendar: workspace.calendar)
                        ForEach(sidebarSemesters, id: \.id) { semester in
                            let courses = workspace.sidebarCourses(in: semester)
                            let current = semester.id == workspace.currentSemester?.id
                            let open = !courses.isEmpty && current != toggledTerms.contains(semester.id)
                            semesterRow(
                                semester, open: open,
                                menu: semesterMenu(semester, current: current, hasCourses: !courses.isEmpty, open: open)
                            )
                            .rowTools(
                                add: current ? String(localized: .rootAddCourse) : nil, action: { addingCourse = true },
                                open: courses.isEmpty ? nil : openBinding(semester, current: current)
                            ) { over in
                                if over { hoveredTerm = semester.id } else if hoveredTerm == semester.id { hoveredTerm = nil }
                            }
                            if open {
                                ForEach(courses) {
                                    courseRow(
                                        $0, last: $0.id == courses.last?.id, now: now,
                                        hint: current ? summary.hint(for: $0.id, now: now) : nil)
                                }
                                .onMove { workspace.moveSidebarCourses(in: semester, from: $0, to: $1) }
                            }
                        }
                    } header: {
                        Text(.rootSemesters).foregroundStyle(Theme.Palette.chromeText).frame(maxWidth: .infinity, alignment: .leading)
                            .rowTools(add: String(localized: .rootAddSemester)) { addingSemester = true }
                            .padding(.leading, Theme.Space.xs)
                    }
                }
                .overflowFade(.vertical)
                .focusable(false)
                if workspace.recorder.isActive {
                    RecordingBar(workspace: workspace) { open($0) }
                        .padding([.horizontal, .bottom], Theme.Space.m)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            #if os(macOS)
            .listStyle(.sidebar)
            #else
            .listStyle(.plain)
            .listRowSeparator(.hidden)
            .font(Theme.Typeface.sidebar)
            .environment(\.defaultMinListRowHeight, Theme.Size.sidebarRow)
            #endif
            .labelStyle(SidebarLabelStyle())
        }
        .sheet(isPresented: $addingSemester) {
            AddSemesterSheet(workspace: workspace) { id in
                guard let id else { return }
                open(AppLink(.semester, id))
            }
        }
        // Section에 붙인 sheet는 모든 행에 복사되고, 복사본이 모두 같은 flag에 묶여 하나를 닫으면 다음 것이 다시 떴다. 그래서
        // List 밖에 둔다.
        .sheet(isPresented: $addingCourse) {
            if let current = workspace.currentSemester {
                AddCourseSheet(workspace: workspace, semester: current) { if let id = $0 { open(.course(id)) } }
            }
        }
    }

    @ViewBuilder func shell(@ViewBuilder content: () -> some View) -> some View {
        #if os(macOS)
        VStack(spacing: 0) {
            titleRow
            HStack(spacing: 0) {
                if sidebarOpen {
                    sidebar
                        .scrollContentBackground(.hidden)
                        .focusable(false)
                        .frame(width: Theme.Size.sidebar)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                content()
                    .padding([.trailing, .bottom], Theme.Size.panelInset)
                    .padding(.leading, sidebarOpen ? 0 : Theme.Size.panelInset)
            }
        }
        // 이 줄이 창의 맨 위다. 숨긴 title bar의 safe area를 따르면 줄이 창 버튼 아래로 밀려난다.
        .ignoresSafeArea(.container, edges: .top)
        .background { TrafficLights(center: TitleRowEdges.lights) { fullScreen = $0 } }
        .background(Theme.Palette.frameTint.ignoresSafeArea())
        .containerBackground(colorScheme == .light ? .thinMaterial : .regularMaterial, for: .window)
        .animation(Theme.Motion.standard, value: sidebarOpen)
        #else
        touchShell(content: content)
        #endif
    }

    #if os(macOS)
    var titleRow: some View {
        let lead = TitleRowEdges.lead(fullScreen: fullScreen)
        return TitleRow(lead: lead) {
            HStack(spacing: Self.historyGap) {
                sidebarButton
                    #if DEBUG || RESIZE_PROBE
                .background { ResizeMarker(name: "sidebar") }
                    #endif
                HistoryButtons(navigator: navigator) { workspace.title(of: $0) }
                    #if DEBUG || RESIZE_PROBE
                .background { ResizeMarker(name: "back") }
                    #endif
            }
            TabBar(
                tabs: tabs, workspace: workspace, crumbs: crumbs, toolbar: row, moveToWindow: moveToWindow,
                nameLayout: { namingLayout = $0 }, manageLayouts: manageLayouts)
        } trailing: {
            HStack(spacing: Theme.Space.s) {
                searchButton
                recordButton
                tools
            }
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { row.trailingWidth = $0 }
            #if DEBUG || RESIZE_PROBE
            .background { ResizeMarker(name: "trailing") }
            #endif
        }
        .onChange(of: lead, initial: true) { _, lead in row.leadingX = lead }
    }
    #endif

    #if os(macOS)
    var sidebarButton: some View {
        Button(sidebarOpen ? .rootSidebarClose : .rootSidebarOpen, systemImage: "sidebar.leading") { sidebarOpen.toggle() }
            .keyboardShortcut("s", modifiers: [.control, .command])
            .help(Text(sidebarOpen ? .rootSidebarCloseHelp : .rootSidebarOpenHelp))
            .buttonStyle(.toolbar)
            .toolbarGroup()
    }
    #endif

    var searchButton: some View {
        Button {
            searching = true
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "magnifyingglass")
                Text(.commonSearch)
            }
            .foregroundStyle(Theme.Palette.chromeText)
            .frame(width: Theme.Size.searchField - Theme.Space.m * 2, alignment: .leading)
            .overlay(alignment: .trailing) {
                Text("⌘K").font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.chromeText)
            }
            .toolbarField()
            .contentShape(.capsule)
        }
        .buttonStyle(.pointing(.plain))
        .help(Text(.rootSearchHelp))
    }

    var tools: some View {
        HStack(spacing: Theme.Space.xxs) {
            Button(.rootQuickAdd, systemImage: "plus") { quickAdding = true }
                .help(Text(.rootQuickAddHelp))
                .popover(isPresented: $quickAdding, arrowEdge: .bottom) {
                    QuickAddField(
                        workspace: workspace, defaultCourse: navigator.current.course, showsEmptyChips: true, focusOnAppear: true,
                        floating: true
                    ).padding(Theme.Space.l).frame(width: 440)
                        .fixedSize(horizontal: false, vertical: true)
                }
            timerButton
            Button(
                workspace.gradesUnlocked ? .rootLockGrades : .commonUnlockGrades,
                systemImage: workspace.gradesUnlocked ? "lock.open" : "lock"
            ) {
                if workspace.gradesUnlocked { workspace.lockGrades() } else { Task { await workspace.unlockGrades() } }
            }
            .help(Text(workspace.gradesUnlocked ? .rootHideGrades : .rootShowGrades))
            Button(.rootReload, systemImage: "arrow.clockwise") { workspace.reload() }.help(Text(.rootReloadHelp))
        }
        .toolbarGroup()
        .buttonStyle(.toolbar)
        .menuStyle(.button)
    }

    var crumbs: [Crumb] {
        let steps = if case .course = selection { tabs.trail(tabs.selected)?.crumbs ?? [] } else { [Crumb]() }
        return [workspace.placeCrumb(of: navigator.current)] + steps
    }

    var panelEdge: CGFloat { sidebarOpen ? Theme.Size.sidebar : Theme.Size.panelInset }

    static let historyGap = Theme.Space.s
    static let recordingTimeWidth: CGFloat = 96

    @ViewBuilder var recordButton: some View {
        #if os(macOS)
        RecordingCapsule(workspace: workspace, expanded: workspace.recorder.isActive && !sidebarOpen) { recordMenu }
        #else
        RecordingCapsule(workspace: workspace, expanded: workspace.recorder.isActive, openCard: { showingRecording = true }) { recordMenu }
            .popover(isPresented: $showingRecording, arrowEdge: .bottom) {
                RecordingBar(workspace: workspace) { link in
                    showingRecording = false
                    open(link)
                }
                .frame(width: Theme.Size.sidebar)
                .padding(Theme.Space.m)
            }
            // popover에서 멈추면 capsule이 마이크로 바뀌면서 popover를 닫지만 false를 다시 쓰지 않는다. true로 두면 다음 녹음에서
            // popover가 저절로 열린다.
            .onChange(of: workspace.recorder.isActive) { _, active in if !active { showingRecording = false } }
        #endif
    }

    var recordMenu: some View {
        LiveTime(workspace) { now in
            let ongoing = workspace.ongoingClass(at: now)
            Button {
                if let ongoing { workspace.record(ongoing.session.id, in: ongoing.courseId) }
            } label: {
                Label(.rootRecord, systemImage: "mic")
            }
            .disabled(ongoing == nil || workspace.recorder.isActive)
            .help(
                workspace.recorder.isActive
                    ? String(localized: .rootRecording)
                    : ongoing.flatMap { o in
                        workspace.course(o.courseId).map {
                            String(
                                localized: .rootRecordSession(
                                    $0.title, $0.file.subject(of: o.session) ?? $0.file.day(of: o.session, calendar: workspace.calendar)))
                        }
                    }
                        ?? String(localized: .rootRecordUnavailable))
        }
    }

    @ViewBuilder var timerButton: some View {
        if let manual = StudyTracker.shared.manual {
            ManualTimerButton(courseID: manual.courseId)
        } else if case .course(let id) = selection {
            ManualTimerButton(courseID: id)
        }
    }

    // 목록 밖에서 만든다. 목록 안에 closure를 넣으면 사이드바의 식이 너무 커서 iPad 빌드가 type check를 끝내지 못했다.
    func semesterMenu(_ semester: Semester, current: Bool, hasCourses: Bool, open: Bool) -> SemesterMenu {
        var add: (@MainActor () -> Void)?
        if current { add = { addingCourse = true } }
        let fold: @MainActor () -> Void = { openBinding(semester, current: current).wrappedValue.toggle() }
        return SemesterMenu(semesterId: semester.id, host: .list, addCourse: add, folded: hasCourses ? !open : nil, fold: fold)
    }

    func semesterRow(_ semester: Semester, open: Bool, menu: SemesterMenu) -> some View {
        let chosen = selection == .semester(semester.id)
        let past = semester.term == .credited || workspace.currentSemester.map { semester.order < $0.order } ?? false
        return Label {
            Text(semester.title).lineLimit(1)
        } icon: {
            Group {
                if semester.term == .credited {
                    LineIcon(symbol: "checkmark.seal", filled: chosen, duotone: true)
                } else {
                    FolderIcon(open: open || hoveredTerm == semester.id, filled: chosen, duotone: true)
                }
            }
            .foregroundStyle(chosen ? Theme.Palette.chromeSelected : Theme.Palette.chromeIcon)
        }
        .opacity(past && !chosen ? Theme.Opacity.ended : 1)
        .sidebarRow(.semester(semester.id), selectionBinding, guide: .stem, guideShown: open, menu: AnyView(menu))
    }

    func sidebarIcon(_ symbol: String, _ destination: Screen) -> some View {
        LineIcon(symbol: symbol, filled: selection == destination, duotone: true)
            .foregroundStyle(selection == destination ? Theme.Palette.chromeSelected : Theme.Palette.chromeIcon)
    }

    var sidebarSemesters: [Semester] {
        workspace.transcript.semesters.filter { $0.term == .credited } + workspace.semesters.reversed()
    }

    func openBinding(_ semester: Semester, current: Bool) -> Binding<Bool> {
        Binding {
            current != toggledTerms.contains(semester.id)
        } set: { _ in
            withAnimation(Theme.Motion.quick) {
                // 포인터 아래에서 닫으면 포인터가 떠날 때가 아니라 바로 접는다. animation 안에서 지워야 한다. 밖에서 지우면 animation
                // 없는 변경이 같은 갱신에 실려 과목이 움직임 없이 나타났다. 포인터가 온 뒤 첫 클릭만 값을 지우므로, 이후 클릭에는 계속
                // 움직임이 있다.
                hoveredTerm = nil
                if toggledTerms.remove(semester.id) == nil { toggledTerms.insert(semester.id) }
            }
        }
    }

    func courseRow(_ course: LoadedCourse, last: Bool, now: Date, hint: TodaySummary.CourseHint?) -> some View {
        let accent = workspace.accent(course.id)
        let ongoing = workspace.ongoingClass(at: now).flatMap { $0.courseId == course.id ? $0 : nil }
        let detail =
            (ongoing.map {
                String(
                    localized: .rootInClass(
                        course.file.subject(of: $0.session) ?? course.file.day(of: $0.session, calendar: workspace.calendar)))
            }
            ?? hint.map(hintHelp)).flatMap { $0.isEmpty ? nil : $0 }
        return Label {
            HStack {
                Text(course.title).lineLimit(1)
                if let ongoing {
                    Spacer(minLength: Theme.Space.xs)
                    Text(.rootMinutesLeft(Int(ongoing.end.timeIntervalSince(now) / 60) + 1)).font(Theme.Typeface.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(accent.ink).fixedSize()
                } else if let hint {
                    Spacer(minLength: Theme.Space.xs)
                    courseHint(hint)
                }
            }
        } icon: {
            CourseMark(icon: course.file.course.icon, color: accent.color, filled: selection == .course(course.id), duotone: true)
        }
        .help(detail ?? "")
        .padding(.leading, SidebarGuide.indent)
        .sidebarRow(
            .course(course.id), selectionBinding, fill: accent.tint, guide: last ? .lastCourse : .course,
            progress: ongoing?.fraction(at: now), note: detail,
            menu: AnyView(CourseMenu(courseId: course.id, host: .list)))
    }

    @ViewBuilder func courseHint(_ hint: TodaySummary.CourseHint) -> some View {
        Group {
            switch hint {
            case .dueToday: Image(systemName: "checklist").foregroundStyle(Theme.Palette.danger)
            case .nextClass(let date): Text(clock(date)).foregroundStyle(Theme.Palette.chromeText)
            case .exam(let days): Text(days == 0 ? "D-day" : "D-\(days)").foregroundStyle(Theme.Palette.warning)
            }
        }
        .font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit()
        .fixedSize()
    }

    func clock(_ date: Date) -> String { date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()) }

    func hintHelp(_ hint: TodaySummary.CourseHint) -> String {
        switch hint {
        case .dueToday(let a): String(localized: .rootDueTodayHelp(a.title, a.due?.formatted(date: .omitted, time: .shortened) ?? ""))
        case .nextClass(let date): String(localized: .rootNextClassHelp(date.formatted(date: .omitted, time: .shortened)))
        case .exam: ""
        }
    }

    var detail: some View { TabScreens(tabs: tabs, workspace: workspace, openLink: openLink(from:)) }

    func showSettings(_ tab: SettingsTab?) {
        open(.settings(tab?.page))
    }

    func showInputGuide(_ syntax: MathSyntax?) {
        inputGuide = inputGuide == nil ? InputGuideRequest(syntax: syntax ?? workspace.settings.newNoteMath) : nil
    }
}

extension Semester {
    var title: String {
        switch term {
        case .credited: source.map { String(localized: .semesterTitleCreditedSource($0)) } ?? String(localized: .semesterTitleCredited)
        case .spring: String(localized: .semesterTitleSpring(String(year)))
        case .summer: String(localized: .semesterTitleSummer(String(year)))
        case .fall: String(localized: .semesterTitleFall(String(year)))
        case .winter: String(localized: .semesterTitleWinter(String(year)))
        }
    }
}

private struct SidebarLabelStyle: LabelStyle {
    static let gap = Theme.Space.s

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Self.gap) {
            configuration.icon
            configuration.title
        }
    }
}

// 도구는 행 안이 아니라 위에 놓는다. 행은 버튼이고, 버튼의 label 안에 있는 버튼은 클릭을 받지 못한다. 터치에는 hover가
// 없으므로 iPad에서는 도구가 항상 보인다.
private struct RowTools: ViewModifier {
    let add: String?
    let action: () -> Void
    let open: Binding<Bool>?
    let folderHover: (Bool) -> Void
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                HStack(spacing: 0) {
                    if let add {
                        tool("plus", font: Theme.Glyph.regular, help: add, action: action)
                            #if os(macOS)
                        .opacity(hovering ? 1 : 0)
                        // 숨겨도 아래 행으로 갈 클릭을 받으므로 hover일 때만 hit test를 받는다.
                        .allowsHitTesting(hovering)
                            #endif
                    }
                }
                .padding(.trailing, Theme.Space.tight)
            }
            .overlay(alignment: .leading) {
                if let open {
                    Button {
                        open.wrappedValue.toggle()
                    } label: {
                        Color.clear.frame(width: Theme.Size.tile, height: Theme.Size.tile).contentShape(TouchTarget())
                    }
                    .buttonStyle(.pointing(.plain))
                    .help(Text(open.wrappedValue ? .commonCollapse : .commonExpand))
                    .accessibilityLabel(Text(open.wrappedValue ? .commonCollapse : .commonExpand))
                    .onHover(perform: folderHover)
                }
            }
            .onHover { hovering = $0 }
    }

    func tool(_ symbol: String, font: Font, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(font).frame(width: Theme.Size.tile, height: Theme.Size.tile).contentShape(TouchTarget())
        }
        .buttonStyle(.pointing(.plain))
        .foregroundStyle(Theme.Palette.chromeText)
        .help(help)
        .accessibilityLabel(help)
    }
}

enum SidebarGuide {
    case stem, course, lastCourse

    static let indent = Theme.Space.xl
    static var reach: CGFloat { indent - SidebarLabelStyle.gap - Theme.Size.tile / 2 }
}

private struct GuideSegment: Shape {
    var guide: SidebarGuide

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + 0.5
        let y = rect.midY
        let r = Theme.Space.xs
        path.move(to: CGPoint(x: x, y: rect.minY))
        switch guide {
        case .stem:
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        case .course, .lastCourse:
            path.addLine(to: CGPoint(x: x, y: guide == .course ? rect.maxY : y - r))
            path.move(to: CGPoint(x: x, y: y - r))
            path.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + SidebarGuide.reach, y: y))
        }
        return path
    }
}

private extension View {
    func rowTools(
        add: String? = nil, action: @escaping () -> Void = {}, open: Binding<Bool>? = nil, folderHover: @escaping (Bool) -> Void = { _ in }
    ) -> some View {
        modifier(RowTools(add: add, action: action, open: open, folderHover: folderHover))
    }

    @ViewBuilder func rowMenu(_ destination: Screen, note: String?, menu: AnyView?) -> some View {
        if let note {
            Text(note)
            Divider()
        }
        if let menu { menu } else if let link = destination.link { LinkMenu(link: link) }
    }

    // 각 행이 스스로 선택하고 채움을 그린다. Mac 사이드바의 선택은 tint와 상관없이 회색 하나라 고른 과목이 회색 덩어리가
    // 되었고, split view 밖의 iPad 목록에는 사이드바 선택이 없다. Mac에서는 guide를 행 간격까지 덮는 행 background에 그려
    // 선분이 겹치지 않고 이어진다(반투명 선은 겹친 곳이 진해진다). `guideShown`은 선을 빼지 않고 흐리게 한다. Mac 목록은 뷰가
    // 생기고 사라지는 행 background를 다시 그리지 않고 값이 바뀌는 것만 다시 그리며, 행을 새로 만들면 열 때 행이 튀었다.
    @ViewBuilder func sidebarRow(
        _ destination: Screen, _ selection: Binding<Screen?>, fill: Color = Theme.Palette.sidebarSelection, guide: SidebarGuide? = nil,
        guideShown: Bool = true, progress: Double? = nil, note: String? = nil, menu: AnyView? = nil
    ) -> some View {
        let line = guide.map { GuideSegment(guide: $0).stroke(Theme.Palette.chromeLine, lineWidth: 1).frame(width: SidebarGuide.reach + 1) }
        let chosen = selection.wrappedValue == destination
        // Button이 아니라 tap을 쓴다. 버튼은 누름을 붙잡아 목록의 순서 바꾸기 drag가 시작되지 않는다.
        frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .onTapGesture { selection.wrappedValue = destination }
            .listRowBackground(
                ZStack(alignment: .leading) {
                    let shape = RoundedRectangle(cornerRadius: Theme.Radius.control)
                    ZStack {
                        shape.fill(chosen ? fill : .clear)
                        if let progress {
                            Rectangle().fill(fill).scaleEffect(x: progress, anchor: .leading).clipShape(shape)
                        }
                    }
                    .padding(.horizontal, Theme.Space.s)
                    if let guide, let line {
                        line.frame(maxHeight: guide == .stem ? Theme.Space.tight : .infinity)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.leading, Theme.Space.l + Theme.Size.tile / 2)
                            .opacity(guideShown ? 1 : 0)
                    }
                }
            )
            #if os(iOS)
        .listRowInsets(EdgeInsets(top: 0, leading: Theme.Space.l, bottom: 0, trailing: Theme.Space.s))
        .listRowSeparator(.hidden)
            #endif
            .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { selection.wrappedValue = destination }
            .contextMenu { rowMenu(destination, note: note, menu: menu) }
    }
}
