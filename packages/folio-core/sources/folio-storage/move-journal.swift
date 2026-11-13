import FolioDomain
import Foundation

extension CleanupPlan: StoredModel {
    public static let schemaVersion = 1
}

/// One line of `.folio/moves.jsonl` (GIST root). Paths are relative to the GIST root.
/// Every filesystem change the app makes is journaled right after it happens, so even a batch that
/// failed halfway can be undone.
public struct MoveRecord: Codable, Sendable, Equatable {
    public enum Op: String, Codable, Sendable {
        case move
        case makeFolder
        case removeFolder
        /// `.DS_Store` and Office lock files removed so an emptied folder can go. Not restored by undo.
        case removeJunk
        /// A course schema v1 kept in transcript.json got its folder's course.json (`to`). Undo puts it back.
        case fileCourse
        /// Undo of `fileCourse`: the course.json in `from` went back to transcript.json.
        case unfileCourse
    }

    public var schemaVersion: Int
    public var id: UUID
    public var batch: UUID
    public var undoOf: UUID?
    public var at: Date
    public var device: DeviceID
    public var op: Op
    public var from: String?
    public var to: String?
}

public enum MoveJournal {
    public enum Failure: Error, Equatable {
        case sourceMissing(String)
        case targetExists(String)
        case unknownBatch(UUID)
        case outsideGIST(String)
        /// The course has sessions, notes or other data since it was filed, which transcript.json can't hold.
        case courseChanged(String)
    }

    static func url(in gist: URL) -> URL {
        gist.appending(path: StandardLayout.metadataFolder).appending(path: StandardLayout.movesFile)
    }

    public static func records(in gist: URL) throws -> [MoveRecord] {
        let url = url(in: gist)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try CoordinatedFile.read(url)
            .split(separator: UInt8(ascii: "\n"))
            .compactMap { try? JSONFormat.decoder.decode(MoveRecord.self, from: Data($0)) }
    }

    /// Runs `moves` in order, then removes `removals` if they are still empty, and returns the batch ID for `undo`.
    /// Checks every source and target first, so a stale plan fails before anything moves.
    @discardableResult
    public static func apply(_ moves: [PlannedMove], removing removals: [String] = [], in gist: URL, device: DeviceID, now: Date) throws
        -> UUID
    {
        let fm = FileManager.default
        // Lexical, since a target doesn't exist yet: `a/../../x` must not reach past the GIST folder.
        let root = gist.standardizedFileURL.path + "/"
        for path in moves.flatMap({ [$0.from, $0.to] }) + removals
        where !gist.appending(path: path).standardizedFileURL.path.hasPrefix(root) {
            throw Failure.outsideGIST(path)
        }
        for move in moves {
            guard fm.fileExists(atPath: gist.appending(path: move.from).path) else { throw Failure.sourceMissing(move.from) }
            guard !fm.fileExists(atPath: gist.appending(path: move.to).path) else { throw Failure.targetExists(move.to) }
        }
        let writer = Writer(gist: gist, batch: UUID(), undoOf: nil, device: device, now: now)
        for move in moves {
            try writer.makeParents(of: move.to)
            try writer.move(move.from, to: move.to)
        }
        for path in removals { try writer.removeFolderIfEmpty(path) }
        try writer.removeEmptied(Set((moves.map(\.from) + removals).map { ($0 as NSString).deletingLastPathComponent }))
        return writer.batch
    }

    /// GIST-relative paths the journal shows were taken out of an `Exam Review` folder, where they are now.
    public static func selfMadePaths(in gist: URL) throws -> Set<String> {
        CleanupPlanner.selfMade(
            moves: try records(in: gist).compactMap { r in
                guard r.op == .move, let from = r.from, let to = r.to else { return nil }
                return (from, to)
            })
    }

    /// Writes each course into `folder/.folio/course.json` under the same id, making the folders it needs. The caller
    /// then takes the courses out of transcript.json; `undo` of the batch puts them back.
    @discardableResult
    public static func file(_ courses: [(course: Course, folder: String)], in gist: URL, device: DeviceID, now: Date) throws -> UUID {
        let root = gist.standardizedFileURL.path + "/"
        for (_, folder) in courses {
            guard gist.appending(path: folder).standardizedFileURL.path.hasPrefix(root) else { throw Failure.outsideGIST(folder) }
            guard !FileManager.default.fileExists(atPath: gist.appending(path: folder).path) else { throw Failure.targetExists(folder) }
        }
        let writer = Writer(gist: gist, batch: UUID(), undoOf: nil, device: device, now: now)
        for (course, folder) in courses {
            let store = CourseStore(url: gist.appending(path: folder))
            try writer.makeParents(of: writer.relative(store.courseFileURL))
            try store.save(StoredDocument(new: CourseFile(course: course)))
            try writer.record(.fileCourse, to: folder)
        }
        return writer.batch
    }

