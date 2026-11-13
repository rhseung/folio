import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Observation

struct LoadedCourse: Identifiable {
    var store: CourseStore
    var document: StoredDocument<CourseFile>
    var id: UUID { document.model.course.id }
    var file: CourseFile { document.model }
    var title: String { file.course.title }
}

@MainActor @Observable
final class Workspace {
    private(set) var gist: GISTStore?
    private(set) var transcript = Transcript()
    private(set) var catalog = Catalog()
    // catalog.json을 읽지 못한 동안 목록을 저장하면 파일이 화면에 보이는 값으로 바뀐다.
    private(set) var catalogLoaded = true
    private(set) var settings = Settings()
    private(set) var courses: [LoadedCourse] = []
    private(set) var reviewEvents: [UUID: [LoggedEvent]] = [:]
    var error: String?
    var showsFirstRun = false
    var folderTrouble: FolderTrouble?
    @ObservationIgnored var folderWait: Task<Void, Never>?
    // 연결 설정과 API key는 관찰되지 않는 곳(UserDefaults, keychain)에 있으므로, 이 값을 올리지 않으면 `claudeReady`를 읽는
    // 뷰가 낡은 답을 유지한다.
    var claudeRevision = 0
    // 노트와 카드 목록은 디스크에서 파일을 읽으므로 `courses`만 관찰해서는 바뀐 것을 알 수 없다.
    private(set) var notesRevision = 0
    private(set) var quizRevision = 0
    private(set) var dataRevision = 0
    var gradesUnlocked = false
    @ObservationIgnored var gradeRelock: Task<Void, Never>?
    let recorder = LectureRecorder()
    var finishingRecordings = Set<UUID>()
    var wrapUpAsk: ClassWrapUpAsk?
    var classStartAsk: ClassStartAsk?
    @ObservationIgnored var classStartDone: [String: Set<ClassStart.Step>] = [:]
    @ObservationIgnored var classRecordingStop: ClassRecordingStop?
    var splitAsk: UUID?
    @ObservationIgnored var recoveryTried = Set<UUID>()
    // 테스트, 미리보기, 렌더가 처음 쓰기 전에 자기 폴더를 줄 수 있도록 lazy로 둔다. 주지 않으면 이 Mac의 끝나지 않은 녹음을
    // 픽스처로 복구하지 않고 그 자리에서 멈춘다(`LocalFolders`).
    @ObservationIgnored lazy var pendingRecordings = PendingRecordings(url: LocalFolders.applicationSupport("Recording", perGIST: true))
    let transcriptions = TranscriptionQueue()
    var releaseNotes = ReleaseNotes()
    var lms = LMSConnection()
    @ObservationIgnored private var watcher: GISTWatcher?
    @ObservationIgnored private var lastOwnWrite = Date.distantPast
    @ObservationIgnored private var pendingReload: Task<Void, Never>?

    let device = LocalDevice.id()
    var calendar = Calendar.current
    var pinnedNow: Date?
    var now: Date { pinnedNow ?? .now }
    let clock = LiveClock()
    // 모든 페이지가 그릴 때 읽는 `now`와 분리해야 그 페이지들이 분마다 다시 그려지지 않는다.
    var liveNow: Date { pinnedNow ?? clock.now }

    static let bookmarkKey = "folio.gistBookmark"
    static let pathKey = "folio.gistPath"
    nonisolated static let environmentKey = "FOLIO_GIST"

    init() {
        // 테스트 host와 Xcode 미리보기는 저장된 폴더를 열면 안 된다. 그 폴더는 실제 GIST 폴더다.
        let env = ProcessInfo.processInfo.environment
        if LocalFolders.isIsolated(env) { return }
        if let path = env[Self.environmentKey] {
            open(URL(filePath: path, directoryHint: .isDirectory), remember: false)
        } else if UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil {
            openRemembered()
        } else {
            showsFirstRun = true
        }
        #if DEBUG
        if FirstRunDebug.requested { showsFirstRun = true }
        #endif
    }

    // 테스트, 미리보기, 픽스처 실행(`FOLIO_GIST`)은 자기 폴더를 연다. 그 폴더를 기억하면 다음 실제 실행이 픽스처를 연다.
    nonisolated static var remembersFolders: Bool {
        let env = ProcessInfo.processInfo.environment
        return !LocalFolders.isIsolated(env) && env[environmentKey] == nil
    }

