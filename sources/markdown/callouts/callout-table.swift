import Foundation

// 기본 종류에 설정(`settings.json`의 `callouts`)의 종류를 더한 표다. 같은 이름이면 설정이 기본 종류를 덮는다. 표에 없는
// 종류도 콜아웃으로 그리고, 색은 `neutral` 색에 바탕을 둔다.
public struct CalloutTable: Equatable, Sendable {
    public private(set) var kinds: [CalloutKind]

    public init(adding custom: [CalloutKind] = []) {
        var kinds = CalloutKind.defaults
        for kind in custom where CalloutKind.allows(kind.name) {
            if let i = kinds.firstIndex(where: { $0.name == kind.name }) { kinds[i] = kind } else { kinds.append(kind) }
        }
        self.kinds = kinds
    }

    public static let standard = CalloutTable()

    public subscript(name: String) -> CalloutKind? { kinds.first { $0.name == name } }

    public var names: [String] { kinds.map(\.name) }

    public func numbered(_ name: String) -> Bool { self[name]?.numbered ?? false }

    public func provable(_ name: String) -> Bool { self[name]?.provable ?? false }
}
