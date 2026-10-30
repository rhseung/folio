import FolioDomain
import Foundation

#if os(macOS)
/// Daily backups (docs/SPEC.md "백업"). Nothing here writes inside the GIST folder.
/// On the GIST folder's own volume a backup is an APFS clone of the whole folder, which costs disk only for
/// files changed since. A clone can't cross volumes, and copying every lecture daily would cost gigabytes, so
/// elsewhere it falls back to zipping GIST/.folio and each course's Notes, Ink and .folio.
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
        public var isClone: Bool { url.pathExtension != BackupStore.zipExtension }
    }

    public struct Created: Sendable, Equatable {
        public var url: URL
        /// Files only in iCloud, left out rather than downloaded.
        public var skipped: Int
    }

    public let gist: GISTStore
    public let folder: URL
    var isEvicted: @Sendable (String) -> Bool = { BackupStore.isDataless($0) }

    static let prefix = "Folio-"
    static let zipExtension = "zip"

    public init(gist: GISTStore, folder: URL) {
        self.gist = gist
        self.folder = folder
    }

    /// A backup folder inside the GIST folder would sync to iCloud and be backed up into itself.
    func checkFolder() throws {
        let root = gist.url.standardizedFileURL.path + "/"
        guard !(folder.standardizedFileURL.path + "/").hasPrefix(root) else { throw Failure.insideGIST(folder.path) }
    }

    public var clones: Bool {
        var probe = folder.standardizedFileURL
        while !FileManager.default.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
        guard let a = try? gist.url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier,
              let b = try? probe.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else { return false }
        return a.isEqual(b)
    }

    public func target(for day: LocalDate) -> URL { target(for: day, clone: clones) }

    func target(for day: LocalDate, clone: Bool) -> URL {
        folder.appending(path: "\(Self.prefix)\(day)" + (clone ? "" : ".\(Self.zipExtension)"))
    }

    public func archives() -> [Archive] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.compactMap { name in
            guard name.hasPrefix(Self.prefix) else { return nil }
            var stem = name.dropFirst(Self.prefix.count)
            if stem.hasSuffix("." + Self.zipExtension) { stem = stem.dropLast(Self.zipExtension.count + 1) }
            guard let day = LocalDate(String(stem)) else { return nil }
            return Archive(url: folder.appending(path: name), day: day)
        }
        .sorted { $0.day > $1.day }
    }

    @discardableResult
    public func backUp(today: LocalDate, dailyDays: Int, calendar: Calendar) throws -> Created {
        try backUp(today: today, dailyDays: dailyDays, calendar: calendar, clone: clones)
    }

    func backUp(today: LocalDate, dailyDays: Int, calendar: Calendar, clone: Bool) throws -> Created {
        try checkFolder()
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = target(for: today, clone: clone)
        // Build next to the target and swap in, so a failed run never leaves a half-written backup under the real name.
        let partial = folder.appending(path: ".\(UUID().uuidString).partial")
        defer { try? fm.removeItem(at: partial) }
        var skipped = 0
        if clone {
            try fm.createDirectory(at: partial, withIntermediateDirectories: true)
            skipped = try Self.cloneTree(gist.url.path(percentEncoded: false), into: partial.path(percentEncoded: false), skip: isEvicted)
        } else {
            try zipNotes(to: partial)
        }
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: partial, to: target)

        let keep = BackupRetention.keep(archives().map(\.day), today: today, dailyDays: dailyDays, calendar: calendar)
        for old in archives() where !keep.contains(old.day) { try fm.removeItem(at: old.url) }
        return Created(url: target, skipped: skipped)
    }

    /// Path strings with mkdir and copyfile, not FileManager: its URL and path APIs rewrite names to NFD, so a
    /// Korean file name saved as NFC would come back under different bytes.
    /// Item by item instead of one recursive copy, so a file iCloud has evicted is skipped rather than
    /// downloaded: fetching gigabytes of lectures would stall the backup and refill the disk.
    static func cloneTree(_ source: String, into target: String, skip: (String) -> Bool = { _ in false }) throws -> Int {
        var skipped = 0
        for name in try FileManager.default.contentsOfDirectory(atPath: source) {
            let from = source + "/" + name, to = target + "/" + name
            var info = stat()
            guard lstat(from, &info) == 0 else { throw posixFailure(from) }
            if info.st_mode & S_IFMT == S_IFDIR {
                guard mkdir(to, 0o755) == 0 else { throw posixFailure(to) }
                skipped += try cloneTree(from, into: to, skip: skip)
            } else if skip(from) {
                skipped += 1
            } else {
                // COPYFILE_CLONE falls back to a plain copy where cloning isn't possible.
                guard copyfile(from, to, nil, copyfile_flags_t(COPYFILE_CLONE | COPYFILE_NOFOLLOW)) == 0 else { throw posixFailure(from) }
            }
        }
        return skipped
    }

    static func posixFailure(_ path: String) -> Failure {
        .tool("\(path): \(String(cString: strerror(errno)))")
    }

    private func zipNotes(to archive: URL) throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appending(path: "folio-backup-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        let root = staging.appending(path: gist.url.lastPathComponent)
        try copyIfPresent(gist.url.appending(path: StandardLayout.metadataFolder), to: root.appending(path: StandardLayout.metadataFolder))
        for course in try gist.courseStores() {
            for sub in [CourseFolder.notes, .ink, .metadata] {
                try copyIfPresent(course.url.appending(path: sub.rawValue), to: root.appending(path: relative(course)).appending(path: sub.rawValue))
            }
        }
        try Self.ditto(["-c", "-k", "--sequesterRsrc", "--keepParent", root.path, archive.path])
    }

    /// Copies one course out of `archive` into `target`, a new folder outside GIST: the whole course folder from
    /// a clone, its Notes, Ink and .folio from a zip. Restoring never overwrites; the user compares and copies back by hand.
    public func restore(course: CourseStore, from archive: Archive, to target: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: target.path) else { throw Failure.targetExists(target.path) }
        let scratch = fm.temporaryDirectory.appending(path: "folio-restore-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: scratch) }
        let source: URL
        if archive.isClone {
            source = archive.url.appending(path: relative(course))
        } else {
            try Self.ditto(["-x", "-k", archive.url.path, scratch.path])
            source = scratch.appending(path: gist.url.lastPathComponent).appending(path: relative(course))
        }
        guard fm.fileExists(atPath: source.path) else { throw Failure.courseNotInBackup(relative(course)) }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let to = target.path(percentEncoded: false)
        guard mkdir(to, 0o755) == 0 else { throw Self.posixFailure(to) }
        _ = try Self.cloneTree(source.path(percentEncoded: false), into: to)
    }

    private func relative(_ course: CourseStore) -> String {
        String(course.url.standardizedFileURL.path.dropFirst(gist.url.standardizedFileURL.path.count + 1))
    }

    private func copyIfPresent(_ source: URL, to target: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: target)
    }

    static func isDataless(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_flags & UInt32(SF_DATALESS) != 0
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
