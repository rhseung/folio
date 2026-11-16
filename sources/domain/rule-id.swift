import Foundation

// 저장은 메시지가 아니라 규칙과 대상으로 위반을 비교한다. 그래서 메시지 문구를 고치거나 항목 이름을 바꿔도
// 파일에 이미 있던 문제가 새 문제로 보이지 않는다.
public struct RuleID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let name: String
    public init(_ name: String) { self.name = name }
    public init(stringLiteral value: String) { name = value }
    public var description: String { name }
}
