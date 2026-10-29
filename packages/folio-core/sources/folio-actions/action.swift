import FolioDomain
import FolioStorage
import Foundation

/// One change to the user's data. The app's screens and the `folio` CLI build the same value and run it the same way,
/// so the files they leave behind are the same (docs/SPEC.md "액션").
/// Declared with `@Action`, which writes `spec` and checks the declaration; see docs/SPEC.md "액션".
public protocol Action: Codable, Sendable {
    static var spec: ActionSpec { get }
    func run(_ ctx: ActionContext) throws
}

extension Action {
    /// `folio actions --check` matches commands on it.
    public static var command: String { spec.command }
}

/// Why an action refused to run. Each case is its own CLI exit code (docs/SPEC.md "출력").
public enum ActionError: Error, Equatable, CustomStringConvertible {
    case notFound(String)
    /// The data rules forbid it, e.g. deleting a session that a note still points at.
    case rule(String)
    /// The file changed elsewhere since it was read.
    case conflict(String)

    public var description: String {
        switch self {
        case .notFound(let s), .rule(let s), .conflict(let s): s
        }
    }

    init(_ e: ModelError) {
        switch e {
        case .notFound(let s): self = .notFound(s)
        case .rule(let s): self = .rule(s)
        }
    }
}

/// A file the action created, changed, removed or moved, relative to the GIST folder. `item` names the entry inside a
/// JSON file (`exams/<id>`); nil means the file as a whole.
public struct Change: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case added, changed, removed, moved }
    public var kind: Kind
    public var path: String
    public var item: String?
    public var to: String?
    /// For a changed entry, each field that changed, with its value before and after (nil: absent).
    public var fields: [Field]?

    public struct Field: Codable, Sendable, Equatable {
        public var name: String
        public var before: JSONValue?
        public var after: JSONValue?

        public init(name: String, before: JSONValue?, after: JSONValue?) {
            (self.name, self.before, self.after) = (name, before, after)
        }
    }

    public init(_ kind: Kind, _ path: String, item: String? = nil, to: String? = nil, fields: [Field]? = nil) {
        self.kind = kind
        self.path = path
        self.item = item
        self.to = to
        self.fields = fields
    }
}

extension [Change] {
    /// One entry per file and item, for an action that touches the same item more than once (or several actions run
    /// on one context): added stays added, a later removal wins, and each field keeps its first before and last after.
    public func coalesced() -> [Change] {
        var out: [Change] = []
        var at: [String: Int] = [:]
        for c in self {
            let key = c.path + "\u{0}" + (c.item ?? "") + "\u{0}" + (c.to ?? "")
            guard let i = at[key] else { at[key] = out.count; out.append(c); continue }
            var m = out[i]
            if c.kind == .removed { m.kind = m.kind == .added ? .changed : .removed }
            if let fields = c.fields {
                var merged = m.fields ?? []
                for f in fields {
                    if let j = merged.firstIndex(where: { $0.name == f.name }) { merged[j].after = f.after } else { merged.append(f) }
                }
                m.fields = merged.filter { $0.before != $0.after }
            }
            out[i] = m
        }
        return out
    }
}

/// All reads and writes of an action go through here, so a dry run is the same code with the writes left out.
public final class ActionContext {
    public let gist: GISTStore
    public let device: DeviceID
    public let now: Date
    public let calendar: Calendar
    public let dryRun: Bool
    public private(set) var changes: [Change] = []
    /// The item the action made, e.g. a new session or note; the app opens it.
    public private(set) var made: UUID?
    /// Course files saved by the action, so the app can show them without reading every course again.
    public private(set) var savedCourses: [UUID: StoredDocument<CourseFile>] = [:]
    /// True when something other than a course file changed: the app then reads everything again.
    public private(set) var needsReload = false
    public private(set) var loggedCourses: Set<UUID> = []
    /// What an import skipped or wants checked, for the person reading the result.
    public private(set) var notes: [String] = []

    private var stores: [UUID: CourseStore]?
    private var courseDocs: [UUID: StoredDocument<CourseFile>] = [:]
    // Read once and kept, so an action that edits two files checks and previews the second against the first's edit.
    private var transcriptDoc: StoredDocument<Transcript>?
    private var catalogDoc: StoredDocument<Catalog>?
    private var settingsDoc: StoredDocument<Settings>?

