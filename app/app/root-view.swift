import FolioDomain
import SwiftUI

enum Destination: Hashable {
    case today
    case course(UUID)
    case semester(UUID)
    case grades
    case requirements
    case people
    case codes
    case settings
}

struct RootView: View {
    @Environment(Workspace.self) private var workspace
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Destination? = .today
    @State private var pickingFolder = false
    @State private var addingSemester = false
    @State private var addingCourse = false
    /// Terms flipped from their default: the current term starts open, the others closed.
    @State private var toggledTerms: Set<UUID> = []
    /// The term whose folder is under the pointer: it opens, a hint that the folder opens and closes the term.
    @State private var hoveredTerm: UUID?
    /// The fixed list's own height, measured: the rows' height follows the system's sidebar size setting.
    @State private var navHeight: CGFloat?
    /// Whether the terms run on past the top and the bottom of their space, where the list fades out.
    @State private var searching = false
    @State private var searchTarget: SearchTarget?
    @State private var personTarget: UUID?
    @AppStorage(SettingsTab.storageKey) private var settingsTab: SettingsTab = .general
    @AppStorage("sidebarOpen") private var sidebarOpen = true
    @State private var quickAdding = false
    @State private var trail = CrumbTrail()
    @Environment(\.colorScheme) private var colorScheme
    @State private var windowWidth: CGFloat = 1200

