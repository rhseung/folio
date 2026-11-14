import CryptoKit
import FolioDomain
import Foundation

public struct GISTStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func fileURL(_ coursePath: String) -> URL { url.appending(path: coursePath) }

    var metadataURL: URL { url.appending(path: StandardLayout.metadataFolder) }
    public var transcriptURL: URL { metadataURL.appending(path: StandardLayout.transcriptFile) }
    public var catalogURL: URL { metadataURL.appending(path: StandardLayout.catalogFile) }

    public var settingsURL: URL { metadataURL.appending(path: StandardLayout.settingsFile) }

    public func loadSettings() throws -> StoredDocument<Settings> {
        FileManager.default.fileExists(atPath: settingsURL.path)
            ? try StoredDocument.read(from: settingsURL) : StoredDocument(new: Settings())
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

    public func allCourses() throws -> [Course] {
        try courseStores().map { try $0.load().model.course }
    }

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

    public func cleanupPlan(skip: Set<String> = [], labs: [String: [String: Int]] = [:], labWeeks: [String: [Int: Int]] = [:]) throws
        -> CleanupPlan
    {
        let root = url.standardizedFileURL.path
        var exams: [String: [Exam]] = [:]
        for store in try courseStores() {
            guard let file = try? store.load().model else { continue }
            exams[String(store.url.standardizedFileURL.path.dropFirst(root.count + 1))] = file.exams
        }
        return CleanupPlanner.plan(
            try readTree(), skip: skip, labs: labs, labWeeks: labWeeks,
            selfMade: try MoveJournal.selfMadePaths(in: url), exams: exams)
    }

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

    public func courseStores() throws -> [CourseStore] {
        let fm = FileManager.default
        func folders(_ path: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: url.appending(path: path).path)) ?? []).filter { !$0.hasPrefix(".") }.sorted().map {
                "\(path)/\($0)"
            }
        }
        let terms = try fm.contentsOfDirectory(atPath: url.path).filter { SemesterFolder(name: $0) != nil }.sorted()
        return (terms + folders(StandardLayout.creditedFolder))
            .flatMap(folders)
            .map { CourseStore(url: url.appending(path: $0)) }
            .filter { fm.fileExists(atPath: $0.courseFileURL.path) }
    }
}
