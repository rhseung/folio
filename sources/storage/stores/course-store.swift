import CryptoKit
import FolioDomain
import Foundation

public struct CourseStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func fileURL(_ coursePath: String) -> URL { url.appending(path: coursePath) }

    var metadataURL: URL { url.appending(path: StandardLayout.metadataFolder) }
    public var courseFileURL: URL { metadataURL.appending(path: StandardLayout.courseFile) }
    public var log: EventLog { EventLog(folder: metadataURL.appending(path: StandardLayout.logsFolder)) }

    @discardableResult
    public func ensureFolder(assignmentTitle: String) throws -> String? {
        guard let (kind, number) = AssignmentKind.parse(title: assignmentTitle) else { return nil }
        return try ensure("\(CourseFolder.assignments.rawValue)/\(kind.folderName(number))")
    }

    private func ensure(_ path: String) throws -> String {
        try FileManager.default.createDirectory(at: url.appending(path: path), withIntermediateDirectories: true)
        return path
    }

    public func quizURL(unit: UUID) -> URL {
        metadataURL.appending(path: StandardLayout.quizzesFolder).appending(path: "\(unit.uuidString).json")
    }

    public func loadQuiz(unit: UUID) throws -> StoredDocument<QuizFile> {
        let url = quizURL(unit: unit)
        return FileManager.default.fileExists(atPath: url.path)
            ? try StoredDocument.read(from: url) : StoredDocument(new: QuizFile(unitId: unit))
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

    // iCloud가 남긴 충돌 사본을 지금 문서에 합쳐 쓰고 해결됨으로 표시한다. 사본은 지우지 않는다. 합치기가 같은 항목에서
    // 잘못 고른 쪽이 있어도 파일의 다른 버전에서 되찾을 수 있게 하기 위해서다. 아직 내려받지 않아 읽지 못한 사본은
    // 남겨 두고 다음에 다시 합친다. 합친 사본이 있으면 true다.
    @discardableResult
    public func resolveConflicts() throws -> Bool {
        let versions = CoordinatedFile.unresolvedConflicts(courseFileURL)
        guard !versions.isEmpty else { return false }
        var doc = try load()
        var merged: [NSFileVersion] = []
        for version in versions {
            guard let other = try? StoredDocument<CourseFile>.read(from: version.url) else { continue }
            doc.model = doc.model.merged(with: other.model)
            merged.append(version)
        }
        guard !merged.isEmpty else { return false }
        try save(doc)
        for version in merged { version.isResolved = true }
        return true
    }

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
