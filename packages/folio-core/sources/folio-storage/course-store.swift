import FolioDomain
import CryptoKit
import Foundation

/// The GIST root folder.
public struct GISTStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// A path stored relative to the course folder (materials, recordings), as a file URL.
    public func fileURL(_ coursePath: String) -> URL { url.appending(path: coursePath) }

    var metadataURL: URL { url.appending(path: StandardLayout.metadataFolder) }
    public var transcriptURL: URL { metadataURL.appending(path: StandardLayout.transcriptFile) }
    public var catalogURL: URL { metadataURL.appending(path: StandardLayout.catalogFile) }

    public var settingsURL: URL { metadataURL.appending(path: StandardLayout.settingsFile) }

    /// Defaults when settings.json doesn't exist yet.
    public func loadSettings() throws -> StoredDocument<Settings> {
        FileManager.default.fileExists(atPath: settingsURL.path) ? try StoredDocument.read(from: settingsURL) : StoredDocument(new: Settings())
    }

    public func loadCatalog() throws -> StoredDocument<Catalog> {
        try StoredDocument.read(from: catalogURL)
    }

    public func save(_ catalog: StoredDocument<Catalog>) throws {
        try catalog.write(to: catalogURL)
    }

    public func save(_ settings: StoredDocument<Settings>) throws {
        try settings.write(to: settingsURL)
    }

    /// Every course with a grade record: folderless ones from transcript.json plus each course.json.
    public func allCourses() throws -> [Course] {
        try loadTranscript().model.courses + courseStores().map { try $0.load().model.course }
    }

    /// Writes a Notion import. Never overwrites: transcript.json and catalog.json must not exist yet,
    /// and course folders that already have a course.json are skipped and returned.
    public func write(_ result: NotionImportResult) throws -> [String] {
        for existing in [transcriptURL, catalogURL] where FileManager.default.fileExists(atPath: existing.path) {
            throw MoveJournal.Failure.targetExists(existing.lastPathComponent)
        }
        try StoredDocument(new: result.catalog).write(to: catalogURL)
        try StoredDocument(new: result.transcript).write(to: transcriptURL)
        var skipped: [String] = []
        for (folder, file) in result.courseFiles.sorted(by: { $0.key < $1.key }) {
            let store = CourseStore(url: url.appending(path: folder))
            if FileManager.default.fileExists(atPath: store.courseFileURL.path) {
                skipped.append(folder)
            } else {
                try store.save(StoredDocument(new: file))
            }
        }
        return skipped
    }

    public func readTree() throws -> FolderTree {
        try FolderTree(contentsOf: url)
    }

    /// Copies the whole GIST folder to `<directory>/GIST-<timestamp>` outside iCloud. Required before cleanup.
    public func backup(into directory: URL, now: Date) throws -> URL {
        let stamp = now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let target = directory.appending(path: "GIST-\(stamp)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: url, to: target)
        return target
    }

    public func layoutIssues() throws -> [LayoutIssue] {
        LayoutCheck.issues(in: try readTree())
    }

    public func loadTranscript() throws -> StoredDocument<Transcript> {
        try StoredDocument.read(from: transcriptURL)
    }

    public func save(_ transcript: StoredDocument<Transcript>) throws {
        try transcript.write(to: transcriptURL)
    }

    /// Folders under semester folders that have a course.json.
    /// Lists two levels only; reading the whole tree (thousands of files) would make every app launch slow.
    public func courseStores() throws -> [CourseStore] {
        let fm = FileManager.default
        return try fm.contentsOfDirectory(atPath: url.path)
            .filter { SemesterFolder(name: $0) != nil }
            .sorted()
            .flatMap { semester in
                try fm.contentsOfDirectory(atPath: url.appending(path: semester).path).sorted()
                    .map { CourseStore(url: url.appending(path: semester).appending(path: $0)) }
            }
            .filter { fm.fileExists(atPath: $0.courseFileURL.path) }
    }
}

/// One course folder.
public struct CourseStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// A path stored relative to the course folder (materials, recordings), as a file URL.
    public func fileURL(_ coursePath: String) -> URL { url.appending(path: coursePath) }

    var metadataURL: URL { url.appending(path: StandardLayout.metadataFolder) }
    public var courseFileURL: URL { metadataURL.appending(path: StandardLayout.courseFile) }
    public var log: EventLog { EventLog(folder: metadataURL.appending(path: StandardLayout.logsFolder)) }

    /// Creates the standard folder for an assignment or exam (docs/SPEC.md "구조 유지"). Creating is not moving,
    /// so it needs no approval. Returns the course-relative path, or nil when the item has no standard folder.
    @discardableResult
    public func ensureFolder(assignmentTitle: String) throws -> String? {
        guard let (kind, number) = AssignmentKind.parse(title: assignmentTitle) else { return nil }
        return try ensure("\(CourseFolder.assignments.rawValue)/\(kind.folderName(number))")
    }

    @discardableResult
    public func ensureFolder(exam: Exam, among exams: [Exam]) throws -> String? {
        guard let path = MaterialIntake.folder(of: exam, among: exams) else { return nil }
        return try ensure(path)
    }

    private func ensure(_ path: String) throws -> String {
        try FileManager.default.createDirectory(at: url.appending(path: path), withIntermediateDirectories: true)
        return path
    }

    public func quizURL(unit: UUID) -> URL {
        metadataURL.appending(path: StandardLayout.quizzesFolder).appending(path: "\(unit.uuidString).json")
    }

    /// An empty file for units without cards yet.
    public func loadQuiz(unit: UUID) throws -> StoredDocument<QuizFile> {
        let url = quizURL(unit: unit)
        return FileManager.default.fileExists(atPath: url.path) ? try StoredDocument.read(from: url) : StoredDocument(new: QuizFile(unitId: unit))
    }

    public func save(_ quiz: StoredDocument<QuizFile>) throws {
        try quiz.write(to: quizURL(unit: quiz.model.unitId))
    }

    public func load() throws -> StoredDocument<CourseFile> {
        try StoredDocument.read(from: courseFileURL)
    }

    public func save(_ document: StoredDocument<CourseFile>) throws {
        try document.write(to: courseFileURL)
    }

    /// Re-links materials to files on disk and registers new ones. Does not move or rename anything.
    public func refreshMaterials(in file: inout CourseFile, device: DeviceID, now: Date) throws {
        let scanned = ScannedEntry.materials(in: try FolderTree(contentsOf: url, depth: IndexRules.courseFolderDepth))
        file.materials = try MaterialTracking.reconcile(
            file.materials, with: scanned, folderRoles: file.course.folderRoles,
            io: trackingIO, device: device, now: now
        )
    }

    var trackingIO: TrackingIO {
        let root = url.standardizedFileURL
        let rootPath = root.path(percentEncoded: false)
        return TrackingIO(
            resolveBookmark: { material in
                guard let data = material.bookmark else { return nil }
                var stale = false
                guard let resolved = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
                let path = resolved.standardizedFileURL.path(percentEncoded: false)
                guard path.hasPrefix(rootPath) else { return nil }
                return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            },
            hash: { try FileHash.sha256(of: root.appending(path: $0)) },
            makeBookmark: { try? root.appending(path: $0).bookmarkData() }
        )
    }
}

enum FileHash {
    /// Streams the file so large textbooks don't load into memory. Nil if iCloud hasn't downloaded it yet,
    /// because reading would force a download (docs/SPEC.md: download only when opened).
    static func sha256(of url: URL) throws -> String? {
        let status = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        if let status, status != .current { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
