import SwiftUI

@MainActor final class ColumnMemory {
    static let shared = ColumnMemory(defaults: LocalFolders.isolatesDefaults() ? nil : .standard)
    private let defaults: UserDefaults?
    private(set) var last: Set<ColumnKind>

    init(defaults: UserDefaults?, collapsed: Set<ColumnKind> = []) {
        self.defaults = defaults
        last = defaults.map { d in Set(ColumnKind.allCases.filter { d.bool(forKey: Self.key($0)) }) } ?? collapsed
    }

    static func key(_ kind: ColumnKind) -> String { "columnCollapsed.\(kind.rawValue)" }

    func remember(_ kind: ColumnKind, collapsed on: Bool) {
        if on { last.insert(kind) } else { last.remove(kind) }
        defaults?.set(on, forKey: Self.key(kind))
    }

    func newPane() -> ColumnPrefs { ColumnPrefs(collapsed: last, memory: self) }

    // 나중 빌드가 없앤 종류가 있어도 요청 전체와 창이 실패하지 않도록, 원래 이름으로 받아 모르는 종류만 건너뛴다.
    func pane(_ kinds: [String]?) -> ColumnPrefs {
        guard let kinds else { return newPane() }
        return ColumnPrefs(collapsed: Set(kinds.compactMap(ColumnKind.init(rawValue:))), memory: self)
    }
}
