import FolioCore
import Foundation

public enum ExamPlan {
    // 이벤트는 여러 기기의 로그에서 순서 없이 들어온다.
    public static func done(_ events: [(at: Date, event: PlanCheckEvent)]) -> Set<UUID> {
        var latest: [UUID: (at: Date, done: Bool)] = [:]
        for (at, e) in events where latest[e.itemId].map({ at >= $0.at }) ?? true {
            latest[e.itemId] = (at, e.done)
        }
        return Set(latest.filter(\.value.done).keys)
    }

    // 계획을 놓은 결과다. 액션이 시험에 그대로 쓴다.
    public struct Placement: Sendable, Equatable {
        public var plan: [ExamPlanItem]
        public var period: ExamPlanPeriod
        public var basis: ExamPlanBasis
    }
}

extension Exam {
    // 미루기는 그 항목만 다음 공부일로 옮긴다. 뒤 항목까지 밀면 시험 전에 끝나지 않으므로 다른 항목의 날은 바꾸지 않는다.
    // 못 하고 지난 항목은 오늘에 얹혀 있으므로 오늘의 다음 날로 간다.
    public static func postponedDay(of item: ExamPlanItem, today: LocalDate) -> LocalDate { max(item.day, today).adding(days: 1) }

    public mutating func postponePlan(_ items: [UUID], today: LocalDate) {
        for i in plan.indices where items.contains(plan[i].id) {
            plan[i].postponedFrom = plan[i].postponedFrom ?? plan[i].day
            plan[i].day = Self.postponedDay(of: plan[i], today: today)
            plan[i].edited = true
        }
    }

    // 앞당기기는 뒤 날의 항목을 오늘로 가져온다. 미뤘던 항목이 원래 날이나 그 앞으로 돌아오면 밀린 것이 아니다.
    public mutating func advancePlan(_ items: [UUID], today: LocalDate) {
        for i in plan.indices where items.contains(plan[i].id) && plan[i].day > today {
            plan[i].day = today
            plan[i].edited = true
            if let from = plan[i].postponedFrom, today <= from { plan[i].postponedFrom = nil }
        }
    }

    // 날짜를 직접 고른 항목은 그 날이 제날이다.
    public mutating func movePlan(_ items: [UUID], to day: LocalDate) {
        for i in plan.indices where items.contains(plan[i].id) {
            plan[i].day = day
            plan[i].edited = true
            plan[i].postponedFrom = nil
        }
    }
}

extension CourseStudy {
    // 계획의 진행을 정하는 한 곳이다. 지금은 손으로 한 체크와 풀기를 끝내며 남긴 체크뿐이라, 체크한 항목은 전체를 끝낸 것이고
    // 아니면 한 것이 없다.
    public func progress(of item: ExamPlanItem) -> PlanProgress {
        PlanProgress(done: manualChecks.contains(item.id) ? 1 : 0, total: 1)
    }

    // 어제 오답의 진행이다. 다시 맞힌 수는 아직 세지 않아, 남은 오답이 전체이고 한 것은 없다.
    public var wrongProgress: PlanProgress { PlanProgress(done: 0, total: wrongLeft) }

    public func isDone(_ item: ExamPlanItem) -> Bool { progress(of: item).isDone }

    // 과목에 남은 오답 문제 수다.
    public var wrongLeft: Int { allProblems.count { $0.status.needsWork } }

    // 모의고사는 족보 한 벌이므로 족보 묶음 수까지만 놓는다.
    public var mockSets: Int { file.problemSets.count { $0.source == .pastExam && !$0.problems.isEmpty } }

    // 기간을 주지 않으면 시험에 저장한 기간이고, 그것도 없으면 오늘부터 시험 전날까지다. 날짜가 없는 시험은 놓지 않는다.
    public func place(
        _ exam: Exam, period: ExamPlanPeriod? = nil, proofs: Set<UUID>, settings: Settings, calendar: Calendar
    ) -> ExamPlan.Placement? {
        guard let start = exam.start else { return nil }
        let examDay = settings.studyDay(of: start, calendar: calendar)
        let period = (period ?? exam.planPeriod ?? .standard(today: today, examDay: examDay)).fitted(before: examDay)
        let notes = file.planNotes(of: exam, proofs: proofs)
        let plan = ExamPlanner.plan(
            current: exam.plan, notes: notes, period: period, mocks: mockSets, today: today, examDay: examDay, isDone: isDone)
        return ExamPlan.Placement(plan: plan, period: period, basis: ExamPlanBasis(period: period, notes: notes, examDay: examDay))
    }

