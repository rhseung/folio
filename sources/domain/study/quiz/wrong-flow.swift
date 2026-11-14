import Foundation

public enum WrongFlow {
    // 고친 문제를 며칠 뒤 다시 확인할지는 설정(`review.quizRecheckDays`)이다. 상태의 종류만 보는 곳은 기본값으로 불러도 된다.
    public static func status(
        _ attempts: [(day: LocalDate, verdict: Verdict)], recheckDays: Int = SettingItem.quizRecheckDays.int
    ) -> WrongStatus {
        var status = WrongStatus.neverWrong
        for (day, verdict) in attempts {
            switch (status, verdict) {
            case (_, .wrong), (_, .partial):
                status = .open(since: day)
            case (.open, .correct):
                status = .resolved(on: day, recheckDue: day.adding(days: recheckDays))
            case (.resolved(let on, let due?), .correct) where day >= due:
                status = .resolved(on: on, recheckDue: nil)
            default:
                break
            }
        }
        return status
    }

    public static func isDue(_ attempts: [(day: LocalDate, verdict: Verdict)], today: LocalDate, recheckDays: Int) -> Bool {
        switch status(attempts, recheckDays: recheckDays) {
        case .open: true
        case .resolved(_, let recheck?): recheck <= today
        default: false
        }
    }

    public static func isOpen(_ s: WrongStatus) -> Bool {
        if case .open = s { true } else { false }
    }

    public static func pickForReview(
        cards: [UUID], attempts: [UUID: [(day: LocalDate, verdict: Verdict)]], today: LocalDate, count: Int,
        recheckDays: Int
    ) -> [UUID] {
        func lastDay(_ id: UUID) -> LocalDate? { attempts[id]?.last?.day }
        let due = cards.filter { isDue(attempts[$0] ?? [], today: today, recheckDays: recheckDays) }
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
