import Foundation

public enum MaterialTracking {
    public static func role(for path: String, overrides: [String: MaterialRole]) -> MaterialRole? {
        let match = overrides.keys
            .filter { path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
            .max { $0.count < $1.count }
        return match.flatMap { overrides[$0] } ?? MaterialRole(path: path)
    }

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
                if entry.size != m.size {
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
            result.append(
                Material(
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

    // 이름은 파일 시스템처럼 대소문자를 가리지 않고 비교한다. 옮겨도 두 ID가 그대로이므로, 전에 만든 연결을 남기면 옮긴
    // `.tex`가 옛 폴더의 PDF를 가리킨다. 그래서 연결을 매번 다시 계산한다.
    static func linkTexSources(_ materials: inout [Material]) {
        let pdfs = Dictionary(
            materials.filter { MaterialFormat(path: $0.path) == .pdf }.map { ($0.path.lowercased(), $0.id) },
            uniquingKeysWith: { a, _ in a }
        )
        for i in materials.indices {
            guard let pdf = MaterialFormat.builtPDF(of: materials[i].path) else { continue }
            materials[i].sourceOf = pdfs[pdf.lowercased()]
        }
    }
}

extension [Material] {
    // `sourceOf`는 추적할 때만 새로 고치므로 `material mv`를 바로 따라가지 못한다. 그래서 이름으로 찾는다.
    public func builtPDF(of source: Material) -> Material? {
        guard let pdf = MaterialFormat.builtPDF(of: source.path)?.lowercased() else { return nil }
        return first { $0.path.lowercased() == pdf }
    }

    // 같은 목록에 `.tex`가 있는 PDF만 뺀다. 그래야 역할별로 나눈 목록이 보이지 않는 원본 때문에 PDF를 잃지 않는다.
    public func withoutBuiltPDFs() -> [Material] {
        let hidden = Set(builtPDFsHidden().values.map(\.id))
        return filter { !hidden.contains($0.id) }
    }

    public func builtPDFsHidden() -> [Material.ID: Material] {
        var hidden: [Material.ID: Material] = [:]
        for source in self {
            if let pdf = builtPDF(of: source), pdf.status != .missing { hidden[source.id] = pdf }
        }
        return hidden
    }
}
