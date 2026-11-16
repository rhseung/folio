import Foundation

public enum ModelPart<Doc: Sendable>: Sendable {
    case items(AnyItems<Doc>)
    case rule(AnyRule<Doc>)
}
