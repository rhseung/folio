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

/// Everything the screens show, read from the GIST folder through Storage. Views never touch the file system.
@MainActor @Observable
final class Workspace {
    private(set) var gist: GISTStore?
    private(set) var transcript = Transcript()
    private(set) var catalog = Catalog()
    /// False while catalog.json fails to read: saving the catalog then would replace the file with what is shown.
    private(set) var catalogLoaded = true
    private(set) var settings = Settings()
    private(set) var courses: [LoadedCourse] = []
    private(set) var reviewEvents: [UUID: [LoggedEvent]] = [:]
    var error: String?
    /// Bumped when the Claude connection setting or the API key changes. Neither lives in observed state (UserDefaults,
    /// the keychain), so views reading `claudeReady` would otherwise keep a stale answer.
    var claudeRevision = 0
    /// Bumped when a note's kind or links change from its editor, so the note list re-reads the frontmatter it shows.
    var notesRevision = 0
    /// Grades stay hidden until the device owner unlocks them; never saved, so every launch starts locked.
    var gradesUnlocked = false
    @ObservationIgnored var gradeRelock: Task<Void, Never>?
    /// One lecture recording at a time, kept here so it continues while the user moves around the app.
    let recorder = LectureRecorder()
    /// Recordings being compressed into their course folder; each runs once even when a reload asks again.
    @ObservationIgnored var finishingRecordings = Set<UUID>()
    @ObservationIgnored private var watcher: GISTWatcher?
    @ObservationIgnored private var lastOwnWrite = Date.distantPast
    @ObservationIgnored private var pendingReload: Task<Void, Never>?

    let device = LocalDevice.id()
    let calendar = Calendar.current

    static let bookmarkKey = "folio.gistBookmark"
    /// The folder as a plain path for the folio command, which can't resolve this app's bookmark without a sandbox warning.
    static let pathKey = "folio.gistPath"
    /// Lets a development run point at a fixture copy instead of the real folder.
    static let environmentKey = "FOLIO_GIST"

