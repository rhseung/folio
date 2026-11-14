import Foundation

public enum WrongFlow {
    public static let recheckAfterDays = 7

    public static func status(_ attempts: [(day: LocalDate, verdict: Verdict)]) -> WrongStatus {
        var status = WrongStatus.neverWrong
        for (day, verdict) in attempts {
            switch (status, verdict) {
            case (_, .wrong), (_, .partial):
                status = .open(since: day)
            case (.open, .correct):
                status = .resolved(on: day, recheckDue: day.adding(days: recheckAfterDays))
            case (.resolved(let on, let due?), .correct) where day >= due:
                status = .resolved(on: on, recheckDue: nil)
            default:
                break
            }
        }
        return status
    }

    public static func isDue(_ attempts: [(day: LocalDate, verdict: Verdict)], today: LocalDate) -> Bool {
        switch status(attempts) {
        case .open: true
        case .resolved(_, let recheck?): recheck <= today
        default: false
        }
    }

    public static func isOpen(_ s: WrongStatus) -> Bool {
        if case .open = s { true } else { false }
    }

    public static func pickForReview(cards: [UUID], attempts: [UUID: [(day: LocalDate, verdict: Verdict)]], today: LocalDate, count: Int)
        -> [UUID]
    {
        func lastDay(_ id: UUID) -> LocalDate? { attempts[id]?.last?.day }
        let due = cards.filter { isDue(attempts[$0] ?? [], today: today) }
        let rest = cards.filter { !due.contains($0) }.sorted {
            (lastDay($0) ?? .init(year: 1, month: 1, day: 1)!) < (lastDay($1) ?? .init(year: 1, month: 1, day: 1)!)
        }
        return Array((due + rest).prefix(count))
    }

    public static func accuracy(_ verdicts: [Verdict]) -> Double? {
        guard !verdicts.isEmpty else { return nil }
        let score = verdicts.reduce(0.0) { $0 + ($1 == .correct ? 1 : $1 == .partial ? 0.5 : 0) }
        return score / Double(verdicts.count)
    }
}
