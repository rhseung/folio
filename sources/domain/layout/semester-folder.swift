import Foundation

public struct SemesterFolder: Hashable, Sendable {
    public let year: Int
    public let term: Term
    public let name: String

    public init?(year: Int, term: Term) {
        guard (1000...9999).contains(year), let number = term.folderNumber else { return nil }
        self.year = year
        self.term = term
        self.name = "\(year)-\(number)"
    }

    public init?(name: String) {
        let parts = name.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
            let year = Int(parts[0]), let number = Int(parts[1]),
            let term = Term.allCases.first(where: { $0.folderNumber == number }),
            let parsed = SemesterFolder(year: year, term: term),
            parsed.name == name  // `2026-03`이나 `+2026-3` 같은 비표준 꼴을 거절한다.
        else { return nil }
        self = parsed
    }
}
