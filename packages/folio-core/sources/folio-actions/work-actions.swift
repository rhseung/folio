import FolioDomain
import FolioStorage
import Foundation

// MARK: Exams

@Action("exam add", "시험 추가. 시험 폴더(Exams/<이름>)도 만든다", effect: .creates, done: "시험 '{title}'을(를) 추가했습니다",
        examples: [#"folio exam add EC4207 중간고사 --kind midterm --start "2026-10-21 10:00" --end "2026-10-21 12:00" --location B101"#,
                   "folio exam add EC4207 Quiz1 --kind quiz --start 2026-09-30 --dry-run"],
        phrases: ["기말고사 추가", "중간고사 등록", "시험 추가", "중간고사 추가", "기말 등록", "퀴즈 일정"])
public struct ExamAdd {
    @New var id: Exam.ID
    /// 과목
    @Arg var course: Course.ID
    /// 시험 제목
    @Arg var title: String
    /// 종류
    var kind: ExamKind = .other
    /// 시작 일시
    var start: Date?
    /// 끝 일시
    var end: Date?
    /// 장소
    var location: String = ""
    /// 반영되는 성적 항목
    var component: GradeComponent.ID?
    /// 범위 단원. 여러 번 줄 수 있다
    var scope: [FolioDomain.Unit.ID] = []
    /// 범위 설명. 예: 3장까지
    var scopeText: String = ""
    /// 허용 자료. 예: 계산기
    var allowed: String = ""
    /// 메모
    var memo: String = ""

    public func run(_ ctx: ActionContext) throws {
        var exam = Exam(id: id, device: ctx.device, at: ctx.now, kind: kind, title: title, start: start, end: end, location: location)
        (exam.componentId, exam.scopeText, exam.allowed, exam.memo) = (component, scopeText, allowed, memo)
        try ctx.edit(course) { f in
            guard !f.exams.contains(where: { $0.id == id }) else { throw ActionError.rule(String(localized: .errorIdTakenExam("\(id)"))) }
            f.exams.append(exam)
            f.setScope(scope, exam: id)
        }
        // The same path the exam screen and materials read, so a quiz named freely still gets its own QuizN.
        let exams = try ctx.file(course).exams
        if let path = MaterialIntake.folder(of: exam, among: exams) {
            let store = try ctx.store(course)
            if !FileManager.default.fileExists(atPath: store.fileURL(path).path) {
                try ctx.io(Change(.added, ctx.relative(store.fileURL(path)) + "/")) { try store.ensureFolder(exam: exam, among: exams) }
            }
        }
        ctx.made(id)
    }
}

@Action("exam set", "시험의 제목, 종류, 일시, 장소, 성적 항목, 범위 바꾸기. 준 것만 바뀐다", done: "시험 '{exam}'을(를) 바꿨습니다",
        examples: [#"folio exam set EC4207/중간고사 --start "2026-10-22 10:00" --end "2026-10-22 12:00""#,
                   "folio exam set EC4207/Quiz1 --location B203", "folio exam set EC4207/Quiz1 --end none --component none --dry-run"],
        phrases: ["시험 날짜 변경", "시험 시간", "시험 장소", "고사실"])
public struct ExamSet {
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID
    /// 새 제목
    var title: Patch<String>
    /// 종류
    var kind: Patch<ExamKind>
    /// 시작 일시
    var start: Patch<Date?>
    /// 끝 일시
    var end: Patch<Date?>
    /// 장소
    var location: Patch<String>
    /// 반영되는 성적 항목
    var component: Patch<GradeComponent.ID?>
    /// 범위 단원 전체. 단원을 하나씩 넣고 빼려면 folio exam scope
    var scope: Patch<[FolioDomain.Unit.ID]>
    /// 범위 설명
    var scopeText: Patch<String>
    /// 허용 자료
    var allowed: Patch<String>
    /// 메모
    var memo: Patch<String>

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                title.apply(&e.title)
                kind.apply(&e.kind)
                start.apply(&e.start)
                end.apply(&e.end)
                location.apply(&e.location)
                component.apply(&e.componentId)
                scopeText.apply(&e.scopeText)
                allowed.apply(&e.allowed)
                memo.apply(&e.memo)
                e.touch(by: ctx.device, at: ctx.now)
            }
            if let scope = scope.value { f.setScope(scope, exam: exam) }
        }
    }
}

