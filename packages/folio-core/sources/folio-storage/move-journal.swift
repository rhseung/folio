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

    /// Runs `moves` in order and returns the batch ID for `undo`. Checks every source and target first,
    /// so a stale plan fails before anything moves.
    @discardableResult
    public static func apply(_ moves: [PlannedMove], in gist: URL, device: DeviceID, now: Date) throws -> UUID {
        let fm = FileManager.default
        // Lexical, since a target doesn't exist yet: `a/../../x` must not reach past the GIST folder.
        let root = gist.standardizedFileURL.path + "/"
        for path in moves.flatMap({ [$0.from, $0.to] }) where !gist.appending(path: path).standardizedFileURL.path.hasPrefix(root) {
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
        try writer.removeEmptied(Set(moves.map { ($0.from as NSString).deletingLastPathComponent }))
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
            case .removeJunk: break
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
                  names.allSatisfy(IndexRules.isIgnoredFile) else { return }
            for junk in names {
                try FileManager.default.removeItem(at: url(path).appending(path: junk))
                try record(.removeJunk, from: "\(path)/\(junk)")
            }
            try removeFolder(path)
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