    var body: some View {
        Group {
            if workspace.gist == nil {
                ContentUnavailableView {
                    Label(.rootPickGistTitle, systemImage: "folder")
                } description: {
                    Text(.rootPickGistDetail)
                } actions: {
                    Button(.rootPickFolder) { pickingFolder = true }
                }
            } else {
                shell {
                    detail
                        // Roomier buttons and segmented controls, as in Alcove; text sizes stay with the tokens.
                        .controlSize(.large)
                        .environment(\.searchTarget, $searchTarget)
                        // Any screen can jump into a course by setting the target, not only the search palette.
                        .onChange(of: searchTarget) { _, target in if let target { selection = .course(target.courseId) } }
                        .environment(\.personTarget, $personTarget)
                        .onChange(of: personTarget) { _, target in if target != nil { selection = .people } }
                        .environment(\.showSettings) { showSettings($0) }
                        .environment(trail)
                        // No toolbar band: columns (course, quiz scope, inspector) run to the window top, and a band over them
                        // reads as a header cutting across every column.
                        #if os(macOS)
                        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                        #endif
                        .background { Button(.commonSearch) { searching = true }.keyboardShortcut("k").opacity(0).accessibilityHidden(true) }
                }
                .toolbar { globalTools }
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { windowWidth = $0 }
                // A size up from the compact row's default: plain icons at its own size read too small.
                .controlSize(.regular)
                .overlay {
                    if searching {
                        // An explicit top-aligned stack: overlay content is centered otherwise, leaving the palette mid-window.
                        ZStack(alignment: .top) {
                            Theme.Palette.scrim.ignoresSafeArea().onTapGesture { searching = false }
                            SearchPalette(workspace: workspace, close: { searching = false }) { target in
                                selection = .course(target.courseId)
                                searchTarget = target
                            }
                            .padding(.top, 90)
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    if workspace.recorder.isActive {
                        RecordingBar(workspace: workspace)
                            .padding(.bottom, Theme.Space.xl)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.snappy(duration: 0.3), value: workspace.recorder.isActive)
                #if os(macOS)
                // Closing the file on quit keeps the audio playable; the transcript so far is already on disk.
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in workspace.recorder.stopNow() }
                #endif
                .focusedSceneValue(\.showSettings) { showSettings($0) }
                #if DEBUG && os(macOS)
                .onChange(of: SnapshotDriver.shared.searchQuery) { _, query in searching = query != nil }
                #endif
            }
        }
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { workspace.open(url) }
        }
        #if DEBUG && os(macOS)
        .task {
            // Snapshots are for checking layout; a Touch ID prompt would stall them on locked screens.
            if SnapshotDriver.directory != nil { workspace.gradesUnlocked = true }
            let ids = workspace.currentCourses.map(\.id)
            await SnapshotDriver.shared.run(select: { selection = $0 }, courses: ids, semester: workspace.currentSemester?.id)
        }
        #endif
        .environment(\.gradesLocked, !workspace.gradesUnlocked)
        .environment(\.unlockGrades) { Task { await workspace.unlockGrades() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { workspace.lockGrades() }
            // Coming back picks up what other devices or the CLI changed meanwhile.
            if phase == .active { workspace.reload() }
        }
        .alert(Text(.rootErrorTitle), isPresented: .constant(workspace.error != nil)) {
            Button(.commonOk) { workspace.error = nil }
        } message: {
            Text(workspace.error ?? "")
        }
    }

    /// The Mac's rows select themselves (see `sidebarRow`), so the list's own selection stays empty there.
    var listSelection: Binding<Destination?> {
        #if os(macOS)
        .constant(nil)
        #else
        $selection
        #endif
    }

    var sidebar: some View {
        // Ticks for the class under way: its row's fill and minutes. Around the list, not inside the row, so the row's
        // background (where the fill is drawn) is rebuilt with it.
        TimelineView(.periodic(from: .now, by: 30)) { context in
        // The places stay put and the terms scroll in the space under them, as the list of terms grows each term.
        VStack(spacing: 0) {
        List(selection: listSelection) {
            Label { Text(.rootNavToday) } icon: { sidebarIcon("house", .today) }.sidebarRow(.today, $selection)
            Label { Text(.rootNavGrades) } icon: { sidebarIcon("chart.line.uptrend.xyaxis", .grades) }.sidebarRow(.grades, $selection)
            Label { Text(.rootNavRequirements) } icon: { sidebarIcon("flag", .requirements) }.sidebarRow(.requirements, $selection)
            Label { Text(.rootNavPeople) } icon: { sidebarIcon("person", .people) }.sidebarRow(.people, $selection)
            Label { Text(.rootNavCodes) } icon: { sidebarIcon("number", .codes) }.sidebarRow(.codes, $selection)
            Label { Text(.rootNavSettings) } icon: { sidebarIcon("gearshape", .settings) }.sidebarRow(.settings, $selection)
        }
        .scrollDisabled(true)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, height in
            navHeight = height
        }
        .frame(height: navHeight)
        .focusable(false)
        List(selection: listSelection) {
            // The current term starts open, since its courses are what's opened daily.
            Section {
                // Built once per tick for every course row's hint, not once per row.
                let summary = TodaySummary.build(courses: workspace.currentCourses.map(\.file), now: context.date, settings: workspace.settings, calendar: workspace.calendar)
                ForEach(sidebarSemesters, id: \.id) { semester in
                    let courses = workspace.sidebarCourses(in: semester)
                    let current = semester.id == workspace.currentSemester?.id
                    let open = !courses.isEmpty && current != toggledTerms.contains(semester.id)
                    semesterRow(semester, open: open)
                        .rowTools(add: current ? String(localized: .rootAddCourse) : nil, action: { addingCourse = true }, open: courses.isEmpty ? nil : openBinding(semester, current: current)) { over in
                            if over { hoveredTerm = semester.id } else if hoveredTerm == semester.id { hoveredTerm = nil }
                        }
                    if open {
                        ForEach(courses) { courseRow($0, last: $0.id == courses.last?.id, now: context.date, hint: current ? summary.hint(for: $0.id, now: context.date) : nil) }
                            .onMove { workspace.moveSidebarCourses(in: semester, from: $0, to: $1) }
                    }
                }
            } header: {
                // Colored, not the list's own header gray, which faded into the dark frame; inset to start where the
                // rows' icons do.
                Text(.rootSemesters).foregroundStyle(Theme.Palette.chromeText).frame(maxWidth: .infinity, alignment: .leading)
                    .rowTools(add: String(localized: .rootAddSemester)) { addingSemester = true }
                    .padding(.leading, Theme.Space.xs)
            }
            .sheet(isPresented: $addingCourse) {
                if let current = workspace.currentSemester { AddCourseSheet(workspace: workspace, semester: current) { if let id = $0 { selection = .course(id) } } }
            }
        }
        .overflowFade(.vertical)
        .focusable(false)
        }
        .listStyle(.sidebar)
        .labelStyle(SidebarLabelStyle())
        }
        .sheet(isPresented: $addingSemester) {
            AddSemesterSheet(workspace: workspace) { id in
                guard let id else { return }
                selection = .semester(id)
            }
        }
    }

    /// On the Mac the window is a frame: toolbar row and sidebar sit flat on the window's material, and the content is a rounded
    /// panel inside it. Not a NavigationSplitView there, whose sidebar floats as its own glass panel over the window.
    /// The iPad keeps the split view, which also folds the sidebar into an overlay in compact widths.
    @ViewBuilder func shell(@ViewBuilder content: () -> some View) -> some View {
        #if os(macOS)
        // The toolbar's height is taken out as padding, not left as safe area: a column that runs up into the safe area
        // pulled the whole panel under the toolbar.
        let content = content()
        GeometryReader { window in
        HStack(spacing: 0) {
            if sidebarOpen {
                sidebar
                    .scrollContentBackground(.hidden)
                    // Outside a split view the list takes focus and paints its selection in the system accent.
                    .focusable(false)
                    .frame(width: Theme.Size.sidebar)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.floating)
            content
                .background(Theme.Palette.page, in: shape)
                .clipShape(shape)
                .overlay { shape.strokeBorder(Theme.Palette.lineSoft) }
                .padding([.trailing, .bottom], Theme.Size.panelInset)
                .padding(.leading, sidebarOpen ? 0 : Theme.Size.panelInset)
        }
        .padding(.top, window.safeAreaInsets.top)
        .ignoresSafeArea(.container, edges: .top)
        }
        .background(Theme.Palette.frameTint.ignoresSafeArea())
        // Thinner in light: the regular material whitened the frame into milk over a light wallpaper. Not ultra-thin:
        // with the wallpaper showing through that clearly, the sidebar's text lost its contrast.
        .containerBackground(colorScheme == .light ? .thinMaterial : .regularMaterial, for: .window)
        .animation(.snappy(duration: 0.25), value: sidebarOpen)
        #else
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 220, ideal: 250)
        } detail: {
            content().background(Theme.Palette.page)
        }
        #endif
    }

    /// Actions that work from any page, so they live in the window's toolbar rather than on one screen.
    @ToolbarContentBuilder var globalTools: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .navigation) {
            Button(sidebarOpen ? .rootSidebarClose : .rootSidebarOpen, systemImage: "sidebar.leading") { sidebarOpen.toggle() }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .help(Text(sidebarOpen ? .rootSidebarCloseHelp : .rootSidebarOpenHelp))
                .buttonStyle(.toolbar)
                .toolbarGroup()
        }
        .sharedBackgroundVisibility(.hidden)
        #endif
        // A course adds its section after this; pages add their own controls after that.
        ToolbarItem(placement: .navigation) { crumb }
            .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.flexible)
        // Between two flexible spacers: centered in the room the crumb and the buttons leave, as in the design. Not
        // `.principal`, which centers on the window and, pushed over the panel, crowded the buttons into overflow.
        ToolbarItem {
            Button { searching = true } label: {
                // No Spacer inside: a toolbar item with one has no fixed width, and the row drops it.
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
        .sharedBackgroundVisibility(.hidden)
        ToolbarSpacer(.flexible)
        // One item for all the buttons, laid out here: as separate items the system spaces them far apart.
        ToolbarItem {
            HStack(spacing: Theme.Space.xxs) {
                Button(.rootQuickAdd, systemImage: "plus") { quickAdding = true }
                    .help(Text(.rootQuickAddHelp))
                    .popover(isPresented: $quickAdding, arrowEdge: .bottom) {
                        QuickAddField(workspace: workspace).padding(Theme.Space.l).frame(width: 440)
                    }
                recordButton
                timerButton
                Button(workspace.gradesUnlocked ? .rootLockGrades : .commonUnlockGrades, systemImage: workspace.gradesUnlocked ? "lock.open" : "lock") {
                    if workspace.gradesUnlocked { workspace.lockGrades() } else { Task { await workspace.unlockGrades() } }
                }
                .help(Text(workspace.gradesUnlocked ? .rootHideGrades : .rootShowGrades))
                Button(.rootReload, systemImage: "arrow.clockwise") { workspace.reload() }.help(Text(.rootReloadHelp))
            }
            .toolbarGroup()
            .buttonStyle(.toolbar)
            .menuStyle(.button)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    var crumb: some View {
        let first: Crumb = switch selection {
        case .course(let id): Crumb(title: workspace.course(id)?.title ?? "", symbol: workspace.course(id)?.file.course.icon, dot: workspace.accent(id).color)
        case .semester(let id):
            { let semester = workspace.transcript.semesters.first { $0.id == id }
              return Crumb(title: semester?.title ?? "", symbol: semester?.term == .credited ? "checkmark.seal" : "folder") }()
        case .grades: Crumb(title: String(localized: .rootNavGrades), symbol: "chart.line.uptrend.xyaxis")
        case .requirements: Crumb(title: String(localized: .rootNavRequirements), symbol: "flag")
        case .people: Crumb(title: String(localized: .rootNavPeople), symbol: "person")
        case .codes: Crumb(title: String(localized: .rootNavCodes), symbol: "number")
        case .settings: Crumb(title: String(localized: .rootNavSettings), symbol: "gearshape")
        case .today, nil: Crumb(title: String(localized: .rootNavToday), symbol: "house")
        }
        let start = (sidebarOpen ? Theme.Size.sidebar : Theme.Size.panelInset) + Theme.Space.l
        // Folds before where a window-centered search field would begin, so the trail doesn't push it aside; truncates
        // only where the field and the buttons would run out of room.
        let room = windowWidth / 2 - Theme.Size.searchField / 2 - Theme.Space.l - start
        let limit = windowWidth - start - Theme.Size.searchField - Self.trailingTools
        // A course's section and what it opened only while the course is shown: they clear as it goes.
        let steps = if case .course = selection { trail.crumbs } else { [Crumb]() }
        let inset = Theme.Space.m * 2  // the capsule's own padding, left out of the trail's room
        return Breadcrumb(crumbs: [first] + steps, foldWidth: max(Self.crumbMinWidth, room - inset), maxWidth: max(Self.crumbMinWidth, limit - inset))
            .toolbarField()
            // From right after the sidebar button over to the panel's corner, folded or not.
            .padding(.leading, max(Theme.Space.s, start - Self.crumbStart))
    }

    /// Where the item after the sidebar button begins, from the window's left edge; measured in a window screenshot.
    static let crumbStart: CGFloat = 140
    /// Below this the trail folds anyway and its last step truncates.
    static let crumbMinWidth: CGFloat = 160
    /// The trailing buttons and the gaps around the search field, measured at their widest (a course, timer shown),
    /// less the Claude button that moved to the page.
    static let trailingTools: CGFloat = 288

    var recordButton: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let ongoing = workspace.ongoingClass(at: context.date)
            Menu {
                if let ongoing {
                    Button(.rootRecordKorean) { workspace.record(ongoing.session.id, in: ongoing.courseId, locale: Locale(identifier: "ko-KR")) }
                    Button(.rootRecordEnglish) { workspace.record(ongoing.session.id, in: ongoing.courseId, locale: Locale(identifier: "en-US")) }
                }
            } label: {
                Label(.rootRecord, systemImage: "mic")
            }
            .menuIndicator(.hidden)
            .disabled(ongoing == nil || workspace.recorder.isActive)
            .help(workspace.recorder.isActive ? String(localized: .rootRecording)
                  : ongoing.flatMap { o in workspace.course(o.courseId).map { String(localized: .rootRecordSession($0.title, $0.file.name(of: o.session))) } }
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

    func semesterRow(_ semester: Semester, open: Bool) -> some View {
        let chosen = selection == .semester(semester.id)
        // Terms already over step back, so the current and coming ones stand out in a list that grows every term.
        let past = semester.term == .credited || workspace.currentSemester.map { semester.order < $0.order } ?? false
        return Label {
            Text(semester.title)
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
        // On the label, under `sidebarRow`, so a chosen past term's row fill stays full strength.
        .opacity(past && !chosen ? Theme.Opacity.ended : 1)
        .sidebarRow(.semester(semester.id), $selection, guide: .stem, guideShown: open)
    }

    func sidebarIcon(_ symbol: String, _ destination: Destination) -> some View {
        LineIcon(symbol: symbol, filled: selection == destination, duotone: true)
            .foregroundStyle(selection == destination ? Theme.Palette.chromeSelected : Theme.Palette.chromeIcon)
    }

    var sidebarSemesters: [Semester] {
        // Oldest first; the credited term comes before any taken one.
        workspace.transcript.semesters.filter { $0.term == .credited } + workspace.semesters.reversed()
    }

    func openBinding(_ semester: Semester, current: Bool) -> Binding<Bool> {
        Binding {
            current != toggledTerms.contains(semester.id)
        } set: { _ in
            // Closed under the pointer, the folder shuts at once rather than when the pointer leaves.
            hoveredTerm = nil
            withAnimation(.snappy(duration: 0.2)) {
                if toggledTerms.remove(semester.id) == nil { toggledTerms.insert(semester.id) }
            }
        }
    }

    func courseRow(_ course: LoadedCourse, last: Bool, now: Date, hint: TodaySummary.CourseHint?) -> some View {
        let accent = workspace.accent(course.id)
        // The course in class right now shows how far the class has gone, from any page: its row fills from the left
        // in its color and the minutes left sit at the end. No ring or dot, so the row keeps the shape of every other.
        let ongoing = workspace.ongoingClass(at: now).flatMap { $0.courseId == course.id ? $0 : nil }
        return Label {
            HStack {
                Text(course.title).lineLimit(1)
                if let ongoing {
                    Spacer(minLength: Theme.Space.xs)
                    Text(.rootMinutesLeft(Int(ongoing.end.timeIntervalSince(now) / 60) + 1)).font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(accent.ink)
                } else if let hint {
                    Spacer(minLength: Theme.Space.xs)
                    courseHint(hint)
                }
            }
        } icon: {
            // A line icon, not a tile: with twenty-odd courses, tiles turn the sidebar into confetti.
            CourseMark(icon: course.file.course.icon, color: accent.color, filled: selection == .course(course.id), duotone: true)
        }
        .help(ongoing.map { String(localized: .rootInClass(course.file.name(of: $0.session))) } ?? hint.map(hintHelp) ?? "")
        .padding(.leading, SidebarGuide.indent)
        .sidebarRow(.course(course.id), $selection, fill: accent.tint, guide: last ? .lastCourse : .course, progress: ongoing?.fraction(at: now))
    }

    @ViewBuilder func courseHint(_ hint: TodaySummary.CourseHint) -> some View {
        Group {
            switch hint {
            // An icon alone, its name and time on hover: "마감" didn't say what was due, and with the time it cut the title.
            case .dueToday: Image(systemName: "checklist").foregroundStyle(Theme.Palette.danger)
            case .nextClass(let date): Text(clock(date)).foregroundStyle(Theme.Palette.chromeText)
            case .exam(let days): Text(days == 0 ? "D-day" : "D-\(days)").foregroundStyle(Theme.Palette.warning)
            }
        }
        .font(Theme.Typeface.caption.weight(.semibold)).monospacedDigit()
    }

    func clock(_ date: Date) -> String { date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()) }

    func hintHelp(_ hint: TodaySummary.CourseHint) -> String {
        switch hint {
        case .dueToday(let a): String(localized: .rootDueTodayHelp(a.title, a.due?.formatted(date: .omitted, time: .shortened) ?? ""))
        case .nextClass(let date): String(localized: .rootNextClassHelp(date.formatted(date: .omitted, time: .shortened)))
        case .exam: ""
        }
    }

    @ViewBuilder var detail: some View {
        switch selection {
        case .today, nil: TodayView(workspace: workspace)
        case .course(let id): CourseView(workspace: workspace, courseID: id).id(id)
        case .semester(let id): SemesterView(workspace: workspace, semesterID: id) { selection = .course($0) }.id(id)
        case .grades: GradesView(workspace: workspace)
        case .requirements:
            // A course with a folder opens itself; a record-only one (credited terms) opens its semester.
            RequirementsView(workspace: workspace) { course in
                if workspace.course(course.id) != nil { selection = .course(course.id) } else if let id = course.semesterId { selection = .semester(id) }
            }
        case .people: PeopleView(workspace: workspace) { selection = .course($0) }
        case .codes: CodesView(workspace: workspace)
        case .settings: SettingsView(workspace: workspace)
        }
    }

    /// Nil keeps the section last open.
    func showSettings(_ tab: SettingsTab?) {
        if let tab { settingsTab = tab }
        selection = .settings
    }
}

extension Semester {
    /// `2026 가을학기`, `인정학기`.
    var title: String {
        switch term {
        case .credited: String(localized: .semesterTitleCredited)
        case .spring: String(localized: .semesterTitleSpring(String(year)))
        case .summer: String(localized: .semesterTitleSummer(String(year)))
        case .fall: String(localized: .semesterTitleFall(String(year)))
        case .winter: String(localized: .semesterTitleWinter(String(year)))
        }
    }
}

/// The sidebar's rows set their own icon gap: the same as a course's branch leaves before its icon, so the icon sits
/// evenly between the branch and its name. With the course column's wider gap it leaned toward the branch.
private struct SidebarLabelStyle: LabelStyle {
    static let gap = Theme.Space.s

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Self.gap) {
            configuration.icon
            configuration.title
        }
    }
}

/// The tools on a term row or the list's name: an add button at the end, shown while the pointer is over it (adding is
/// rare, and an always-there row weighed as much as the items; touch has no hover, so the iPad always shows it), and
/// the term's folder as the button that opens it to its courses. They lie over the row, not in it: the row is a button, and a button
/// inside its label never gets the click.
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
                            // Hidden, it would still take clicks meant for the row under it.
                            .allowsHitTesting(hovering)
                            #endif
                    }
                }
                // The last tool sits as far in from the sidebar's right edge as the row symbols do from its left.
                .padding(.trailing, Theme.Space.tight)
            }
            .overlay(alignment: .leading) {
                // The term's folder opens and closes it, drawn open or closed to show which (and opening under the
                // pointer); the title opens the page.
                if let open {
                    Button { open.wrappedValue.toggle() } label: {
                        Color.clear.frame(width: Theme.Size.tile, height: Theme.Size.tile).contentShape(Rectangle())
                    }
                    .buttonStyle(.pointing(.plain))
                    .help(Text(open.wrappedValue ? .commonCollapse : .commonExpand))
                    .accessibilityLabel(Text(open.wrappedValue ? .commonCollapse : .commonExpand))
                    // This button lies over the folder, so the pointer on the folder is on it, not on the row.
                    .onHover(perform: folderHover)
                }
            }
            .onHover { hovering = $0 }
    }

    func tool(_ symbol: String, font: Font, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(font).frame(width: Theme.Size.tile, height: Theme.Size.tile).contentShape(Rectangle())
        }
        .buttonStyle(.pointing(.plain))
        .foregroundStyle(Theme.Palette.chromeText)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The term's guide line in a sidebar row. `stem` is its start, at the foot of an open term's row: begun at the first