/// Removes the exam record and references to it; its folder and files stay.
@Action("exam rm", "시험 기록 지우기. 시험 폴더와 파일은 남는다. 범위 단원과 점수의 연결도 풀린다", effect: .removes,
        confirm: "시험 '{exam}'의 기록을 지웁니다. 폴더와 파일은 남습니다.", done: "시험 '{exam}'을(를) 지웠습니다",
        examples: ["folio exam rm EC4207/Quiz1 --dry-run"], phrases: ["시험 삭제"])
public struct ExamRemove {
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(exam, in: f.exams, .valueExam)
            f.exams.removeAll { $0.id == exam }
            for i in f.units.indices { f.units[i].examIds.removeAll { $0 == exam } }
            for i in f.scores.indices where f.scores[i].examId == exam { f.scores[i].examId = nil }
        }
    }
}

@Action("exam plan add", "공부 계획에 날짜별 할 일 추가", effect: .creates, done: "공부 계획에 '{title}'을(를) 넣었습니다",
        examples: [#"folio exam plan add EC4207/중간고사 --day 2026-10-18 "트리 단원 복습""#], phrases: ["공부 계획", "시험 준비 계획", "날짜별 할 일"])
public struct ExamPlanAdd {
    @New var id: ExamPlanItem.ID
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID
    /// 할 일
    @Arg var title: String
    /// 날짜. 2026-10-18
    var day: LocalDate
    /// 이 단원을 공부하는 일
    var unit: FolioDomain.Unit.ID?

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                guard !e.plan.contains(where: { $0.id == id }) else { throw ActionError.rule(String(localized: .errorIdTakenPlanItem("\(id)"))) }
                e.plan.append(ExamPlanItem(id: id, day: day, title: title, target: unit.map { ExamPlanTarget(kind: .unit, id: $0) }))
                e.touch(by: ctx.device, at: ctx.now)
            }
        }
        ctx.made(id)
    }
}

@Action("exam plan rm", "공부 계획 항목 지우기", effect: .removes, confirm: "공부 계획 항목 '{item}'을(를) 지웁니다.",
        done: "공부 계획에서 '{item}'을(를) 지웠습니다", cli: .manual)
public struct ExamPlanRemove {
    @Arg var course: Course.ID
    @Arg var exam: Exam.ID
    /// 항목
    @Arg var item: ExamPlanItem.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.exams, exam) { e in
                guard e.plan.contains(where: { $0.id == item }) else { throw ActionError.notFound(String(localized: .errorNotFoundPlanItem)) }
                e.plan.removeAll { $0.id == item }
                e.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}

/// Checks a plan item off or back on; the latest line across every device's log wins.
@Action("exam plan-check", "공부 계획 항목 끝내기, --undo면 되돌리기", effect: .logs, done: "공부 계획 항목 '{item}'을(를) 표시했습니다", cli: .manual)
public struct ExamPlanCheck {
    @Arg var course: Course.ID
    @Arg var item: ExamPlanItem.ID
    @Off("undo") var done = true

    public func run(_ ctx: ActionContext) throws {
        guard try ctx.file(course).exams.contains(where: { $0.plan.contains { $0.id == item } }) else {
            throw ActionError.notFound(String(localized: .errorNotFoundPlanItem))
        }
        try ctx.log(PlanCheckEvent(itemId: item, done: done), course: course)
    }
}

/// The exam's summary note, created from the template the first time.
@Action("exam summary", "시험 종합 정리 노트. 없으면 템플릿으로 만든다", effect: .creates, done: "시험 '{exam}'의 종합 정리 노트",
        examples: ["folio exam summary EC4207/중간고사"], phrases: ["시험 정리 노트", "요약 노트", "족보 정리"])
public struct ExamSummary {
    @New var note: Note.ID
    @Arg var course: Course.ID
    /// 시험
    @Arg var exam: Exam.ID