    /// `courses` is the app's map of course folders; the CLI leaves it out and the folder is scanned when needed.
    public init(gist: GISTStore, device: DeviceID, now: Date = .now, calendar: Calendar = .current, dryRun: Bool = false,
                courses: [UUID: CourseStore]? = nil) {
        self.gist = gist
        self.device = device
        self.now = now
        self.calendar = calendar
        self.dryRun = dryRun
        self.stores = courses
    }

    /// Runs the action against documents the caller already holds, as the app does to enable its buttons. Only for a
    /// dry run: these are bare models, without the unknown keys a save must keep.
    public func preload(courses: [StoredDocument<CourseFile>], transcript: Transcript, catalog: Catalog, settings: Settings) {
        precondition(dryRun, "preloaded documents are never saved")
        for doc in courses { courseDocs[doc.model.course.id] = doc }
        transcriptDoc = StoredDocument(new: transcript)
        catalogDoc = StoredDocument(new: catalog)
        settingsDoc = StoredDocument(new: settings)
    }

    // MARK: Reads

    public func store(_ course: UUID) throws -> CourseStore {
        guard let store = try courseStores()[course] else { throw ActionError.notFound("과목을 찾지 못했습니다: \(course)") }
        return store
    }

    private func courseStores() throws -> [UUID: CourseStore] {
        if let stores { return stores }
        let found = Dictionary(try gist.courseStores().compactMap { s in (try? s.load()).map { ($0.model.course.id, s) } },
                               uniquingKeysWith: { a, _ in a })
        stores = found
        return found
    }

    public func hasFolder(_ course: UUID) -> Bool { (try? store(course)) != nil }

    /// Read from disk once per action: another device or the app may have changed the file since it was shown.
    public func file(_ course: UUID) throws -> CourseFile {
        try document(course).model
    }

    public func transcript() throws -> Transcript { try transcriptDocument().model }

    public func catalog() throws -> Catalog { try catalogDocument().model }

    public func settings() throws -> Settings { try settingsDocument().model }

