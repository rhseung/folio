import Foundation

public enum MathSyntax: String, Codable, Sendable, CaseIterable {
    case latex, asciimath
}

extension MathSyntax {
    public var name: LocalizedStringResource {
        switch self {
        case .latex: .mathSyntaxLatex
        case .asciimath: .mathSyntaxAsciimath
        }
    }
}
