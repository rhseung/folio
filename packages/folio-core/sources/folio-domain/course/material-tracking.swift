import Foundation

/// A file or opaque folder found in a course folder. `path` is relative to the course folder.
public struct ScannedEntry: Hashable, Sendable {
    public var path: String
    public var isFolder: Bool
    public var size: Int64?

    public init(path: String, isFolder: Bool = false, size: Int64? = nil) {
        self.path = path
        self.isFolder = isFolder
        self.size = size
    }

    public static func materials(in course: FolderTree) -> [ScannedEntry] {
        func walk(_ node: FolderTree, _ path: String) -> [ScannedEntry] {
            switch node.content {
            case .file(let size): [ScannedEntry(path: path, size: size)]
            case .opaque: [ScannedEntry(path: path, isFolder: true)]
            case .folder(let children): children.flatMap { walk($0, "\(path)/\($0.name)") }
            }
        }
        return course.children
            .filter { CourseFolder(rawValue: $0.name)?.holdsMaterials ?? true }
            .flatMap { walk($0, $0.name) }
    }
}

/// Disk access the tracker needs, injected so the algorithm stays pure and testable.
public struct TrackingIO {
    /// Current relative path of the material's bookmark target if it still lies in the course folder.
    public var resolveBookmark: (Material) -> String?
    /// SHA-256 hex of a file, or nil if it isn't available locally (e.g. not downloaded from iCloud).
    public var hash: (String) throws -> String?
    public var makeBookmark: (String) -> Data?

    public init(
        resolveBookmark: @escaping (Material) -> String?,
        hash: @escaping (String) throws -> String?,
        makeBookmark: @escaping (String) -> Data?
    ) {
        self.resolveBookmark = resolveBookmark
        self.hash = hash
        self.makeBookmark = makeBookmark
    }
}

public enum MaterialTracking {
    /// The role for a path: a course-specific `folderRoles` override (longest matching folder) wins over the standard layout.
    public static func role(for path: String, overrides: [String: MaterialRole]) -> MaterialRole? {
        let match = overrides.keys
            .filter { path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
            .max { $0.count < $1.count }
        return match.flatMap { overrides[$0] } ?? MaterialRole(path: path)
    }

    /// Matches tracked materials to what is on disk (docs/SPEC.md "파일 추적", "미분류 파일"):
    /// same path → bookmark → content hash; unmatched materials become `missing` (links are kept),
    /// and new files are registered, classified by folder when the folder has a role.
    public static func reconcile(
        _ materials: [Material], with scanned: [ScannedEntry], folderRoles: [String: MaterialRole] = [:],
        io: TrackingIO, device: DeviceID, now: Date
    ) throws -> [Material] {
        var result = materials
        var unclaimed = Dictionary(keepingFirst: scanned.map { ($0.path, $0) })
        var unmatched: [Int] = []

        func relocate(_ i: Int, to entry: ScannedEntry) {
            result[i].path = entry.path
            result[i].bookmark = io.makeBookmark(entry.path)
            if let role = role(for: entry.path, overrides: folderRoles) {
                result[i].role = role
                if result[i].status != .ignored { result[i].status = .classified }
            }
        }

        for i in result.indices {
            let m = result[i]
            if let entry = unclaimed.removeValue(forKey: m.path) {
                if entry.size != m.size {  // replaced in place
                    result[i].size = entry.size
                    result[i].hash = entry.isFolder ? nil : try io.hash(entry.path)
                }
                if m.status == .missing { result[i].status = m.role == nil ? .unclassified : .classified }
            } else if let path = io.resolveBookmark(m), let entry = unclaimed.removeValue(forKey: path) {
                relocate(i, to: entry)
            } else {
                unmatched.append(i)
            }
        }

        var hashes: [String: String?] = [:]
        for i in unmatched {
            let m = result[i]
            let candidate = try m.hash.flatMap { wanted in
                try unclaimed.values
                    .filter { !$0.isFolder && $0.size == m.size }
                    .sorted { $0.path < $1.path }
                    .first { entry in
                        if hashes[entry.path] == nil { hashes[entry.path] = try io.hash(entry.path) }
                        return hashes[entry.path] == wanted
                    }
            }
            if let entry = candidate {
                unclaimed.removeValue(forKey: entry.path)
                relocate(i, to: entry)
            } else {
                result[i].status = .missing
            }
        }

        for entry in unclaimed.values.sorted(by: { $0.path < $1.path }) {
            let role = role(for: entry.path, overrides: folderRoles)
            result.append(Material(
                device: device, at: now,
                path: entry.path, isFolder: entry.isFolder, bookmark: io.makeBookmark(entry.path),
                hash: entry.isFolder ? nil : try hashes[entry.path] ?? io.hash(entry.path), size: entry.size,
                role: role, status: role == nil ? .unclassified : .classified
            ))
        }

        linkTexSources(&result)

        for i in result.indices {
            if let old = materials.first(where: { $0.id == result[i].id }), old != result[i] {
                result[i].touch(by: device, at: now)
            }
        }
        return result
    }

    /// A `.tex` next to a same-named PDF is that PDF's source (docs/SPEC.md "색인 제외 대상").
    static func linkTexSources(_ materials: inout [Material]) {
        let pdfs = Dictionary(
            materials.filter { $0.path.hasSuffix(".pdf") }.map { ($0.path.dropLast(4), $0.id) },
            uniquingKeysWith: { a, _ in a }
        )
        for i in materials.indices where materials[i].path.hasSuffix(".tex") && materials[i].sourceOf == nil {
            materials[i].sourceOf = pdfs[materials[i].path.dropLast(4)]
        }
    }
}
