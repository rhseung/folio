import FolioCore
import FolioDomain
import FolioStorage
import Foundation

@Query(
    "study show", "과목의 공부 상태: 단원마다 준비 정도와 진척, 남은 오답, 풀이 기록",
    discussion: "준비 정도는 판정의 가중 평균이다. Claude만 채점한 것은 절반으로, 안 푼 문제는 0으로 센다. 오답은 다른 공부일에 맞혀야 빠진다.",
    examples: ["folio study show EC4207", "folio study show EC4207 --json"], phrases: ["공부 상태", "준비 정도", "오답 목록", "어디가 약해"],
    panel: true)
public struct StudyShow {
    /// 과목
    @Arg public var course: Course.ID

    public struct UnitRow: Encodable {
        public var id: UUID
        public var title: String
        public var depth: Int
        public var done: Bool
        public var state: String
        public var score: Double?
        public var problemsSolved: Int
        public var problemsTotal: Int
        public var wrong: Int
        public var recheck: Int
        public var cardsTotal: Int
        public var cardsUnknown: Int
        public var pagesSeen: Int
        public var pagesTotal: Int
    }

    public struct Wrong: Encodable {
        public var set: String
        public var number: String
        public var problemId: UUID
        public var recheck: Bool
        public var since: String
        public var reason: String?
    }

    public struct Attempt: Encodable {
        public var id: UUID
        public var set: String
        public var number: String
        public var at: Date
        public var verdict: String
        public var basis: String
        public var changed: Bool
    }

    public struct Summary: Encodable {
        public var units: [UnitRow]
        public var wrong: [Wrong]
        public var attempts: [Attempt]
    }

    public func read(_ ctx: ReadContext) throws -> Summary {
        let study = try ctx.study(course)
        let file = study.file
        let setTitle = Dictionary(file.problemSets.map { ($0.id, $0.title) }) { a, _ in a }
        let units = UnitTree.outline(file.units).map { row -> UnitRow in
            let p = study.progress(of: row.unit, notes: file.notes.count { $0.unitIds.contains(row.unit.id) })
            return UnitRow(
                id: row.unit.id, title: row.unit.title, depth: row.depth, done: p.done, state: p.readiness.state.rawValue,
                score: p.readiness.score, problemsSolved: p.problemsSolved, problemsTotal: p.problemsTotal, wrong: p.readiness.wrong,
                recheck: p.readiness.recheck, cardsTotal: p.cardsTotal, cardsUnknown: p.cardsUnknown, pagesSeen: p.pagesSeen,
                pagesTotal: p.pagesTotal)
        }
        let wrong = study.allProblems.compactMap { r -> Wrong? in
            let since: LocalDate
            switch r.status {
            case .open(let d), .recheck(let d): since = d
            default: return nil
            }
            return Wrong(
                set: setTitle[r.setId] ?? "", number: r.problem.number, problemId: r.problem.id, recheck: r.status.isRecheck,
                since: since.description, reason: r.last?.reason?.rawValue)
        }
        let attempts = study.allProblems.flatMap { r in
            r.attempts.map {
                Attempt(
                    id: $0.id, set: setTitle[r.setId] ?? "", number: r.problem.number, at: $0.at, verdict: $0.verdict.rawValue,
                    basis: $0.basis.rawValue, changed: $0.changed)
            }
        }
        .sorted { $0.at > $1.at }
        return Summary(units: units, wrong: wrong, attempts: attempts)
    }
}