    @discardableResult
    public static func undo(batch: UUID, in gist: URL, device: DeviceID, now: Date) throws -> UUID {
        let records = try records(in: gist).filter { $0.batch == batch }
        guard !records.isEmpty else { throw Failure.unknownBatch(batch) }
        let writer = Writer(gist: gist, batch: UUID(), undoOf: batch, device: device, now: now)
        for record in records.reversed() {
            switch record.op {
            case .move: try writer.move(record.to!, to: record.from!)
            // Files may have been added to a folder the batch made; those stay, and so does the folder.
            case .makeFolder: try writer.removeFolderIfEmpty(record.to!)
            case .removeFolder: try writer.makeFolder(record.from!)
            case .removeJunk, .unfileCourse: break
            case .fileCourse: try writer.unfileCourse(record.to!)
            }
        }
        return writer.batch
    }

    struct Writer {
        let gist: URL
        let batch: UUID
        let undoOf: UUID?
        let device: DeviceID
        let now: Date

        func url(_ path: String) -> URL { gist.appending(path: path) }

        func relative(_ url: URL) -> String {
            String(url.standardizedFileURL.path.dropFirst(gist.standardizedFileURL.path.count + 1))
        }

        func record(_ op: MoveRecord.Op, from: String? = nil, to: String? = nil) throws {
            let line = MoveRecord(
                schemaVersion: 1, id: UUID(), batch: batch, undoOf: undoOf, at: now, device: device, op: op, from: from, to: to
            )
            try CoordinatedFile.append(JSONFormat.lineEncoder.encode(line) + Data("\n".utf8), to: MoveJournal.url(in: gist))
        }

        func move(_ from: String, to: String) throws {
            try CoordinatedFile.move(url(from), to: url(to))
            try record(.move, from: from, to: to)
        }

        func makeFolder(_ path: String) throws {
            try FileManager.default.createDirectory(at: url(path), withIntermediateDirectories: false)
            try record(.makeFolder, to: path)
        }

        func makeParents(of path: String) throws {
            var missing: [String] = []
            var parent = (path as NSString).deletingLastPathComponent
            while !parent.isEmpty, !FileManager.default.fileExists(atPath: url(parent).path) {
                missing.append(parent)
                parent = (parent as NSString).deletingLastPathComponent
            }
            for folder in missing.reversed() { try makeFolder(folder) }
        }

        func removeFolder(_ path: String) throws {
            try FileManager.default.removeItem(at: url(path))
            try record(.removeFolder, from: path)
        }

        func removeFolderIfEmpty(_ path: String) throws {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: url(path).path),
                names.allSatisfy(IndexRules.isIgnoredFile)
            else { return }
            for junk in names {
                try FileManager.default.removeItem(at: url(path).appending(path: junk))
                try record(.removeJunk, from: "\(path)/\(junk)")
            }
            try removeFolder(path)
        }

        func unfileCourse(_ folder: String) throws {
            let store = CourseStore(url: url(folder))
            let file = try store.load().model
            guard file == CourseFile(course: file.course) else { throw Failure.courseChanged(folder) }
            let gistStore = GISTStore(url: gist)
            var transcript = try gistStore.loadTranscript()
            if !transcript.model.unfiledCourses.contains(where: { $0.id == file.course.id }) {
                transcript.model.unfiledCourses.append(file.course)
                try gistStore.save(transcript)
            }
            try FileManager.default.removeItem(at: store.courseFileURL)
            try record(.unfileCourse, from: folder)
        }

        func removeEmptied(_ folders: Set<String>) throws {
            var candidates = Set<String>()
            for folder in folders {
                var path = folder
                while path.contains("/") {  // never the GIST root or a semester folder
                    candidates.insert(path)
                    path = (path as NSString).deletingLastPathComponent
                }
            }
            for path in candidates.sorted(by: { $0.count > $1.count }) { try removeFolderIfEmpty(path) }
        }
    }
}