    public func run(_ ctx: ActionContext) throws {
        let file = try ctx.file(course)
        let exam = file.exams[try index(exam, in: file.exams, .valueExam)]
        if let existing = try ctx.store(course).notes().first(where: { $0.meta.kind == .examSummary && $0.meta.examId == exam.id })?.meta.id {
            ctx.made(existing)
            return
        }
        let settings = try ctx.settings()
        let title = "\(exam.title) 종합 정리"
        let body = NoteTemplate.body(for: .examSummary, title: title, sections: settings.noteSections(for: .examSummary))
        let meta = NoteMeta(id: note, kind: .examSummary, unitIds: exam.scopeUnitIds, examId: exam.id, math: settings.newNoteMath)
        ctx.made(try ctx.createNote(course, title: title, meta: meta, body: body) ?? note)
    }
}

// MARK: Assignments

/// The last moment a repeating assignment may fall: the end of the term's last day.
func repeatEnd(_ ctx: ActionContext, course: UUID) throws -> Date? {
    try ctx.semester(of: ctx.file(course).course)?.end?.date(in: ctx.calendar)
        .flatMap { ctx.calendar.date(byAdding: .day, value: 1, to: $0) }?.addingTimeInterval(-1)
}

/// A new assignment plus its standard folder when the title names one (`HW 3` → `Assignments/HW3`).
@Action("assignment add", "과제 추가. 제목이 HW3처럼 표준 이름이면 Assignments 폴더도 만든다", effect: .creates, done: "과제 '{title}'을(를) 추가했습니다",
        examples: [#"folio assignment add EC4207 "HW 3" --due "2026-11-04 23:59""#, #"folio assignment add EC4207 "Weekly Quiz" --due 2026-11-02 --repeats weekly --dry-run"#],
        phrases: ["과제 추가", "숙제 생김", "새 과제"])
public struct AssignmentAdd {
    @New var id: Assignment.ID
    /// 과목
    @Arg var course: Course.ID
    /// 과제 제목
    @Arg var title: String
    /// 마감 일시
    var due: Date?
    /// 반복
    var repeats: AssignmentRepeat?

    public func run(_ ctx: ActionContext) throws {
        guard !title.isEmpty else { throw ActionError.rule(String(localized: .errorAssignmentTitleEmpty)) }
        try ctx.edit(course) { f in
            var a = Assignment(id: id, device: ctx.device, at: ctx.now, title: title, due: due)
            a.repeats = repeats
            f.assignments.append(a)
        }
        if AssignmentKind.parse(title: title) != nil {
            let path = AssignmentFiles.path(of: Assignment(device: ctx.device, at: ctx.now, title: title))
            let store = try ctx.store(course)
            if !FileManager.default.fileExists(atPath: store.fileURL(path).path) {
                try ctx.io(Change(.added, ctx.relative(store.fileURL(path)) + "/")) { try store.ensureFolder(assignmentTitle: title) }
            }
        }
        ctx.made(id)
    }
}

/// Everything the assignment sheet edits, with its scores: one per component it counts toward. The command works out
/// the covered components and scores from its flags, so it is written by hand.
@Action("assignment set", "과제의 제목, 마감, 상태, 성적 항목, 메모 바꾸기. 준 것만 바뀐다", done: "과제 '{assignment}'을(를) 바꿨습니다",
        phrases: ["미뤄졌", "연기", "마감일", "마감 변경", "기한 연장", "과제 메모", "과제 이름"], cli: .manual)
public struct AssignmentSave {
    public struct Score: Codable, Sendable, Equatable {
        public var component: UUID
        public var score: Double
        public var max: Double
        public init(component: UUID, score: Double, max: Double) {
            (self.component, self.score, self.max) = (component, score, max)
        }
    }
    @Arg var course: Course.ID
    @Arg var assignment: Assignment.ID
    var title: String
    var due: Date?
    var status: AssignmentStatus
    var repeats: AssignmentRepeat?
    var componentId: GradeComponent.ID?
    var componentGroup: String?
    var memo: String
    /// Every component the target covers; one left out loses its score.
    var components: [GradeComponent.ID]
    var scores: [Score]

    public func run(_ ctx: ActionContext) throws {
        guard !title.isEmpty else { throw ActionError.rule(String(localized: .errorAssignmentTitleEmpty)) }
        guard scores.allSatisfy({ $0.max > 0 }) else { throw ActionError.rule(String(localized: .errorAssignmentMaxScore)) }
        let end = try repeatEnd(ctx, course: course)
        // A weekly series shares one title, so each score is told apart by its date.
        let entryTitle = repeats == .weekly ? due.map { "\(title) \($0.formatted(.dateTime.month(.defaultDigits).day()))" } ?? title : title
        try ctx.edit(course) { f in
            let i = try index(assignment, in: f.assignments, .valueAssignment)
            f.assignments[i].title = title
            f.assignments[i].due = due
            f.assignments[i].repeats = repeats
            f.assignments[i].componentId = componentId
            f.assignments[i].componentGroup = componentGroup
            f.assignments[i].memo = memo
            f.assignments[i].touch(by: ctx.device, at: ctx.now)
            var kept = Set<UUID>()
            for s in scores where components.contains(s.component) {
                kept.insert(s.component)
                if let j = f.scores.firstIndex(where: { $0.assignmentId == assignment && $0.componentId == s.component }) {
                    f.scores[j].title = entryTitle
                    f.scores[j].score = s.score
                    f.scores[j].max = s.max
                    f.scores[j].touch(by: ctx.device, at: ctx.now)
                } else {
                    var entry = ScoreEntry(device: ctx.device, at: ctx.now, componentId: s.component, title: entryTitle, score: s.score, max: s.max)
                    entry.assignmentId = assignment
                    f.scores.append(entry)
                }
            }
            f.scores.removeAll { $0.assignmentId == assignment && !kept.contains($0.componentId) }
            // A score means it was graded, whatever the menu said.
            f.assignments[i].status = kept.isEmpty ? status : .graded
            f.continueRepeating(assignment, until: end, calendar: ctx.calendar, device: ctx.device, now: ctx.now)
        }
    }
}

/// Handing in a weekly assignment makes the next one.
@Action("assignment status", "과제 상태 바꾸기. 매주 과제를 내면 다음 과제가 생긴다", done: "과제 '{assignment}'의 상태를 {status}(으)로 바꿨습니다",
        examples: ["folio assignment status EC4207/HW3 submitted"], phrases: ["제출", "냈어", "다 했어", "하는 중", "채점됨"])
public struct AssignmentStatusSet {
    /// 과목
    @Arg var course: Course.ID
    /// 과제
    @Arg var assignment: Assignment.ID
    /// 상태
    @Arg var status: AssignmentStatus

    public func run(_ ctx: ActionContext) throws {
        let end = try repeatEnd(ctx, course: course)
        try ctx.edit(course) { f in
            let i = try index(assignment, in: f.assignments, .valueAssignment)
            f.assignments[i].status = status
            f.continueRepeating(assignment, until: end, calendar: ctx.calendar, device: ctx.device, now: ctx.now)
        }
    }
}

/// The assignment and its scores; its folder and files stay.
@Action("assignment rm", "과제와 그 점수 지우기. 과제 폴더와 파일은 남는다", effect: .removes,
        confirm: "과제 '{assignment}'과(와) 그 점수를 지웁니다. 폴더와 파일은 남습니다.", done: "과제 '{assignment}'을(를) 지웠습니다",
        examples: ["folio assignment rm EC4207/HW3 --dry-run"], phrases: ["과제 삭제", "과제 지우기"])
public struct AssignmentRemove {
    /// 과목
    @Arg var course: Course.ID
    /// 과제
    @Arg var assignment: Assignment.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(assignment, in: f.assignments, .valueAssignment)
            f.assignments.removeAll { $0.id == assignment }
            f.scores.removeAll { $0.assignmentId == assignment }
        }
    }
}

