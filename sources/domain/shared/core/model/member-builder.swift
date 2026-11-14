import Foundation

@resultBuilder public enum MemberBuilder<Doc: Sendable, E: Sendable> {
    // 이것이 없으면 각 줄의 형식을 따로 추론하므로, `Ref(\.field, ...)`가 어느 항목에 속하는지 알 수 없다.
    public static func buildExpression(_ member: Member<Doc, E>) -> [Member<Doc, E>] { [member] }
    public static func buildExpression(_ members: [Member<Doc, E>]) -> [Member<Doc, E>] { members }
    public static func buildBlock(_ members: [Member<Doc, E>]...) -> [Member<Doc, E>] { members.flatMap { $0 } }
}