    // Only a missing file starts empty; one that fails to read must not be replaced.
    private func transcriptDocument() throws -> StoredDocument<Transcript> {
        if let transcriptDoc { return transcriptDoc }
        let doc = FileManager.default.fileExists(atPath: gist.transcriptURL.path) ? try gist.loadTranscript() : StoredDocument(new: Transcript())
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

    /// The display name of any item: a course, a semester, a catalog row, or anything in a course file.
    public func name(of id: UUID) -> String? {
        if let n = (try? transcript())?.name(of: id) ?? (try? catalog())?.name(of: id) { return n }
        for course in ((try? courseStores()) ?? [:]).keys {
            if let n = (try? file(course))?.name(of: id) { return n }
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

    /// Creates a note in the course's Notes folder and returns its id (known before writing, so a dry run has it too).
    @discardableResult
    public func createNote(_ course: UUID, title: String, meta: NoteMeta, body: String?) throws -> UUID? {
        let store = try store(course)
        let planned = relative(store.url.appending(path: CourseFolder.notes.rawValue).appending(path: "\(title).md"))
        if let id = meta.id, try store.notes().contains(where: { $0.meta.id == id }) { throw ActionError.rule("이미 쓰는 노트 ID입니다: \(id)") }
        guard !dryRun else {
            record(Change(.added, planned))
            return meta.id
        }
        let note = try store.createNote(title: title, meta: meta, body: body)
        record(Change(.added, relative(note.url)))
        return note.meta.id
    }

    public func editTranscript(_ change: (inout Transcript) throws -> Void) throws {
        var doc = try transcriptDocument()
        let before = doc.model
        do { try change(&doc.model) } catch let e as ModelError { throw ActionError(e) }
        guard doc.model != before else { return }
        let catalog = try catalog()
        try refuseNewViolation(before, doc.model, World(catalog: catalog))
        try refuseBreakingCourses(World(catalog: catalog, transcript: before), World(catalog: catalog, transcript: doc.model))
        transcriptDoc = doc
        changes += diff(before, doc.model, path: relative(gist.transcriptURL))
        needsReload = true
        if !dryRun { try gist.save(doc) }
    }

    public func editCatalog(_ change: (inout Catalog) throws -> Void) throws {
        var doc = try catalogDocument()
        let before = doc.model
        do { try change(&doc.model) } catch let e as ModelError { throw ActionError(e) }
        guard doc.model != before else { return }
        try refuseNewViolation(before, doc.model, World())
        let transcript = try transcript()
        if let v = Transcript.model.newViolation(transcript, in: World(catalog: before), transcript, in: World(catalog: doc.model)) {
            throw ActionError.rule("다른 파일이 쓰고 있어 바꿀 수 없습니다: \(v.message)")
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

    /// A save may not add a violation; ones the file already had stay allowed, so a broken file can be fixed in steps.
    private func refuseNewViolation<D: Document>(_ before: D, _ after: D, _ world: World) throws {
        if let v = D.model.newViolation(before, in: world, after, in: world) { throw ActionError.rule(v.message) }
    }

    /// Course files point into the catalog and the transcript, so changing those can break a course file it doesn't touch.
    private func refuseBreakingCourses(_ before: World, _ after: World) throws {
        for course in try courseStores().keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let file = try file(course)
            if let v = CourseFile.model.newViolation(file, in: before, file, in: after) {
                throw ActionError.rule("다른 파일이 쓰고 있어 바꿀 수 없습니다: \(v.message)")
            }
        }
    }

    public func log<E: LogEvent>(_ event: E, course: UUID, at date: Date? = nil) throws {
        let store = try store(course)
        changes.append(Change(.changed, relative(store.log.folder.appending(path: device.uuidString).appendingPathExtension(StandardLayout.logExtension)), item: E.type))
        loggedCourses.insert(course)
        if !dryRun { try store.log.append(event, device: device, at: date ?? now) }
    }

    /// A file system change outside the JSON files (a folder, a note, a moved file). `perform` runs only for real.
    @discardableResult
    public func io<T>(_ change: Change, _ perform: () throws -> T) throws -> T? {
        changes.append(change)
        needsReload = needsReload || change.path.hasSuffix("/") || change.kind == .moved
        return dryRun ? nil : try perform()
    }

    public func record(_ change: Change) { changes.append(change) }

    public func made(_ id: UUID) { made = id }

    public func note(_ line: String) { notes.append(line) }

    /// Forces the app to read everything again, e.g. after a course folder is renamed.
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

/// Per entry: arrays of objects with an `id` report each added, changed or removed entry, other keys the key itself.
/// Who edited and when are left out, since every edit stamps them.
func diff<M: Encodable>(_ before: M, _ after: M, path: String) -> [Change] {
    func json(_ m: M) -> [String: JSONValue] {
        guard let data = try? JSONEncoder().encode(m), case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: data) else { return [:] }
        return o
    }
    func stripped(_ v: JSONValue?) -> JSONValue? {
        guard case .object(var o)? = v else { return v }
        o["updatedAt"] = nil
        o["updatedBy"] = nil
        return .object(o)
    }
    func byID(_ v: JSONValue?) -> [String: JSONValue]? {
        guard case .array(let items)? = v else { return nil }
        var result: [String: JSONValue] = [:]
        for item in items {
            guard case .string(let id)? = item["id"] else { return nil }
            result[id] = item
        }
        return result
    }
    /// Top-level fields of two versions of one object; anything else is one field named `name`.
    func fields(_ name: String, _ old: JSONValue?, _ new: JSONValue?) -> [Change.Field] {
        guard case .object(let o)? = stripped(old), case .object(let n)? = stripped(new) else { return [Change.Field(name: name, before: old, after: new)] }
        return Set(o.keys).union(n.keys).sorted().filter { o[$0] != n[$0] }.map { Change.Field(name: $0, before: o[$0], after: n[$0]) }
    }
    let (a, b) = (json(before), json(after))
    var changes: [Change] = []
    for key in Set(a.keys).union(b.keys).sorted() where stripped(a[key]) != stripped(b[key]) {
        if let old = byID(a[key]) ?? (a[key] == nil ? [:] : nil), let new = byID(b[key]) ?? (b[key] == nil ? [:] : nil) {
            for id in Set(old.keys).union(new.keys).sorted() where stripped(old[id]) != stripped(new[id]) {
                let kind: Change.Kind = old[id] == nil ? .added : new[id] == nil ? .removed : .changed
                changes.append(Change(kind, path, item: "\(key)/\(id)", fields: kind == .changed ? fields(key, old[id], new[id]) : nil))
            }
        } else {
            changes.append(Change(.changed, path, item: key, fields: fields(key, a[key], b[key])))
        }
    }
    return changes
}