// MARK: Grades

@Action("score add", "점수 추가", effect: .creates, done: "점수 '{id}'을(를) 추가했습니다",
        examples: ["folio score add EC4207 --component 과제 --title HW1 --score 9 --max 10",
                   "folio score add EC4207 --component 중간고사 --score 72 --max 100 --mean 61.5 --std-dev 12 --date 2026-10-21 --dry-run"],
        phrases: ["점수 입력", "점수 기록", "성적 나왔어", "몇 점 받았어", "평균 표준편차"])
public struct ScoreAdd {
    @New var id: ScoreEntry.ID
    /// 과목
    @Arg var course: Course.ID
    /// 성적 항목
    var component: GradeComponent.ID
    /// 제목. 예: HW1
    var title: String = ""
    /// 받은 점수
    var score: Double
    /// 만점
    var max: Double
    /// 평균
    var mean: Double?
    /// 표준편차
    var stdDev: Double?
    /// 날짜. 2026-10-21
    var date: LocalDate?
    /// 점수가 나온 시험
    var exam: Exam.ID?
    /// 점수가 나온 과제
    var assignment: Assignment.ID?
    /// 면제. 계산에서 뺀다
    var excused = false

    public func run(_ ctx: ActionContext) throws {
        var entry = ScoreEntry(id: id, device: ctx.device, at: ctx.now, componentId: component, title: title, score: score, max: max, mean: mean, stdDev: stdDev,
                               excused: excused)
        (entry.date, entry.examId, entry.assignmentId) = (date, exam, assignment)
        try ctx.edit(course) { f in
            guard !f.scores.contains(where: { $0.id == id }) else { throw ActionError.rule(String(localized: .errorIdTakenScore("\(id)"))) }
            f.scores.append(entry)
        }
        ctx.made(id)
    }
}