    // 시험 하나의 줄이다. 같은 노트의 같은 날 단계가 한 줄이고, 못 하고 지난 단계는 오늘 줄에 얹힌다.
    public func planRows(of exam: Exam) -> [PlanRow] {
        struct Key: Hashable {
            var target: UUID
            var day: LocalDate
        }
        let order = Dictionary(file.examNotes(of: exam).enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        var rows: [Key: PlanRow] = [:]
        var keys: [Key] = []
        for item in exam.plan where !item.isRemoved {
            let progress = progress(of: item)
            let done = progress.isDone
            let day = item.shownDay(today: today, done: done)
            // 노트의 단계는 노트로 묶고, 그 밖의 항목은 항목마다 한 줄이다.
            let key = Key(target: item.target.kind == .note ? item.target.id ?? item.id : item.id, day: day)
            let step = PlanRow.Step(item: item.id, stage: item.target.stage, progress: progress)
            let late = item.lateFrom(today: today, done: done)
            if var row = rows[key] {
                row.steps.append(step)
                row.lateFrom = [row.lateFrom, late].compactMap { $0 }.min()
                rows[key] = row
                continue
            }
            let kind: PlanRow.Kind =
                switch item.target.kind {
                case .note: .note(item.target.id ?? item.id)
                case .makeNote: .makeNote(unit: item.target.id ?? item.id)
                case .mock: .mock
                case .custom: .custom
                }
            let unit = item.target.kind == .makeNote ? item.target.id.flatMap { id in file.units.first { $0.id == id } } : nil
            rows[key] = PlanRow(
                id: "\(exam.id)-\(key.target)-\(day)", courseId: file.course.id, examId: exam.id, kind: kind, title: rowTitle(of: item),
                subject: unit?.title, day: day, lateFrom: late, steps: [step])
            keys.append(key)
        }
        func position(_ row: PlanRow) -> Int { if case .note(let id) = row.kind { order[id] ?? Int.max } else { 0 } }
        return keys.compactMap { rows[$0] }.map { row in
            var row = row
            row.steps.sort { ($0.stage ?? .read) < ($1.stage ?? .read) }
            return row
        }
        .enumerated().sorted { a, b in
            (a.element.day, a.element.kind.rank, position(a.element), a.offset) < (
                b.element.day, b.element.kind.rank, position(b.element), b.offset
            )
        }
        .map(\.element)
    }

    private func rowTitle(of item: ExamPlanItem) -> String {
        switch item.target.kind {
        case .note: item.target.id.flatMap { id in file.notes.first { $0.id == id } }?.title ?? String(localized: .examPlanTitleNote)
        case .makeNote: String(localized: .examPlanTitleMakeNote)
        case .mock, .custom: file.title(of: item)
        }
    }

    // 남은 오답이 있으면 오늘의 맨 앞 줄이다. 틀린 문제는 다음 공부일의 맨 앞에 해설 없이 다시 푼다.
    public var wrongRow: PlanRow? {
        let progress = wrongProgress
        guard progress.left > 0 else { return nil }
        return PlanRow(
            id: "wrong-\(file.course.id)", courseId: file.course.id, examId: nil, kind: .wrong(progress),
            title: String(localized: .examPlanTitleWrong), subject: nil, day: today, lateFrom: nil, steps: [])
    }

    // 지난 시험의 못 한 항목은 계획에서 뺀다. 시험이 끝나면 밀린 것이 아니라 끝난 것이다.
    public func plannedExams(now: Date, calendar: Calendar) -> [Exam] {
        file.exams.filter { !$0.plan.isEmpty && !$0.isOver(now: now, today: today, calendar: calendar) }
            .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    // 시험이 여럿이면 가까운 시험의 줄이 앞에 오고, 오늘의 줄은 종류로 다시 줄 세운다.
    public func planBoard(_ exams: [Exam]) -> PlanBoard {
        let rows = exams.flatMap(planRows(of:))
        let days = Set(rows.map(\.day).filter { $0 > today }).sorted()
        return PlanBoard.merged([
            PlanBoard(
                today: (wrongRow.map { [$0] } ?? []) + rows.filter { $0.day == today },
                next: days.map { day in PlanBoard.Day(day: day, rows: rows.filter { $0.day == day }) })
        ])
    }
}

extension CourseFile {
    // 앱이 놓은 항목은 제목을 저장하지 않고 대상에서 이름을 만든다. 노트 이름을 바꾸면 계획에도 바로 보인다.
    public func title(of item: ExamPlanItem) -> String {
        if !item.title.isEmpty { return item.title }
        switch item.target.kind {
        case .note:
            let name = item.target.id.flatMap { id in notes.first { $0.id == id } }?.title ?? String(localized: .examPlanTitleNote)
            return item.target.stage.map { String(localized: .examPlanTitleStage(name, $0.label)) } ?? name
        case .makeNote:
            guard let unit = item.target.id.flatMap({ id in units.first { $0.id == id } }) else {
                return String(localized: .examPlanTitleMakeNote)
            }
            return String(localized: .examPlanTitleMakeNoteFor(unit.title))
        case .mock: return String(localized: .examPlanTitleMock)
        case .custom: return item.title
        }
    }
}