/// course instead, it started a gap below the folder and read as a loose cut line rather than hanging from the term.
enum SidebarGuide {
    case stem, course, lastCourse

    /// A course sits this far in from its term's icon: closer than the term's title, so it reads as the term's own.
    static let indent = Theme.Space.xl
    /// How far a branch runs from the trunk (the middle of the icon column), stopping short of the course's icon.
    static var reach: CGFloat { indent - SidebarLabelStyle.gap - Theme.Size.tile / 2 }
}

/// The guide's segment in one row. A course row gets a branch curving off the trunk toward it; the last one's trunk
/// stops at its branch, so the line ends in a turn instead of a square cut.
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
    func rowTools(add: String? = nil, action: @escaping () -> Void = {}, open: Binding<Bool>? = nil, folderHover: @escaping (Bool) -> Void = { _ in }) -> some View {
        modifier(RowTools(add: add, action: action, open: open, folderHover: folderHover))
    }

    /// On the Mac each row picks itself and draws its own fill: the Mac sidebar's selection is one gray whatever the
    /// tint, which turned a chosen course into a gray block. The iPad keeps the list's selection, which also pushes the
    /// detail when the split view folds into one column.
    /// `guide` draws the term's line beside a course row. On the Mac it is in the row background, which spans the row
    /// spacing, so the segments join without overlapping (a see-through line darkens where segments overlap).
    /// `guideShown` fades the line rather than leaving it out: the Mac list doesn't redraw a row background whose views
    /// come and go, only one whose values change, and rebuilding the row instead made it jump as it opened.
    @ViewBuilder func sidebarRow(_ destination: Destination, _ selection: Binding<Destination?>, fill: Color = Theme.Palette.sidebarSelection, guide: SidebarGuide? = nil, guideShown: Bool = true, progress: Double? = nil) -> some View {
        let line = guide.map { GuideSegment(guide: $0).stroke(Theme.Palette.chromeLine, lineWidth: 1).frame(width: SidebarGuide.reach + 1) }
        #if os(macOS)
        let chosen = selection.wrappedValue == destination
        // A tap, not a Button: a button keeps the press, so the list's own drag to reorder never starts.
        frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        .onTapGesture { selection.wrappedValue = destination }
        .listRowBackground(
            ZStack(alignment: .leading) {
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.control)
                ZStack {
                    shape.fill(chosen ? fill : .clear)
                    // The part of the class gone by, laid in the same tint: over a chosen row it reads a step deeper.
                    if let progress {
                        Rectangle().fill(fill).scaleEffect(x: progress, anchor: .leading).clipShape(shape)
                    }
                }
                .padding(.horizontal, Theme.Space.s)
                // The Mac sidebar starts a row's content 16pt in from the background's edge (measured), so this is
                // the middle of the icon column.
                if let guide, let line {
                    line.frame(maxHeight: guide == .stem ? Theme.Space.tight : .infinity)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.leading, Theme.Space.l + Theme.Size.tile / 2)
                        .opacity(guideShown ? 1 : 0)
                }
            }
        )
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { selection.wrappedValue = destination }
        #else
        tag(destination)
            .background(alignment: .leading) {
                if guide != .stem, let line { line.padding(.vertical, -Theme.Space.xs).padding(.leading, Theme.Size.tile / 2) }
            }
        #endif
    }
}
