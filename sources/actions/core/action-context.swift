import FolioDomain
import FolioStorage
import Foundation

public final class ActionContext {
    public let gist: GISTStore
    public let device: DeviceID
    public let now: Date
    public let calendar: Calendar
    public let dryRun: Bool
    public private(set) var changes: [Change] = []
    public private(set) var made: UUID?
    public private(set) var savedCourses: [UUID: StoredDocument<CourseFile>] = [:]
    public private(set) var needsReload = false
    public private(set) var loggedCourses: Set<UUID> = []
    public private(set) var notes: [String] = []

    private var stores: [UUID: CourseStore]?
    private var courseDocs: [UUID: StoredDocument<CourseFile>] = [:]
    private var transcriptDoc: StoredDocument<Transcript>?
    private var catalogDoc: StoredDocument<Catalog>?
    private var settingsDoc: StoredDocument<Settings>?

    public init(
        gist: GISTStore, device: DeviceID, now: Date = .now, calendar: Calendar = .current, dryRun: Bool = false,
        courses: [UUID: CourseStore]? = nil
    ) {
        self.gist = gist
        self.device = device
        self.now = now
        self.calendar = calendar
        self.dryRun = dryRun
        self.stores = courses
    }

    public func preload(courses: [StoredDocument<CourseFile>], transcript: Transcript, catalog: Catalog, settings: Settings) {
        precondition(dryRun, "preloaded documents are never saved")
        for doc in courses { courseDocs[doc.model.course.id] = doc }
        transcriptDoc = StoredDocument(new: transcript)
        catalogDoc = StoredDocument(new: catalog)
        settingsDoc = StoredDocument(new: settings)
    }

    // MARK: Reads

    public func store(_ course: UUID) throws -> CourseStore {
        guard let store = try courseStores()[course] else {
            throw ActionError.notFound(String(localized: .errorNotFoundCourseId("\(course)")))
        }
        return store
    }

    private func courseStores() throws -> [UUID: CourseStore] {
        if let stores { return stores }
        let found = Dictionary(
            try gist.courseStores().compactMap { s in (try? s.load()).map { ($0.model.course.id, s) } },
            uniquingKeysWith: { a, _ in a })
        stores = found
        return found
    }

    public func hasFolder(_ course: UUID) -> Bool { (try? store(course)) != nil }

    // 보인 뒤에 다른 기기나 앱이 파일을 바꿨을 수 있으므로 액션마다 한 번 디스크에서 읽는다.
    public func file(_ course: UUID) throws -> CourseFile {
        try document(course).model
    }

    public func transcript() throws -> Transcript { try transcriptDocument().model }

    public func catalog() throws -> Catalog { try catalogDocument().model }

    public func settings() throws -> Settings { try settingsDocument().model }

    private func transcriptDocument() throws -> StoredDocument<Transcript> {
        if let transcriptDoc { return transcriptDoc }
        let doc =
            FileManager.default.fileExists(atPath: gist.transcriptURL.path) ? try gist.loadTranscript() : StoredDocument(new: Transcript())
        transcriptDoc = doc
        return doc
    }

    private func catalogDocument() throws -> StoredDocument<Catalog> {
        if let catalogDoc { return catalogDoc }
        let doc = FileManager.default.fileExists(atPath: gist.catalogURL.path) ? try gist.loadCatalog() : StoredDocument(new: Catalog())
        catalogDoc = doc
        return doc
    }

    private func settingsDocument() throws -> StoredDocument<Settings> {
        if let settingsDoc { return settingsDoc }
        let doc = try gist.loadSettings()
        settingsDoc = doc
        return doc
    }

    public func name(of id: UUID) -> String? {
        if let n = (try? transcript())?.name(of: id) ?? (try? catalog())?.name(of: id) { return n }
        for course in ((try? courseStores()) ?? [:]).keys {
            guard let f = try? file(course) else { continue }
            if let s = f.sessions.first(where: { $0.id == id }) { return f.title(of: s, calendar: calendar) }
            if let n = f.name(of: id) { return n }
        }
        return nil
    }

    public func semester(of course: Course) throws -> Semester? {
        try transcript().semesters.first { $0.id == course.semesterId }
    }

    private func document(_ course: UUID) throws -> StoredDocument<CourseFile> {
        if let doc = courseDocs[course] { return doc }
        let doc = try store(course).load()
        courseDocs[course] = doc
        return doc
    }

    // MARK: Writes

    public func edit(_ course: UUID, _ change: (inout CourseFile) throws -> Void) throws {
        let store = try store(course)
        var doc = try document(course)
        let before = doc.model
        do { try change(&doc.model) } catch let e as ModelError { throw ActionError(e) }
        guard doc.model != before else { return }
        try refuseNewViolation(before, doc.model, World(catalog: catalog(), transcript: transcript()))
        doc.model.course.touch(by: device, at: now)
        courseDocs[course] = doc
        changes += diff(before, doc.model, path: relative(store.courseFileURL))
        if !dryRun {
            try store.save(doc)
            savedCourses[course] = doc
        }
    }

    public func editQuiz(_ course: UUID, unit: UUID, _ change: (inout [QuizCard]) throws -> Void) throws {
        let store = try store(course)
        var doc = try store.loadQuiz(unit: unit)
        let before = doc.model
        try change(&doc.model.cards)
        guard doc.model != before else { return }
        try refuseNewViolation(before, doc.model, World())
        changes += diff(before, doc.model, path: relative(store.quizURL(unit: unit)))
        if !dryRun { try store.save(doc) }
    }

