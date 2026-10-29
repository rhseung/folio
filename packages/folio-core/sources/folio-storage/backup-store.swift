import FolioDomain
import Foundation

#if os(macOS)
/// Daily archives of the files that can't be fetched again: GIST/.folio and each course's Notes, Ink and
/// .folio (docs/SPEC.md "백업"). Lectures and assignments are left out. Nothing here writes inside the GIST folder.
public struct BackupStore: Sendable {
    public enum Failure: Error, Equatable {
        case insideGIST(String)
        case courseNotInBackup(String)
        case targetExists(String)
        case tool(String)
    }

    public struct Archive: Sendable, Equatable {
        public var url: URL
        public var day: LocalDate
    }

    public let gist: GISTStore
    public let folder: URL

    static let prefix = "Folio-"
    static let fileExtension = "zip"

    public init(gist: GISTStore, folder: URL) {
        self.gist = gist
        self.folder = folder
    }

    /// A backup folder inside the GIST folder would sync to iCloud and be backed up into itself.
    func checkFolder() throws {
        let root = gist.url.standardizedFileURL.path + "/"
        guard !(folder.standardizedFileURL.path + "/").hasPrefix(root) else { throw Failure.insideGIST(folder.path) }
    }

    public func archives() -> [Archive] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name in
            guard name.hasPrefix(Self.prefix), name.hasSuffix("." + Self.fileExtension),
                  let day = LocalDate(String(name.dropFirst(Self.prefix.count).dropLast(Self.fileExtension.count + 1))) else { return nil }
            return Archive(url: folder.appending(path: name), day: day)
        }
        .sorted { $0.day > $1.day }
    }

    @discardableResult
    public func backUp(today: LocalDate, dailyDays: Int, calendar: Calendar) throws -> URL {
        try checkFolder()
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appending(path: "folio-backup-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        let root = staging.appending(path: gist.url.lastPathComponent)
        try copyIfPresent(gist.url.appending(path: StandardLayout.metadataFolder), to: root.appending(path: StandardLayout.metadataFolder))
        let gistPath = gist.url.standardizedFileURL.path
        for course in try gist.courseStores() {
            let relative = String(course.url.standardizedFileURL.path.dropFirst(gistPath.count + 1))
            for sub in [CourseFolder.notes, .ink, .metadata] {
                try copyIfPresent(course.url.appending(path: sub.rawValue), to: root.appending(path: relative).appending(path: sub.rawValue))
            }
        }

        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: "\(Self.prefix)\(today).\(Self.fileExtension)")
        // Zip next to the target and swap in, so a failed run never leaves a half-written archive under the real name.
        let partial = folder.appending(path: ".\(UUID().uuidString).partial")
        defer { try? fm.removeItem(at: partial) }
        try Self.ditto(["-c", "-k", "--sequesterRsrc", "--keepParent", root.path, partial.path])
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: partial, to: target)

        let keep = BackupRetention.keep(archives().map(\.day), today: today, dailyDays: dailyDays, calendar: calendar)
        for old in archives() where !keep.contains(old.day) { try fm.removeItem(at: old.url) }
        return target
    }

    /// Extracts one course's Notes, Ink and .folio from `archive` into `target`, a new folder outside GIST.
    /// Restoring never overwrites; the user compares and copies back by hand.
    public func restore(course: CourseStore, from archive: Archive, to target: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: target.path) else { throw Failure.targetExists(target.path) }
        let gistPath = gist.url.standardizedFileURL.path
        let relative = String(course.url.standardizedFileURL.path.dropFirst(gistPath.count + 1))
        let scratch = fm.temporaryDirectory.appending(path: "folio-restore-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: scratch) }
        try Self.ditto(["-x", "-k", archive.url.path, scratch.path])
        let source = scratch.appending(path: gist.url.lastPathComponent).appending(path: relative)
        guard fm.fileExists(atPath: source.path) else { throw Failure.courseNotInBackup(relative) }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: target)
    }

    private func copyIfPresent(_ source: URL, to target: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: target)
    }

    static func ditto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw Failure.tool(String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        }
    }
}
#endif
