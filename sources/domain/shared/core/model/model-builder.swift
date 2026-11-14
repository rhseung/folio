import Foundation

@resultBuilder public enum ModelBuilder<Doc: Sendable> {
    public static func buildExpression(_ items: AnyItems<Doc>) -> [ModelPart<Doc>] { [.items(items)] }
    public static func buildExpression(_ rule: AnyRule<Doc>) -> [ModelPart<Doc>] { [.rule(rule)] }
    public static func buildBlock(_ parts: [ModelPart<Doc>]...) -> [ModelPart<Doc>] { parts.flatMap { $0 } }
}
