import FolioCore
import Foundation

// 한 과목의 공부 기록이다. 여러 기기의 로그에서 순서 없이 모은다.
public struct StudyLog: Sendable {
    public var solves: [(at: Date, event: ProblemSolveEvent)]
    public var changes: [(at: Date, event: ProblemVerdictEvent)]
    public var flips: [(at: Date, event: CardFlipEvent)]
    public var views: [(at: Date, event: PageViewEvent)]
    public var checks: [(at: Date, event: PlanCheckEvent)]

    public init(
        solves: [(at: Date, event: ProblemSolveEvent)] = [], changes: [(at: Date, event: ProblemVerdictEvent)] = [],
        flips: [(at: Date, event: CardFlipEvent)] = [], views: [(at: Date, event: PageViewEvent)] = [],
        checks: [(at: Date, event: PlanCheckEvent)] = []
    ) {
        self.solves = solves
        self.changes = changes
        self.flips = flips
        self.views = views
        self.checks = checks
    }

    public static let types: Set<String> = [
        ProblemSolveEvent.type, ProblemVerdictEvent.type, CardFlipEvent.type, PageViewEvent.type, PlanCheckEvent.type,
    ]
}
