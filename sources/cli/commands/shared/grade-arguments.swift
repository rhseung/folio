import ArgumentParser
import FolioActions
import FolioDomain
import Foundation

extension Resolver {
    func score(_ name: String, in c: CourseRef) throws -> ScoreEntry {
        let f = c.file
        return try pick(
            name, f.scores, what: "점수", names: { [f.name(of: $0.id) ?? $0.title] },
            ref: { "\(c.code)/\($0.title.isEmpty ? $0.id.uuidString : $0.title)" })
    }

    func letterGrade(_ symbol: String) throws -> LetterGrade {
        try pick(symbol, try ctx.catalog().letterGrades, what: "성적", names: { [$0.symbol] }, ref: \.symbol)
    }
}

extension Aggregation: ExpressibleByArgument {
    public init?(argument: String) {
        guard let v = try? JSONDecoder().decode(Aggregation.self, from: Data("\"\(argument)\"".utf8)) else { return nil }
        self = v
    }
    public static var allValueStrings: [String] { ["sum", "mean", "single", "dropLowest:<n>", "bestOf:<n>"] }
}

func bar(_ fraction: Double, width: Int = 10) -> String {
    let filled = Int((min(max(fraction, 0), 1) * Double(width)).rounded())
    return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
}