@Action("score set", "점수 고치기. 준 것만 바꾼다", done: "점수 '{score}'을(를) 고쳤습니다",
        examples: ["folio score set EC4207/HW1 --value 10", "folio score set EC4207/HW1 --excused true",
                   "folio score set EC4207/HW1 --date none --dry-run"],
        phrases: ["잘못 넣", "틀리게 넣", "점수 고치기", "점수 수정", "점수 정정"])
public struct ScoreSet {
    @Arg var course: Course.ID
    /// 점수 제목
    @Arg var score: ScoreEntry.ID
    /// 성적 항목
    var component: Patch<GradeComponent.ID>
    /// 제목
    var title: Patch<String>
    /// 받은 점수
    var value: Patch<Double>
    /// 만점
    var max: Patch<Double>
    /// 평균
    var mean: Patch<Double?>
    /// 표준편차
    var stdDev: Patch<Double?>
    /// 날짜
    var date: Patch<LocalDate?>
    /// 점수가 나온 시험
    var exam: Patch<Exam.ID?>
    /// 점수가 나온 과제
    var assignment: Patch<Assignment.ID?>
    /// 면제 여부
    var excused: Patch<Bool>

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.scores, score) { e in
                component.apply(&e.componentId)
                title.apply(&e.title)
                value.apply(&e.score)
                max.apply(&e.max)
                mean.apply(&e.mean)
                stdDev.apply(&e.stdDev)
                date.apply(&e.date)
                exam.apply(&e.examId)
                assignment.apply(&e.assignmentId)
                excused.apply(&e.excused)
                e.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}

@Action("score rm", "점수 지우기", effect: .removes, confirm: "점수 '{score}'을(를) 지웁니다.", done: "점수 '{score}'을(를) 지웠습니다",
        examples: ["folio score rm EC4207/HW1 --dry-run"], phrases: ["점수 삭제"])
public struct ScoreRemove {
    @Arg var course: Course.ID
    /// 점수 제목
    @Arg var score: ScoreEntry.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { try $0.remove(ScoreEntry.self, score) }
    }
}

@Action("component add", "성적 항목 추가. 맨 뒤에 붙는다", done: "성적 항목 '{name}'을(를) 추가했습니다",
        examples: ["folio component add EC4207 과제 --weight 30",
                   "folio component add EC4207 퀴즈 --weight 20 --aggregation dropLowest:1 --expected-count 5 --dry-run"],
        phrases: ["평가 항목 추가"])
public struct ComponentAdd {
    @New var id: GradeComponent.ID
    /// 과목
    @Arg var course: Course.ID
    /// 항목 이름
    @Arg var name: String
    /// 비중(%)
    var weight: Double
    /// 점수를 묶는 방식. sum, mean, single, dropLowest:<n>, bestOf:<n>
    var aggregation: Aggregation = .sum
    /// 예정된 점수 개수
    var expectedCount: Int?
    /// 강의계획서의 묶음 제목
    var group: String?

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            guard !f.components.contains(where: { $0.id == id }) else { throw ActionError.rule(String(localized: .errorIdTakenComponent("\(id)"))) }
            let order = (f.components.map(\.order).max() ?? -1) + 1
            var c = GradeComponent(id: id, device: ctx.device, at: ctx.now, name: name, weight: weight, order: order, aggregation: aggregation,
                                   expectedCount: expectedCount)
            c.group = group
            f.components.append(c.normalized)
        }
        ctx.made(id)
    }
}

