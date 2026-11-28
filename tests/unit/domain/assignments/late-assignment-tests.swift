import FolioDomain
import Foundation
import PropertyBased
import Testing

struct LateAssignmentTests {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return c
    }()
    let device = UUID()

    static func at(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second)) ?? .distantPast
    }

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date { Self.at(day, hour, minute, second) }

    func file(_ assignments: [Assignment], rule: LateRule? = nil) -> CourseFile {
        var f = CourseFile(course: Course(device: device, at: at(1, 9), title: "그래프 이론"))
        f.assignments = assignments
        f.policy.lateRule = rule
        return f
    }

    // MARK: Late days

    @Test func aDayLateStartsOneSecondAfterTheDeadline() {
        let due = at(10, 23, 59)
        #expect(LateRule.lateDays(due: due, at: due - 1) == 0)
        #expect(LateRule.lateDays(due: due, at: due) == 0)
        #expect(LateRule.lateDays(due: due, at: due + 1) == 1)
        #expect(LateRule.lateDays(due: due, at: due + 86_400) == 1)
        #expect(LateRule.lateDays(due: due, at: due + 86_401) == 2)
    }

    // 하루는 공부일이 아니라 마감에서 센 24시간이라, 하루 경계(새벽 4시)를 넘어도 늦은 날수는 그대로다.
    @Test func theDayBoundaryDoesNotAddALateDay() {
        let due = at(10, 23, 59)
        #expect(LateRule.lateDays(due: due, at: at(11, 3, 59)) == 1)
        #expect(LateRule.lateDays(due: due, at: at(11, 4, 0)) == 1)
        #expect(LateRule.lateDays(due: due, at: at(11, 23, 59)) == 1)
        #expect(LateRule.lateDays(due: due, at: at(12, 0, 0)) == 2)
    }

    // MARK: Ceiling, by hand

    @Test func tenPercentADayForThreeDays() {
        let rule = LateRule(percentPerDay: 10, days: 3)
        #expect(rule.ceiling(lateDays: 0) == 1)
        #expect(rule.ceiling(lateDays: 1) == 0.9)
        #expect(abs(rule.ceiling(lateDays: 3) - 0.7) < 1e-9)
        #expect(rule.ceiling(lateDays: 4) == 0)
    }

    @Test func withoutALimitThePenaltyRunsDownToZero() {
        let rule = LateRule(percentPerDay: 30)
        #expect(abs(rule.ceiling(lateDays: 3) - 0.1) < 1e-9)
        #expect(rule.ceiling(lateDays: 4) == 0)
    }

    @Test func noLateSubmissionsMeansZeroOnTheFirstLateSecond() {
        let rule = LateRule(percentPerDay: 0, days: 0)
        #expect(rule.ceiling(lateDays: 0) == 1)
        #expect(rule.ceiling(lateDays: 1) == 0)
        #expect(!rule.acceptsLate)
    }

    @Test func aRuleAcceptsLateWorkOnlyIfADayLateStillScores() {
        #expect(LateRule(percentPerDay: 10, days: 3).acceptsLate)
        #expect(LateRule(percentPerDay: 10).acceptsLate)
        #expect(LateRule(percentPerDay: 0).acceptsLate)
        #expect(!LateRule(percentPerDay: 10, days: 0).acceptsLate)
        #expect(!LateRule(percentPerDay: 100).acceptsLate)
        #expect(!LateRule(percentPerDay: 100, days: 5).acceptsLate)
    }

    @Test func theNextDropIsTheNextWholeDayAfterTheDeadline() {
        let due = at(10, 23, 59)
        let rule = LateRule(percentPerDay: 10, days: 2)
        #expect(rule.nextDrop(due: due, at: due + 60) == due + 86_400)
        #expect(rule.nextDrop(due: due, at: due + 86_400 + 60) == due + 2 * 86_400)
        #expect(rule.nextDrop(due: due, at: due + 2 * 86_400 + 60) == nil)
    }

    // MARK: Ceiling, properties

    static let rule = zip(Gen.int(in: 0...100), Gen.int(in: -1...10)).map { percent, days in
        LateRule(percentPerDay: Double(percent), days: days < 0 ? nil : days)
    }
    static let lateDays = Gen.int(in: 0...30)

    @Test func theCeilingStaysBetweenZeroAndFullMarks() async {
        await propertyCheck(input: Self.rule, Self.lateDays) { rule, days in
            #expect((0...1).contains(rule.ceiling(lateDays: days)))
        }
    }

    @Test func handingInLaterNeverEarnsMore() async {
        await propertyCheck(input: Self.rule, Self.lateDays, Self.lateDays) { rule, a, b in
            #expect(rule.ceiling(lateDays: max(a, b)) <= rule.ceiling(lateDays: min(a, b)))
        }
    }

    @Test func aRuleThatRefusesLateWorkGivesZeroOnEveryLateDay() async {
        await propertyCheck(input: Self.rule, Gen.int(in: 1...30)) { rule, days in
            if !rule.acceptsLate { #expect(rule.ceiling(lateDays: days) == 0) }
        }
    }

    @Test func pastTheAcceptedDaysItIsZero() async {
        await propertyCheck(input: Self.rule, Gen.int(in: 1...10)) { rule, extra in
            guard let days = rule.days else { return }
            #expect(rule.ceiling(lateDays: days + extra) == 0)
        }
    }

    @Test func lateDaysGrowWithTheSubmissionTime() async {
        let due = at(10, 23, 59)
        await propertyCheck(input: Gen.int(in: -200_000...2_000_000), Gen.int(in: -200_000...2_000_000)) { a, b in
            let (early, late) = (due + Double(min(a, b)), due + Double(max(a, b)))
            #expect(LateRule.lateDays(due: due, at: early) <= LateRule.lateDays(due: due, at: late))
            #expect((LateRule.lateDays(due: due, at: early) == 0) == (early <= due))
        }
    }

    // MARK: Submission time

    @Test func submittingStampsTheTimeOnceAndUndoingClearsIt() {
        var a = Assignment(device: device, at: at(1, 9), title: "HW3", due: at(10, 23, 59))
        a.set(.submitted, now: at(10, 22))
        #expect(a.submittedAt == at(10, 22))
        a.set(.submitted, now: at(11, 9))
        #expect(a.submittedAt == at(10, 22))
        a.set(.graded, now: at(12, 9))
        #expect(a.submittedAt == at(10, 22) && a.status == .graded)
        a.set(.todo, now: at(12, 10))
        #expect(a.submittedAt == nil)
        a.set(.submitted, submittedAt: at(11, 1, 20), now: at(13, 9))
        #expect(a.submittedAt == at(11, 1, 20))
        a.set(.missed, now: at(13, 10))
        #expect(a.submittedAt == nil && a.status == .missed && !a.status.isOpen)
    }

    @Test func gradingWithoutSubmittingDoesNotMakeUpATime() {
        var a = Assignment(device: device, at: at(1, 9), title: "HW3", due: at(10, 23, 59))
        a.set(.graded, now: at(12, 9))
        #expect(a.submittedAt == nil)
    }

    // MARK: Lateness

    @Test func latenessComesFromTheSubmissionTimeAndFollowsTheDeadline() {
        var a = Assignment(device: device, at: at(1, 9), title: "HW3", due: at(10, 23, 59))
        a.set(.submitted, now: at(11, 1))
        var f = file([a], rule: LateRule(percentPerDay: 20, days: 3))
        #expect(f.lateness(of: f.assignments[0], at: at(20, 9)) == Lateness(days: 1, ceiling: 0.8, nextDrop: nil))
        f.assignments[0].due = at(11, 23, 59)
        #expect(f.lateness(of: f.assignments[0], at: at(20, 9)) == nil)
    }

    @Test func anOpenOverdueAssignmentIsLateAsOfNow() {
        let a = Assignment(device: device, at: at(1, 9), title: "HW3", due: at(10, 23, 59))
        let f = file([a], rule: LateRule(percentPerDay: 10, days: 3))
        #expect(f.lateness(of: a, at: at(10, 23, 58)) == nil)
        #expect(f.lateness(of: a, at: at(11, 0)) == Lateness(days: 1, ceiling: 0.9, nextDrop: at(11, 23, 59)))
        #expect(f.lateness(of: a, at: at(15, 0))?.ceiling == 0)
    }

    @Test func anAssignmentsOwnRuleBeatsTheCourses() {
        var a = Assignment(device: device, at: at(1, 9), title: "Project", due: at(10, 23, 59))
        a.lateRule = LateRule(percentPerDay: 50, days: 1)
        let f = file([a], rule: LateRule(percentPerDay: 10, days: 3))
        #expect(f.lateness(of: a, at: at(11, 9))?.ceiling == 0.5)
        #expect(f.lateness(of: a, at: at(12, 9))?.ceiling == 0)
    }

    @Test func withoutARuleItIsLateWithoutACeiling() {
        let a = Assignment(device: device, at: at(1, 9), title: "HW3", due: at(10, 23, 59))
        #expect(file([a]).lateness(of: a, at: at(12, 9)) == Lateness(days: 2, ceiling: nil, nextDrop: nil))
    }

    @Test func missedAndUndatedAssignmentsAreNeverLate() {
        var missed = Assignment(device: device, at: at(1, 9), title: "HW3", due: at(10, 23, 59))
        missed.set(.missed, now: at(11, 9))
        let undated = Assignment(device: device, at: at(1, 9), title: "HW4")
        let f = file([missed, undated], rule: LateRule(percentPerDay: 10))
        #expect(f.lateness(of: missed, at: at(12, 9)) == nil && f.lateness(of: undated, at: at(12, 9)) == nil)
        #expect(f.overdueAssignments(at: at(12, 9)).isEmpty)
    }

    // MARK: Grades

    // 과제 두 개짜리 성적 요소에 HW2는 9/10으로 기록했고, HW3은 마감(10일 23:59)이 지났다. `score`를 주면 HW3을 `submitted`에
    // 내고 그 점수를 기록한다.
    func grades(rule: LateRule?, submitted: Date? = nil, score: Double? = nil) -> CourseFile {
        let component = GradeComponent(device: device, at: at(1, 9), name: "과제", weight: 100, expectedCount: 2)
        var hw2 = Assignment(device: device, at: at(1, 9), title: "HW2", due: at(3, 23, 59))
        hw2.set(.graded, submittedAt: at(3, 9), now: at(3, 9))
        hw2.componentId = component.id
        var hw3 = Assignment(device: device, at: at(1, 9), title: "HW3", due: at(10, 23, 59))
        hw3.componentId = component.id
        if let submitted { hw3.set(.submitted, now: submitted) }
        var entries = [ScoreEntry(device: device, at: at(1, 9), componentId: component.id, title: "HW2", score: 9, max: 10)]
        entries[0].assignmentId = hw2.id
        if let score {
            var entry = ScoreEntry(device: device, at: at(1, 9), componentId: component.id, title: "HW3", score: score, max: 10)
            entry.assignmentId = hw3.id
            entries.append(entry)
        }
        var f = file([hw2, hw3], rule: rule)
        f.components = [component]
        f.scores = entries
        return f
    }

    // 하루 20%, 사흘까지 받는다. 이틀 늦은 HW3은 최대 6점이라 예상은 (9 + 6) / 20 = 75점, 받는 기간을 넘기면 (9 + 0) / 20 = 45점이다.
    // 규칙이 없거나 상한이 예상 비율(0.9)보다 높으면 90점 그대로다. 확보한 점수는 기록한 HW2만 세어 45점으로 같다.
    @Test func anUnscoredLateAssignmentCapsTheProjection() {
        let rule = LateRule(percentPerDay: 20, days: 3)
        #expect(grades(rule: rule).courseScore(at: at(12, 9)).projected == 75)
        #expect(grades(rule: rule, submitted: at(12, 9)).courseScore(at: at(20, 9)).projected == 75)
        #expect(grades(rule: rule).courseScore(at: at(14, 9)).projected == 45)
        #expect(grades(rule: rule).courseScore(at: at(10, 23)).projected == 90)
        #expect(grades(rule: nil).courseScore(at: at(12, 9)).projected == 90)
        #expect(grades(rule: LateRule(percentPerDay: 5)).courseScore(at: at(11, 9)).projected == 90)
        #expect(grades(rule: rule).courseScore(at: at(14, 9)).secured == 45)
    }

    // 못 냄은 점수를 적기 전까지 0점이라, 규칙이 없어도 예상은 (9 + 0) / 20 = 45점이다. 못 냄을 눌러 예상이 오르지 않는다.
    @Test func aMissedAssignmentCountsAsZeroInTheProjection() {
        for rule in [LateRule(percentPerDay: 10, days: 3), nil] {
            var f = grades(rule: rule)
            #expect(f.courseScore(at: at(11, 9)).projected ?? 0 > 45)
            f.assignments[1].set(.missed, now: at(11, 9))
            #expect(f.courseScore(at: at(11, 9)).projected == 45 && f.courseScore(at: at(11, 9)).secured == 45)
        }
    }

    // 기록한 점수는 감점이 들어간 최종 점수라, 늦게 낸 과제의 9점도 깎지 않는다(사용자, 2026-11-15).
    @Test func aRecordedLateScoreIsFinal() {
        let f = grades(rule: LateRule(percentPerDay: 20, days: 3), submitted: at(14, 9), score: 9)
        #expect(f.lateness(of: f.assignments[1], at: at(20, 9)) == Lateness(days: 4, ceiling: nil))
        #expect(f.courseScore(at: at(20, 9)).secured == 90 && f.courseScore(at: at(20, 9)).projected == 90)
    }

    @Test func lateCeilingsNeverRaiseTheProjectionOrTouchTheSecuredScore() async {
        await propertyCheck(input: Self.rule, Gen.int(in: 0...(12 * 86_400)), Gen.int(in: 0...1)) { rule, late, submitted in
            let now = at(10, 23, 59) + Double(late)
            let sent = submitted == 1 ? now : nil
            let plain = grades(rule: nil, submitted: sent).courseScore(at: now)
            let capped = grades(rule: rule, submitted: sent).courseScore(at: now)
            #expect(capped.secured == plain.secured)
            #expect((capped.projected ?? 0) <= (plain.projected ?? 0) + 1e-9 && (capped.projected ?? 0) >= capped.secured - 1e-9)
        }
    }

    // MARK: Today

    // 마감은 실제 시각으로 센다. 하루 경계(새벽 4시) 직전과 직후 모두, 지난 마감은 마감 지남으로, 남은 마감은 마감으로 간다.
    @Test func overdueAssignmentsLeaveTheDeadlinesAroundTheDayBoundary() {
        let past = Assignment(device: device, at: at(1, 9), title: "HW3", due: at(16, 3, 58))
        let next = Assignment(device: device, at: at(1, 9), title: "HW4", due: at(16, 4, 1))
        var done = Assignment(device: device, at: at(1, 9), title: "HW2", due: at(15, 23, 59))
        done.set(.submitted, now: at(16, 1))
        let f = file([past, next, done])
        let settings = Settings()

        let before = TodaySummary.build(courses: [f], now: at(16, 3, 59), settings: settings, calendar: Self.calendar)
        #expect(before.overdue.map(\.assignment.title) == ["HW3"])
        #expect(before.deadlines.map(\.assignment.title) == ["HW4"] && before.deadlines[0].isToday == false)

        let after = TodaySummary.build(courses: [f], now: at(16, 4, 0), settings: settings, calendar: Self.calendar)
        #expect(after.overdue.map(\.assignment.title) == ["HW3"])
        #expect(after.deadlines.map(\.assignment.title) == ["HW4"] && after.deadlines[0].isToday)

        let passed = TodaySummary.build(courses: [f], now: at(16, 4, 1, 1), settings: settings, calendar: Self.calendar)
        #expect(passed.overdue.map(\.assignment.title) == ["HW3", "HW4"] && passed.deadlines.isEmpty)
    }

    // MARK: Notifications

    @Test func overdueAssignmentsAreRemindedOnceADay() {
        let late = Assignment(device: device, at: at(1, 9), title: "HW3", due: at(14, 23, 59))
        let soon = Assignment(device: device, at: at(1, 9), title: "HW4", due: at(16, 12))
        var done = Assignment(device: device, at: at(1, 9), title: "HW2", due: at(13, 23, 59))
        done.set(.missed, now: at(14, 9))
        let f = file([late, soon, done])
        var settings = NotificationSettings()
        settings[.assignmentDue].on = false
        let plan = NotificationPlan.build(
            courses: [f], settings: settings, now: at(15, 10, 30), calendar: Self.calendar, days: 3)
        #expect(plan.map(\.date) == [at(16, 10), at(17, 10), at(18, 10)])
        #expect(plan.map(\.kind) == [.assignmentOverdue(count: 1), .assignmentOverdue(count: 2), .assignmentOverdue(count: 2)])
        #expect(plan[0].subject == "HW3" && plan[0].courseId == f.course.id && plan[1].subject.isEmpty)
        #expect(Set(plan.map(\.id)).count == plan.count)

        settings[.assignmentOverdue].minute = 9 * 60
        let earlier = NotificationPlan.build(
            courses: [f], settings: settings, now: at(15, 8), calendar: Self.calendar, days: 1)
        #expect(earlier.map(\.date) == [at(15, 9), at(16, 9)])

        settings[.assignmentOverdue].on = false
        #expect(
            NotificationPlan.build(courses: [f], settings: settings, now: at(15, 10), calendar: Self.calendar)
                .isEmpty)
    }
}
