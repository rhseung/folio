import FolioDomain
import FolioStorage
import Foundation

@Action(
    "assignment set", "과제의 제목, 마감, 상태, 성적 항목, 메모 바꾸기. 준 것만 바뀐다",
    discussion: """
        성적 항목이나 묶음을 바꾸면 이전 항목에 매긴 점수는 지워진다. 점수를 주면 상태는 graded가 된다.
        값을 지우려면 none을 준다.
        """,
    done: "과제 '{assignment}'을(를) 바꿨습니다",
    examples: [
        #"folio assignment set EC4207/HW3 --due "2026-11-06 23:59""#, #"folio assignment set EC4207/HW3 --component 과제 --memo "3번 질문함""#,
        "folio assignment set EC4207/HW3 --component 과제 --score 9/10",
        "folio assignment set EC4207/HW3 --due none --repeats weekly --dry-run",
    ],
    phrases: ["미뤄졌", "연기", "마감일", "마감 변경", "기한 연장", "과제 메모", "과제 이름"])
public struct AssignmentSave {
    public struct Score: Codable, Sendable, Equatable {
        public var component: UUID?
        public var score: Double
        public var max: Double
        public init(component: UUID?, score: Double, max: Double) {
            (self.component, self.score, self.max) = (component, score, max)
        }
    }
    /// 과목
    @Arg var course: Course.ID
    /// 과제
    @Arg var assignment: Assignment.ID
    /// 새 제목
    var title: Patch<String>
    /// 마감 일시
    var due: Patch<Date?>
    /// 상태
    var status: Patch<AssignmentStatus>
    /// 반복. weekly, daily, biweekly, monthly, 3d, 2w, 1m, weekly:mon,wed, 또는 빠른 추가의 말(매일, 격일, 3일마다, 격주, 매월, 매주 월수, 월,수마다, 평일마다)
    var repeats: Patch<AssignmentRepeat?>
    /// 반영되는 성적 항목. 주면 묶음은 풀린다
    @CLIName("component") var componentId: Patch<GradeComponent.ID?>
    /// 한꺼번에 점수를 매기는 성적 항목 묶음. 주면 성적 항목 하나는 풀린다
    @CLIName("group") var componentGroup: Patch<String?>
    /// 메모
    var memo: Patch<String>
    /// 과제가 반영되는 성적 항목들의 점수 전체. 주면 목록 전체를 바꾸고, 목록에 없는 항목의 점수는 지운다
    @Hidden var scores: Patch<[Score]>
    /// 준 항목의 점수만 바꾸고 다른 항목의 점수는 그대로 둔다. 빈 목록이면 점수를 모두 지운다
    @CLIName("score") @Parsed("score", "9/10. 묶음이면 <항목>:9/10") var score: Patch<[Score]>

    static func scoreTitle(_ title: String, repeats: AssignmentRepeat?, due: Date?) -> String {
        repeats != nil ? due.map { "\(title) \($0.formatted(.dateTime.month(.defaultDigits).day()))" } ?? title : title
    }

    public func run(_ ctx: ActionContext) throws {
        if case .set(_?) = componentId, case .set(_?) = componentGroup {
            throw ActionError.input(String(localized: .errorAssignmentComponentOrGroup))
        }
        if title.value?.isEmpty == true { throw ActionError.rule(String(localized: .errorAssignmentTitleEmpty)) }
        guard ((scores.value ?? []) + (score.value ?? [])).allSatisfy({ $0.max > 0 }) else {
            throw ActionError.rule(String(localized: .errorAssignmentMaxScore))
        }

        let end = try repeatEnd(ctx, course: course)
        try ctx.edit(course) { f in
            let i = try index(assignment, in: f.assignments, .valueAssignment)
            let old = f.assignments[i]
            var a = old
            title.apply(&a.title)
            due.apply(&a.due)
            repeats.apply(&a.repeats)
            memo.apply(&a.memo)

            if case .set(let id) = componentId { (a.componentId, a.componentGroup) = (id, nil) }
            if case .set(let g) = componentGroup { (a.componentId, a.componentGroup) = (g == nil ? a.componentId : nil, g) }
            if let g = a.componentGroup, g != old.componentGroup, !f.components.contains(where: { $0.group == g }) {
                throw ActionError.notFound(String(localized: .errorAssignmentGroupNotFound(g)))
            }

            func covered(_ group: String?, _ id: UUID?) -> [UUID] {
                group.map { g in f.components.filter { $0.group == g }.map(\.id) } ?? id.map { [$0] } ?? []
            }
            let own = f.scores.filter { $0.assignmentId == assignment }
            let target = covered(a.componentGroup, a.componentId)
            let shown = target + covered(old.componentGroup, old.componentId ?? own.first?.componentId).filter { !target.contains($0) }
            func resolved(_ list: [Score]) throws -> [(component: UUID, score: Double, max: Double)] {
                try list.map { s in
                    guard let id = s.component ?? (target.count == 1 ? target[0] : nil) else {
                        throw ActionError.input(
                            String(localized: target.isEmpty ? .errorAssignmentNoComponent : .errorAssignmentGroupScoreFormat))
                    }
                    guard target.contains(id) else {
                        throw ActionError.rule(
                            String(localized: .errorAssignmentNotCovered(f.components.first { $0.id == id }?.name ?? id.uuidString)))
                    }
                    return (id, s.score, s.max)
                }
            }

            var given = own.filter { target.contains($0.componentId) }.map { (component: $0.componentId, score: $0.score, max: $0.max) }
            if let list = scores.value { given = try resolved(list) }
            // 명령줄에서 준 한 평가 항목의 점수가 다른 항목의 점수까지 가져가면 안 된다.
            if let list = score.value {
                if list.isEmpty { given = [] }
                for s in try resolved(list) {
                    given.removeAll { $0.component == s.component }
                    given.append(s)
                }
            }

            let entryTitle = Self.scoreTitle(a.title, repeats: a.repeats, due: a.due)
            let oldTitle = Self.scoreTitle(old.title, repeats: old.repeats, due: old.due)
            a.touch(by: ctx.device, at: ctx.now)
            f.assignments[i] = a
            var kept = Set<UUID>()
            for s in given {
                kept.insert(s.component)
                if let j = f.scores.firstIndex(where: { $0.assignmentId == assignment && $0.componentId == s.component }) {
                    let named = f.scores[j].title == oldTitle || f.scores[j].title.isEmpty ? entryTitle : f.scores[j].title
                    guard (f.scores[j].title, f.scores[j].score, f.scores[j].max) != (named, s.score, s.max) else { continue }
                    (f.scores[j].title, f.scores[j].score, f.scores[j].max) = (named, s.score, s.max)
                    f.scores[j].touch(by: ctx.device, at: ctx.now)
                } else {
                    var entry = ScoreEntry(
                        device: ctx.device, at: ctx.now, componentId: s.component, title: entryTitle, score: s.score, max: s.max)
                    entry.assignmentId = assignment
                    f.scores.append(entry)
                }
            }
            f.scores.removeAll { $0.assignmentId == assignment && shown.contains($0.componentId) && !kept.contains($0.componentId) }
            status.apply(&f.assignments[i].status)
            f.markGraded(assignment, device: ctx.device, now: ctx.now)
            f.continueRepeating(assignment, until: end, calendar: ctx.calendar, device: ctx.device, now: ctx.now)
        }
    }
}