    func open(_ url: URL, remember: Bool = true) {
        // 앱이 실행되는 동안 접근을 계속 연다. iPadOS는 Files에서 고른 폴더에 이를 요구한다.
        _ = url.startAccessingSecurityScopedResource()
        if Self.remembersFolders {
            if remember, let data = try? url.bookmarkData() {
                UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            }
            UserDefaults.standard.set(url.path(percentEncoded: false), forKey: Self.pathKey)
        }
        folderTrouble = nil
        folderWait?.cancel()
        gist = GISTStore(url: url)
        watcher?.stop()
        watcher = GISTWatcher(url: url) { [weak self] in Task { @MainActor in self?.changedOutside() } }
        reload()
    }

    // iCloud 동기화는 많은 파일을 건드리므로 한 묶음마다 한 번만 다시 읽는다. 앱 자신의 쓰기도 presenter로 돌아오지만 이미
    // 보이고 있으므로 건너뛴다.
    private func changedOutside() {
        guard Date.now.timeIntervalSince(lastOwnWrite) > 2 else { return }
        pendingReload?.cancel()
        pendingReload = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    // 파일마다 따로 읽는다. 실패한 파일은 전에 보이던 값을 유지하고 보고된다. 그렇지 않으면 모든 과목이 사라지거나, 빈
    // 파일로 대신 읽혀 다음 저장이 실제 파일을 덮어쓴다.
    func reload() {
        guard let gist else { return }
        var problems: [String] = []
        func attempt<T>(_ name: String, _ read: () throws -> T) -> T? {
            do { return try read() } catch { problems.append("\(name): \(error)"); return nil }
        }
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

        transcript =
            attempt("transcript.json") { exists(gist.transcriptURL) ? try gist.loadTranscript().model : Transcript() } ?? transcript
        let loadedCatalog = attempt("catalog.json") { exists(gist.catalogURL) ? try gist.loadCatalog().model : Catalog() }
        catalog = loadedCatalog ?? catalog
        catalogLoaded = loadedCatalog != nil
        settings = attempt("settings.json") { try gist.loadSettings().model } ?? settings

        let stores = attempt(String(localized: .workspaceCourseFolders)) { try gist.courseStores() } ?? []
        var seen = Set<UUID>()
        courses = stores.compactMap { store in
            guard let course = attempt(store.url.lastPathComponent, { LoadedCourse(store: store, document: try store.load()) }) else {
                return nil
            }
            guard seen.insert(course.id).inserted else {
                problems.append(String(localized: .workspaceDuplicateCourseId(store.url.lastPathComponent)))
                return nil
            }
            return course
        }

        reviewEvents = Dictionary(
            keepingFirst: courses.map { c in
                (c.id, (try? c.store.log.readAll().filter { $0.type == ReviewEvent.type }) ?? [])
            })

        if !problems.isEmpty { error = String(localized: .workspaceUnreadableFiles) + "\n" + problems.joined(separator: "\n") }
        notesRevision += 1
        quizRevision += 1
        dataRevision += 1
        recoverRecordings()
    }

    // MARK: Queries

    func semester(of course: Course) -> Semester? {
        transcript.semesters.first { $0.id == course.semesterId }
    }

    var semesters: [Semester] {
        transcript.semesters
            .filter { $0.term != .credited }
            .sorted { $0.order > $1.order }
    }

    var currentSemester: Semester? { semesters.current(on: LocalDate(now, in: calendar)) }

    var currentCourses: [LoadedCourse] { currentSemester.map { courses(in: $0) } ?? [] }

    func courses(in semester: Semester) -> [LoadedCourse] {
        courses.filter { $0.file.course.semesterId == semester.id }.sorted { $0.title < $1.title }
    }

    func sidebarCourses(in semester: Semester) -> [LoadedCourse] {
        let byId = Dictionary(courses(in: semester).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return SidebarOrder.arrange(courses(in: semester).map(\.id), by: settings.sidebar.courses).compactMap { byId[$0] }
    }

    func moveSidebarCourses(in semester: Semester, from source: IndexSet, to destination: Int) {
        guard let first = source.first else { return }
        var new = settings
        new.sidebar.move(sidebarCourses(in: semester).map(\.id), from: first, to: destination)
        saveSettings(new)
    }

    func course(_ id: UUID) -> LoadedCourse? {
        courses.first { $0.id == id }
    }

    var allCourses: [Course] { courses.map(\.file.course) }

    typealias ReviewEntry = FolioDomain.ReviewEntry

    func ongoingClass(at now: Date) -> TodaySummary.OngoingClass? {
        TodaySummary.ongoingClass(in: currentCourses.map(\.file), at: now, calendar: calendar)
    }

    func reviewQueue(now: Date) -> [ReviewEntry] {
        ReviewScheduler.queue(
            courses: currentCourses.map { ($0.file, (reviewEvents[$0.id] ?? []).events(ReviewEvent.self)) },
            settings: settings, calendar: calendar, now: now)
    }

    // MARK: Semesters and courses

    func folderName(title: String, codes: [UUID], number: String) -> String? {
        try? CourseRename.folderName(title: title, codes: codes, number: number, catalog: catalog)
    }

    // MARK: Checks

    private func checkContext() -> ActionContext? {
        guard let gist else { return nil }
        let ctx = ActionContext(
            gist: gist, device: device, now: now, calendar: calendar, dryRun: true,
            courses: Dictionary(courses.map { ($0.id, $0.store) }, uniquingKeysWith: { a, _ in a }))
        ctx.preload(courses: courses.map(\.document), transcript: transcript, catalog: catalog, settings: settings)
        return ctx
    }

    func refusal(_ action: some Action) -> String? {
        guard let ctx = checkContext() else { return String(localized: .workspaceNoGist) }
        do {
            try action.run(ctx)
            return nil
        } catch {
            return "\(error)"
        }
    }

    // 같은 dry run을 함께 쓰므로 각 액션은 앞의 액션이 남긴 course.json으로 검사된다. 노트의 글은 이어지지 않는다. dry run은
    // 파일을 쓰지 않으므로, 같은 노트를 다시 쓴 뒤의 편집은 디스크의 글로 검사된다.
    func refusal(_ actions: [any Action]) -> (index: Int, reason: String)? {
        guard let ctx = checkContext() else { return actions.isEmpty ? nil : (0, String(localized: .workspaceNoGist)) }
        for (i, action) in actions.enumerated() {
            do { try action.run(ctx) } catch { return (i, "\(error)") }
        }
        return nil
    }

    func stagedRefusal(_ actions: [any Action]) -> (index: Int, reason: String)? {
        guard let gist else { return actions.isEmpty ? nil : (0, String(localized: .workspaceNoGist)) }
        let copy: StagedFolder
        do { copy = try StagedFolder(copying: gist.url) } catch { return (0, "\(error)") }
        defer { copy.remove() }
        let (device, now, calendar) = (device, now, calendar)
        return copy.run { () -> (index: Int, reason: String)? in
            let gist = GISTStore(url: copy.url)
            let ctx = ActionContext(gist: gist, device: device, now: now, calendar: calendar)
            for (i, action) in actions.enumerated() {
                // 백업과 가져오기는 폴더 밖에 쓰고, 사본은 그런 쓰기를 막는다. 그래서 dry run만 하고, 앞의 액션이 사본에 쓴 것을 읽는
                // 별도의 context에서 돌린다.
                let staged = ActionProposal.stages(type(of: action).command)
                do {
                    try action.run(staged ? ctx : ActionContext(gist: gist, device: device, now: now, calendar: calendar, dryRun: true))
                } catch { return (i, "\(error)") }
            }
            return nil
        }
    }

    func can(_ action: some Action) -> Bool { refusal(action) == nil }

    func confirmation<A: Action>(_ action: A) -> String? {
        guard A.spec.asks(action), let text = A.spec.confirm, let ctx = checkContext() else { return nil }
        return A.spec.render(text, action, ctx: ctx)
    }

    func summary<A: Action>(_ action: A) -> String {
        guard let ctx = checkContext() else { return A.spec.summary }
        return A.spec.render(A.spec.done, action, ctx: ctx)
    }

    // MARK: Writes (only from explicit user actions)

    @discardableResult
    func run(_ action: some Action) -> ActionContext? {
        do { return try runThrowing(action) } catch {
            self.error = "\(error)"
            return nil
        }
    }

    func runThrowing(_ action: some Action) throws -> ActionContext {
        guard let gist else { throw ActionError.notFound(String(localized: .workspaceNoGist)) }
        let ctx = ActionContext(
            gist: gist, device: device, now: now, calendar: calendar,
            courses: Dictionary(courses.map { ($0.id, $0.store) }, uniquingKeysWith: { a, _ in a }))
        defer { show(ctx) }
        try action.run(ctx)
        return ctx
    }

    func show(_ ctx: ActionContext) {
        lastOwnWrite = .now
        dataRevision += 1
        if ctx.changes.contains(where: \.touchesNotes) { notesRevision += 1 }
        if ctx.changes.contains(where: \.touchesQuizzes) { quizRevision += 1 }
        if ctx.needsReload {
            reload()
            return
        }
        for (id, doc) in ctx.savedCourses {
            if let i = courses.firstIndex(where: { $0.id == id }) { courses[i].document = doc }
        }
        for id in ctx.loggedCourses {
            guard let course = course(id) else { continue }
            reviewEvents[id] = (try? course.store.log.readAll().filter { $0.type == ReviewEvent.type }) ?? []
        }
    }

    func perform(_ action: () throws -> Void) {
        lastOwnWrite = .now
        do { try action() } catch { self.error = "\(error)" }
    }
}
