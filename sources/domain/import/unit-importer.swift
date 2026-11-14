import Foundation

public enum UnitImporter {
    public struct Result: Sendable {
        public var file: CourseFile
        public var added: [String]
        public var linked: [String]
        public var unknownSessions: [String]
    }

    // 같은 부모 아래에서 제목으로 단원을 맞추므로, 다시 실행해도 더하는 단원이 없고 앱에서 고친 단원도 ID를 유지한다.
    public static func merge(_ specs: [UnitSpec], into file: CourseFile, calendar: Calendar, device: DeviceID, now: Date) -> Result {
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
                    let matches = file.sessions(matching: name, calendar: calendar)
                    guard matches.count == 1, let s = file.sessions.firstIndex(where: { $0.id == matches[0].id }) else {
                        unknown.append(name)
                        continue
                    }
                    guard let u = file.units.firstIndex(where: { $0.id == id }), !file.units[u].sessionIds.contains(file.sessions[s].id)
                    else { continue }
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
