import Foundation

/// One unit from a units file, with the sessions (`3주차-1`) that covered it.
public struct UnitSpec: Codable, Sendable, Equatable {
    public var title: String
    public var sessions: [String]?
    public var children: [UnitSpec]?

    public init(title: String, sessions: [String]? = nil, children: [UnitSpec]? = nil) {
        self.title = title
        self.sessions = sessions
        self.children = children
    }
}

/// `{"course": "<course folder>", "units": [...]}`; other keys (sources, notes) are ignored.
public struct UnitFile: Codable, Sendable {
    public var course: String
    public var units: [UnitSpec]
}

public enum UnitImporter {
    public struct Result: Sendable {
        public var file: CourseFile
        public var added: [String]
        /// Session links made, as `unit ← session`.
        public var linked: [String]
        public var unknownSessions: [String]
    }

    /// Units match by title under the same parent, so re-running adds nothing and units edited in the app keep their IDs.
    /// New units go after their existing siblings. Links are only added, on both sides; nothing is removed.
    public static func merge(_ specs: [UnitSpec], into file: CourseFile, device: DeviceID, now: Date) -> Result {
        var file = file
        var added: [String] = [], linked: [String] = [], unknown: [String] = []
        func visit(_ specs: [UnitSpec], parent: UUID?) {
            for spec in specs {
                let id: UUID
                if let existing = file.units.first(where: { $0.parentId == parent && $0.title == spec.title }) {
                    id = existing.id
                } else {
                    let order = (file.units.filter { $0.parentId == parent }.map(\.order).max() ?? -1) + 1
                    let unit = Unit(device: device, at: now, title: spec.title, order: order, parentId: parent)
                    file.units.append(unit)
                    added.append(spec.title)
                    id = unit.id
                }
                for name in spec.sessions ?? [] {
                    guard let s = file.sessions.firstIndex(where: { $0.name(among: file.sessions) == name }) else {
                        unknown.append(name)
                        continue
                    }
                    guard let u = file.units.firstIndex(where: { $0.id == id }), !file.units[u].sessionIds.contains(file.sessions[s].id) else { continue }
                    file.units[u].sessionIds.append(file.sessions[s].id)
                    file.units[u].touch(by: device, at: now)
                    if !file.sessions[s].unitIds.contains(id) {
                        file.sessions[s].unitIds.append(id)
                        file.sessions[s].touch(by: device, at: now)
                    }
                    linked.append("\(spec.title) ← \(name)")
                }
                visit(spec.children ?? [], parent: id)
            }
        }
        visit(specs, parent: nil)
        return Result(file: file, added: added, linked: linked, unknownSessions: unknown)
    }
}
