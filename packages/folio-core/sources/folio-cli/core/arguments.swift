import ArgumentParser
import FolioDomain
import Foundation

extension UUID: @retroactive ExpressibleByArgument {
    public init?(argument: String) { self.init(uuidString: argument) }
}

extension NoteKind: ExpressibleByArgument {}
extension AttendanceState: ExpressibleByArgument {}
extension ExamKind: ExpressibleByArgument {}
extension AssignmentStatus: ExpressibleByArgument {}
extension AssignmentRepeat: ExpressibleByArgument {}
extension MaterialStatus: ExpressibleByArgument {}
extension GradingMode: ExpressibleByArgument {}
extension Term: ExpressibleByArgument {}
extension ReviewResult: ExpressibleByArgument {}

/// `2026-10-28`, `2026-10-28 14:30`, `2026-10-28T14:30`, or full ISO 8601, in local time unless it says otherwise.
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

extension LocalDate: ExpressibleByArgument {
    public init?(argument: String) { self.init(argument) }
}

/// `none` clears an optional field in a set command; anything else is read as `T`. One word for every command, so
/// `--due none`, `--end none` and `--late-policy none` all read the same.
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
    /// A repeatable option given as `none` alone empties the list it replaces.
    var clearing: [String] { self == ["none"] ? [] : self }
}

/// `true`/`false` with the Korean the app shows, for set commands that flip one state.
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
