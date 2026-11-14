public enum MathFence {
    public enum Syntax: String, Sendable, CaseIterable {
        case latex, asciimath
    }

    public static let languages: [(name: String, syntax: Syntax)] = [
        ("math", .latex), ("tex", .latex), ("latex", .latex), ("asciimath", .asciimath), ("am", .asciimath),
    ]

    public static func syntax(_ info: String?) -> Syntax? {
        guard let word = info?.split(whereSeparator: \.isWhitespace).first?.lowercased() else { return nil }
        return languages.first { $0.name == word }?.syntax
    }
}
