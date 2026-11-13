import ArgumentParser
import FolioDomain
import Foundation

extension UUID: @retroactive ExpressibleByArgument {
    public init?(argument: String) { self.init(uuidString: argument) }
}

extension NoteKind: ExpressibleByArgument {}
extension NoteFormat: ExpressibleByArgument {}
extension MathSyntax: ExpressibleByArgument {}
extension AttendanceState: ExpressibleByArgument {}
extension AssignmentStatus: ExpressibleByArgument {}
extension AssignmentRepeat: ExpressibleByArgument {
    public init?(argument: String) { self.init(text: argument) }
}
extension MaterialStatus: ExpressibleByArgument {}
extension GradingMode: ExpressibleByArgument {}
extension Term: ExpressibleByArgument {}
extension ReviewResult: ExpressibleByArgument {}

extension Session.Kind: ExpressibleByArgument {
    public init?(argument: String) {
        switch argument {
        case "강의": self = .lecture
        case "휴강": self = .cancelled
        case "보강": self = .makeup
        default: self.init(rawValue: argument.lowercased())
        }
    }
}

struct DateArg: ExpressibleByArgument {
    var date: Date

    init?(argument: String) {
        if let d = try? Date(argument, strategy: .iso8601) {
            date = d
            return
        }
        let parts = argument.split(whereSeparator: { $0 == " " || $0 == "T" })
        guard let day = parts.first.flatMap({ LocalDate(String($0)) }) else { return nil }
        var c = DateComponents(year: day.year, month: day.month, day: day.day)
        if parts.count > 1 {
            let hm = parts[1].split(separator: ":").compactMap { Int($0) }
            guard hm.count == 2 else { return nil }
            (c.hour, c.minute) = (hm[0], hm[1])
        }
        guard let d = Calendar.current.date(from: c) else { return nil }
        date = d
    }

    static var defaultCompletionKind: CompletionKind { .default }
}

extension JSONValue: ExpressibleByArgument {
    public init?(argument: String) {
        self = (try? JSONDecoder().decode(JSONValue.self, from: Data(argument.utf8))) ?? .string(argument)
    }
}

extension LocalDate: ExpressibleByArgument {
    public init?(argument: String) { self.init(argument) }
}

enum Clearable<T: ExpressibleByArgument>: ExpressibleByArgument {
    case clear, set(T)
    init?(argument: String) {
        if argument == "none" { self = .clear } else if let v = T(argument: argument) { self = .set(v) } else { return nil }
    }
    var value: T? { if case .set(let v) = self { v } else { nil } }
    static var allValueStrings: [String] { T.allValueStrings.isEmpty ? [] : T.allValueStrings + ["none"] }
    static var defaultCompletionKind: CompletionKind { T.allValueStrings.isEmpty ? T.defaultCompletionKind : .list(allValueStrings) }
}

extension [String] {
    var clearing: [String] { self == ["none"] ? [] : self }
}

struct Toggle: ExpressibleByArgument {
    var value: Bool
    init?(argument: String) {
        switch argument.lowercased() {
        case "true", "yes", "on", "1", "켜기", "예": value = true
        case "false", "no", "off", "0", "끄기", "아니오": value = false
        default: return nil
        }
    }
    static var allValueStrings: [String] { ["true", "false"] }
}