@Action("component set", "성적 항목 고치기. 준 것만 바꾼다", done: "성적 항목 '{component}'을(를) 고쳤습니다",
        examples: ["folio component set EC4207/과제 --weight 25", "folio component set EC4207/퀴즈 --aggregation bestOf:3",
                   "folio component set EC4207/퀴즈 --group none --dry-run"],
        phrases: ["비율 바꾸기", "반영 비율", "항목 이름"])
public struct ComponentSet {
    @Arg var course: Course.ID
    /// 항목 이름
    @Arg var component: GradeComponent.ID
    /// 이름
    var name: Patch<String>
    /// 비중(%)
    var weight: Patch<Double>
    /// 점수를 묶는 방식
    var aggregation: Patch<Aggregation>
    /// 예정된 점수 개수
    var expectedCount: Patch<Int?>
    /// 강의계획서의 묶음 제목
    var group: Patch<String?>

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            try f.update(\.components, component) { c in
                name.apply(&c.name)
                weight.apply(&c.weight)
                aggregation.apply(&c.aggregation)
                expectedCount.apply(&c.expectedCount)
                group.apply(&c.group)
                c = c.normalized
                c.touch(by: ctx.device, at: ctx.now)
            }
        }
    }
}

@Action("component rm", "성적 항목과 그 점수 지우기. 과제와 시험은 남고 연결만 풀린다", effect: .removes,
        confirm: "성적 항목 '{component}'과(와) 그 점수를 지웁니다. 과제와 시험은 남습니다.", done: "성적 항목 '{component}'을(를) 지웠습니다",
        examples: ["folio component rm EC4207/퀴즈 --dry-run"], phrases: ["평가 항목 삭제"])
public struct ComponentRemove {
    @Arg var course: Course.ID
    /// 항목 이름
    @Arg var component: GradeComponent.ID

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            _ = try index(component, in: f.components, .valueComponent)
            f.components.removeAll { $0.id == component }
            f.scores.removeAll { $0.componentId == component }
            for i in f.assignments.indices where f.assignments[i].componentId == component { f.assignments[i].componentId = nil }
            for i in f.exams.indices where f.exams[i].componentId == component { f.exams[i].componentId = nil }
        }
    }
}

/// Swaps a component with its neighbor and renumbers all, since imported components may share one `order`.
@Action("component move", "성적 항목을 한 칸 위나 아래로", done: "성적 항목 '{component}'을(를) 옮겼습니다", cli: .manual)
public struct ComponentMove {
    @Arg var course: Course.ID
    @Arg var component: GradeComponent.ID
    /// -1이면 위로, 1이면 아래로
    var by: Int

    public func run(_ ctx: ActionContext) throws {
        try ctx.edit(course) { f in
            var ids = f.components.sorted { $0.order < $1.order }.map(\.id)
            guard let i = ids.firstIndex(of: component) else { throw ActionError.notFound(String(localized: .errorNotFoundComponent)) }
            guard ids.indices.contains(i + by) else { return }
            ids.swapAt(i, i + by)
            for j in f.components.indices {
                let order = ids.firstIndex(of: f.components[j].id)!
                if f.components[j].order != order {
                    f.components[j].order = order
                    f.components[j].touch(by: ctx.device, at: ctx.now)
                }
            }
        }
    }
}

/// Attendance caps, minimum attendance, late rule, top-grade share and the syllabus's own words.
@Action("component policy", "성적 규칙 바꾸기", done: "성적 규칙을 바꿨습니다", cli: .manual)
public struct PolicySet {
    @Arg var course: Course.ID
    /// 성적 규칙 전체
    var policy: GradePolicy

    public func run(_ ctx: ActionContext) throws {
        var policy = policy
        policy.attendanceCap.sort { $0.absences < $1.absences }
        try ctx.edit(course) { $0.policy = policy }
    }
}

extension GradeComponent {
    var normalized: GradeComponent {
        var c = self
        c.name = c.name.trimmingCharacters(in: .whitespaces)
        c.group = c.group?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        // A single score is one by definition.
        if c.aggregation == .single { c.expectedCount = nil }
        return c
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