    public func notes(_ course: UUID) throws -> [NoteFile] {
        try store(course).notes(in: file(course))
    }

    @discardableResult
    public func createNote(_ course: UUID, title: String, meta: NoteMeta, format: NoteFormat = .markdown, body: String) throws -> UUID {
        let store = try store(course)
        let id = meta.id ?? UUID()
        if try file(course).notes.contains(where: { $0.id == id }) { throw ActionError.rule(String(localized: .errorIdTakenNote("\(id)"))) }
        let url = store.newNoteURL(title: title, format: format)
        try io(Change(.added, relative(url))) { try store.createNote(at: url, text: body) }
        try edit(course) { $0.notes.append(NoteEntry(id: id, device: device, at: now, path: store.notePath(of: url), meta: meta)) }
        return id
    }

    public func editTranscript(_ change: (inout Transcript) throws -> Void) throws {
        var doc = try transcriptDocument()
        let before = doc.model
        guard try checkTranscript(&doc.model, change) else { return }
        transcriptDoc = doc
        changes += diff(before, doc.model, path: relative(gist.transcriptURL))
        needsReload = true
        if !dryRun { try gist.save(doc) }
    }

    // 이동 뒤에 거절하면 transcript.json이 없어진 폴더를 가리키므로, 편집이 말하는 폴더를 옮기기 전에 사본으로 규칙을
    // 확인한다.
    public func checkTranscript(_ change: (inout Transcript) throws -> Void) throws {
        var model = try transcript()
        try checkTranscript(&model, change)
    }

    @discardableResult
    private func checkTranscript(_ model: inout Transcript, _ change: (inout Transcript) throws -> Void) throws -> Bool {
        let before = model
        do { try change(&model) } catch let e as ModelError { throw ActionError(e) }
        guard model != before else { return false }
        let catalog = try catalog()
        try refuseNewViolation(before, model, World(catalog: catalog))
        try refuseBreakingCourses(World(catalog: catalog, transcript: before), World(catalog: catalog, transcript: model))
        return true
    }

    public func editCatalog(_ change: (inout Catalog) throws -> Void) throws {
        var doc = try catalogDocument()
        let before = doc.model
        do { try change(&doc.model) } catch let e as ModelError { throw ActionError(e) }
        guard doc.model != before else { return }
        try refuseNewViolation(before, doc.model, World())
        let transcript = try transcript()
        if let v = Transcript.model.newViolation(transcript, in: World(catalog: before), transcript, in: World(catalog: doc.model)) {
            throw ActionError.rule(String(localized: .errorInUse(v.message)))
        }
        try refuseBreakingCourses(World(catalog: before, transcript: transcript), World(catalog: doc.model, transcript: transcript))
        catalogDoc = doc
        changes += diff(before, doc.model, path: relative(gist.catalogURL))
        needsReload = true
        if !dryRun { try gist.save(doc) }
    }

    public func editSettings(_ change: (inout Settings) throws -> Void) throws {
        var doc = try settingsDocument()
        let before = doc.model
        try change(&doc.model)
        guard doc.model != before else { return }
        try refuseNewViolation(before, doc.model, World())
        settingsDoc = doc
        changes += diff(before, doc.model, path: relative(gist.settingsURL))
        needsReload = true
        if !dryRun { try gist.save(doc) }
    }

    // 저장은 새 위반을 더할 수 없다. 파일에 이미 있던 위반은 허용하므로, 깨진 파일을 여러 번에 나눠 고칠 수 있다.
    private func refuseNewViolation<D: Document>(_ before: D, _ after: D, _ world: World) throws {
        if let v = D.model.newViolation(before, in: world, after, in: world) { throw ActionError.rule(v.message) }
    }

    // 과목 파일은 카탈로그와 성적표를 가리키므로, 그것을 바꾸면 손대지 않은 과목 파일도 깨질 수 있다.
    private func refuseBreakingCourses(_ before: World, _ after: World) throws {
        for course in try courseStores().keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let file = try file(course)
            if let v = CourseFile.model.newViolation(file, in: before, file, in: after) {
                throw ActionError.rule(String(localized: .errorInUse(v.message)))
            }
        }
    }

    public func log<E: LogEvent>(_ event: E, course: UUID, at date: Date? = nil) throws {
        let store = try store(course)
        changes.append(
            Change(
                .changed, relative(store.log.folder.appending(path: device.uuidString).appendingPathExtension(StandardLayout.logExtension)),
                item: E.type))
        loggedCourses.insert(course)
        if !dryRun { try store.log.append(event, device: device, at: date ?? now) }
    }

    @discardableResult
    public func io<T>(_ change: Change, _ perform: () throws -> T) throws -> T? {
        changes.append(change)
        needsReload = needsReload || change.path.hasSuffix("/") || change.kind == .moved
        return dryRun ? nil : try perform()
    }

    public func record(_ change: Change) { changes.append(change) }

    public func made(_ id: UUID) { made = id }

    public func note(_ line: String) { notes.append(line) }

    public func invalidate() {
        needsReload = true
        stores = nil
        courseDocs = [:]
        transcriptDoc = nil
        catalogDoc = nil
        settingsDoc = nil
    }

    public func relative(_ url: URL) -> String {
        let root = gist.url.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path
    }

    public func relative(_ course: UUID, _ coursePath: String) throws -> String {
        relative(try store(course).fileURL(coursePath))
    }
}
