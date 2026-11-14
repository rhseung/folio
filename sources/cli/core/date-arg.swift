import ArgumentParser
import FolioDomain
import Foundation

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