    init() {
        if let path = ProcessInfo.processInfo.environment[Self.environmentKey] {
            open(URL(filePath: path, directoryHint: .isDirectory), remember: false)
        } else if let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) {
                open(url, remember: stale)
            }
        }
    }

    func open(_ url: URL, remember: Bool = true) {
        // Access stays open for the app's lifetime; iPadOS requires it for folders picked in Files.
        _ = url.startAccessingSecurityScopedResource()
        if remember, let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
        if ProcessInfo.processInfo.environment[Self.environmentKey] == nil {
            UserDefaults.standard.set(url.path(percentEncoded: false), forKey: Self.pathKey)
        }
        gist = GISTStore(url: url)
        watcher?.stop()
        watcher = GISTWatcher(url: url) { [weak self] in Task { @MainActor in self?.changedOutside() } }
        reload()
    }

    /// Reads everything again shortly after files change outside the app, once per burst (an iCloud sync touches many).
    /// The app's own writes come back through the presenter too; they are already shown, so those are skipped.
    private func changedOutside() {
        guard Date.now.timeIntervalSince(lastOwnWrite) > 2 else { return }
        pendingReload?.cancel()
        pendingReload = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    /// Each file loads on its own: one that fails keeps what was shown before and is reported, instead of hiding
    /// every course or standing in as an empty file that the next save would write over the real one.
    func reload() {
        guard let gist else { return }
        var problems: [String] = []
        func attempt<T>(_ name: String, _ read: () throws -> T) -> T? {
            do { return try read() } catch { problems.append("\(name): \(error)"); return nil }
        }
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
        transcript = attempt("transcript.json") { exists(gist.transcriptURL) ? try gist.loadTranscript().model : Transcript() } ?? transcript
        let loadedCatalog = attempt("catalog.json") { exists(gist.catalogURL) ? try gist.loadCatalog().model : Catalog() }
        catalog = loadedCatalog ?? catalog
        catalogLoaded = loadedCatalog != nil
        settings = attempt("settings.json") { try gist.loadSettings().model } ?? settings
        let stores = attempt("과목 폴더") { try gist.courseStores() } ?? []
        var seen = Set<UUID>()
        courses = stores.compactMap { store in
            guard let course = attempt(store.url.lastPathComponent, { LoadedCourse(store: store, document: try store.load()) }) else { return nil }
            guard seen.insert(course.id).inserted else {
                problems.append("\(store.url.lastPathComponent): 다른 과목 폴더와 같은 과목 ID라서 건너뜁니다")
                return nil
            }
            return course
        }
        reviewEvents = Dictionary(keepingFirst: courses.map { c in
            (c.id, (try? c.store.log.readAll().filter { $0.type == ReviewEvent.type }) ?? [])
        })
        // Never cleared here: callers reload right after a failed save, whose message must stay up.
        if !problems.isEmpty { error = "읽지 못한 파일이 있습니다.\n" + problems.joined(separator: "\n") }
        recoverRecordings()
    }

    // MARK: Queries

    func semester(of course: Course) -> Semester? {
        transcript.semesters.first { $0.id == course.semesterId }
    }

    /// Regular semesters, newest first. Empty ones are listed too, so a newly added term shows up.
    var semesters: [Semester] {
        transcript.semesters
            .filter { $0.term != .credited }
            .sorted { $0.order > $1.order }
    }

    /// The latest semester that has started (or the earliest upcoming one if none has).
    var currentSemester: Semester? {
        let today = LocalDate(.now, in: calendar)
        return semesters.first { ($0.start ?? today) <= today } ?? semesters.last
    }

    /// Courses of a semester that live only in transcript.json (no folder).
    func recordOnlyCourses(in semester: Semester) -> [Course] {
        transcript.courses.filter { $0.semesterId == semester.id }
    }

    var currentCourses: [LoadedCourse] { currentSemester.map { courses(in: $0) } ?? [] }

    func courses(in semester: Semester) -> [LoadedCourse] {
        courses.filter { $0.file.course.semesterId == semester.id }.sorted { $0.title < $1.title }
    }

    /// The order the user dragged the term's courses into. Colors and every other list keep `courses(in:)`, so moving a
    /// course in the sidebar doesn't recolor the ones without a color of their own.
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

    var allCourseRecords: [Course] {
        transcript.courses + courses.map(\.file.course)
    }

    typealias ReviewEntry = FolioDomain.ReviewEntry

    func ongoingClass(at now: Date) -> TodaySummary.OngoingClass? {
        TodaySummary.ongoingClass(in: currentCourses.map(\.file), at: now, calendar: calendar)
    }

    func reviewQueue(now: Date) -> [ReviewEntry] {
        ReviewScheduler.queue(courses: currentCourses.map { ($0.file, (reviewEvents[$0.id] ?? []).events(ReviewEvent.self)) },
                              settings: settings, calendar: calendar, now: now)
    }

    // MARK: Unclassified files

    /// The course folder relative to the GIST root, with a trailing slash.
    func coursePrefix(_ id: UUID) -> String? {
        guard let gist, let course = course(id) else { return nil }
        let root = gist.url.standardizedFileURL.path
        return String(course.store.url.standardizedFileURL.path.dropFirst(root.count + 1)) + "/"
    }

    /// The one-time cleanup's moves for files still left in this course, including the ones it was unsure about.
    /// Reading the whole GIST tree is slow, so this runs off the main actor.
    func cleanupSuggestions(for id: UUID) async -> [PlannedMove] {
        guard let gist, let prefix = coursePrefix(id), let course = course(id) else { return [] }
        let url = gist.url
        let labs = [String(prefix.dropLast()): course.file.labNumbers]
        let labWeeks = [String(prefix.dropLast()): course.file.labWeeks]
        let moves = await Task.detached {
            (try? GISTStore(url: url).readTree()).map { CleanupPlanner.plan($0, labs: labs, labWeeks: labWeeks).moves } ?? []
        }.value
        return moves.filter { $0.from.hasPrefix(prefix) }
    }

    /// Moves files only after the user approved this exact move; the batch goes to `moves.jsonl` so it can be undone.
    func approve(_ moves: [PlannedMove], course id: UUID) -> UUID? {
        run(CleanupApply(moves: moves, course: id))?.made
    }

    func undoMoves(_ batch: UUID, course id: UUID) {
        run(CleanupUndo(batch: batch, course: id))
    }

    // MARK: Semesters and courses

    func addSemester(year: Int, term: Term, start: LocalDate?, end: LocalDate?) -> UUID? {
        run(SemesterAdd(year: year, term: term, start: start, end: end))?.made
    }

    /// `<main code><number> <title>`; nil when the codes are empty or the name breaks the naming rule.
    func folderName(title: String, codes: [UUID], number: String) -> String? {
        try? CourseRename.folderName(title: title, codes: codes, number: number, catalog: catalog)
    }

    // MARK: Checks

    /// A dry run against what the app shows, so a button follows the action's own rules rather than a copy in the view.
    private func checkContext() -> ActionContext? {
        guard let gist else { return nil }
        let ctx = ActionContext(gist: gist, device: device, now: .now, calendar: calendar, dryRun: true,
                                courses: Dictionary(courses.map { ($0.id, $0.store) }, uniquingKeysWith: { a, _ in a }))
        ctx.preload(courses: courses.map(\.document), transcript: transcript, catalog: catalog, settings: settings)
        return ctx
    }

    /// Why the action would be refused, or nil when it would go through. Nothing is written.
    func refusal(_ action: some Action) -> String? {
        guard let ctx = checkContext() else { return "GIST 폴더를 고르지 않았습니다" }
        do {
            try action.run(ctx)
            return nil
        } catch {
            return "\(error)"
        }
    }

    func can(_ action: some Action) -> Bool { refusal(action) == nil }

    /// The question to ask before running the action, as the CLI asks it; nil when it runs without asking.
    func confirmation<A: Action>(_ action: A) -> String? {
        guard A.spec.asks(action), let text = A.spec.confirm, let ctx = checkContext() else { return nil }
        return A.spec.render(text, action, ctx: ctx)
    }

    // MARK: Writes (only from explicit user actions)

    /// Runs an action the way the CLI does, then shows what it changed. A failure goes to the error banner.
    @discardableResult
    func run(_ action: some Action) -> ActionContext? {
        do { return try runThrowing(action) } catch {
            self.error = "\(error)"
            return nil
        }
    }

    func runThrowing(_ action: some Action) throws -> ActionContext {
        guard let gist else { throw ActionError.notFound("GIST 폴더를 고르지 않았습니다") }
        let ctx = ActionContext(gist: gist, device: device, now: .now, calendar: calendar,
                                courses: Dictionary(courses.map { ($0.id, $0.store) }, uniquingKeysWith: { a, _ in a }))
        // Shown even when the action fails halfway: what it already wrote is on disk.
        defer { show(ctx) }
        try action.run(ctx)
        return ctx
    }

    func show(_ ctx: ActionContext) {
        lastOwnWrite = .now
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
