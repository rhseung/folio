import ArgumentParser
import FolioDomain
import Foundation

enum Clearable<T: ExpressibleByArgument>: ExpressibleByArgument {
    case clear, set(T)
    init?(argument: String) {
        if argument == "none" { self = .clear } else if let v = T(argument: argument) { self = .set(v) } else { return nil }
    }
    var value: T? { if case .set(let v) = self { v } else { nil } }
    static var allValueStrings: [String] { T.allValueStrings.isEmpty ? [] : T.allValueStrings + ["none"] }
    static var defaultCompletionKind: CompletionKind { T.allValueStrings.isEmpty ? T.defaultCompletionKind : .list(allValueStrings) }
}
