import FolioCore
import FolioDomain
import Foundation
import PropertyBased
import Testing

struct ExamPlannerTests {
    static let today = LocalDate(Date(timeIntervalSince1970: 1_793_750_400), in: Calendar(identifier: .gregorian))
    static let ids = (0..<16).map { _ in UUID() }

    static func plan(
        _ current: [ExamPlanItem] = [], units: [ExamPlanner.UnitInput], days: Int, finalDays: Int = 3, dayItems: Int = 2,
        done: Set<UUID> = []
    ) -> [ExamPlanItem] {
        ExamPlanner.plan(
            current: current, units: units, today: today, examDay: today.adding(days: days), finalDays: finalDays, dayItems: dayItems,
            isDone: { done.contains($0.id) })
    }

    @Test func twelveUnitsThreeDaysBeforeTheExamBecomeTwoBundlesToday() {
        // D-3에 마무리 날 셋을 바라면 이틀만 받는다(오답, 모의시험). 단원은 오늘 하루에 열둘이고, 하루 두 항목이라 여섯씩 묶는다.
        let units = (0..<12).map { ExamPlanner.UnitInput(id: Self.ids[$0], weight: 1) }
        let plan = Self.plan(units: units, days: 3)
        let todays = plan.filter { $0.day == Self.today }
        #expect(todays.map(\.target.units) == [Array(Self.ids[0..<6]), Array(Self.ids[6..<12])])
        #expect(plan.filter { $0.target.kind != .unit }.map(\.target.kind) == [.mock, .wrong])
        #expect(todays.first?.target.id == Self.ids[0])
    }

    @Test func aDayOverTheCapMergesOnlyThatDaysUnits() {
        // 나흘에 단원 다섯이면 날은 0, 0, 1, 2, 3번째 날이다. 하루 한 항목이면 첫날의 두 단원만 묶인다.
        let units = (0..<5).map { ExamPlanner.UnitInput(id: Self.ids[$0], weight: 1) }
        let plan = Self.plan(units: units, days: 4, finalDays: 0, dayItems: 1)
        #expect(plan.map(\.target.units) == [[Self.ids[0], Self.ids[1]], [Self.ids[2]], [Self.ids[3]], [Self.ids[4]]])
        #expect(plan.map(\.day) == (0..<4).map { Self.today.adding(days: $0) })
        #expect(plan[1].target == .unit(Self.ids[2]))
    }

    @Test func noDayHoldsMoreUnitItemsThanTheCap() async {
        await propertyCheck(input: Gen.int(in: 1...16), Gen.int(in: 1...30), Gen.int(in: 0...4), Gen.int(in: 1...5)) {
            count, days, finals, cap in
            let units = (0..<count).map { ExamPlanner.UnitInput(id: Self.ids[$0], weight: Double($0 % 3) / 2) }
            let plan = Self.plan(units: units, days: days, finalDays: finals, dayItems: cap)
            let perDay = Dictionary(grouping: plan.filter { $0.target.kind == .unit }, by: \.day)
            #expect(perDay.values.allSatisfy { $0.count <= cap })
            for u in units { #expect(plan.contains { $0.target.units.contains(u.id) }) }
        }
    }

    @Test func theLastDaysAreMixedMockAndWrongAndUnitsComeFirst() {
        let units = [ExamPlanner.UnitInput(id: Self.ids[0], weight: 1), ExamPlanner.UnitInput(id: Self.ids[1], weight: 0.2)]
        let plan = Self.plan(units: units, days: 10)
        let finals = plan.filter { $0.target.kind != .unit }
        #expect(finals.map(\.target.kind) == [.mixed, .mock, .wrong])
        #expect(finals.map(\.day) == [7, 8, 9].map { Self.today.adding(days: $0) })
        // 남은 이레를 두 단원이 나눈다. 약한 첫 단원만 두 번째 자리를 받는다.
        let unitItems = plan.filter { $0.target.kind == .unit }
        #expect(unitItems.map(\.target.id) == [Self.ids[0], Self.ids[1], Self.ids[0]])
        #expect(unitItems.first?.day == Self.today)
    }

    @Test func fewerDaysThanTheFinalDaysLeaveTodayForUnits() {
        let plan = Self.plan(units: [ExamPlanner.UnitInput(id: Self.ids[0], weight: 1)], days: 2)
        #expect(plan.map(\.target.kind) == [.unit, .wrong])
        #expect(plan.map(\.day) == [Self.today, Self.today.adding(days: 1)])
    }

    @Test func replanningOnTheSameDayKeepsWhatWasFinishedToday() {
        let units = [ExamPlanner.UnitInput(id: Self.ids[0], weight: 1), ExamPlanner.UnitInput(id: Self.ids[1], weight: 1)]
        let first = Self.plan(units: units, days: 6)
        let todays = first.filter { $0.day == Self.today }
        #expect(todays.count == 1)
        let finished = Set(todays.map(\.id))

        let again = Self.plan(first, units: units, days: 6, done: finished)
        #expect(Set(again.map(\.id)).isSuperset(of: finished))
        // 끝낸 항목이 오늘 자리를 그대로 차지해서 나머지 항목의 날도 처음 짠 것과 같다.
        #expect(again.map(\.day) == first.map(\.day))
        #expect(again.map(\.target) == first.map(\.target))
    }

    @Test func itemsFinishedOnEarlierDaysStayAndUnfinishedOnesCarry() {
        let units = [ExamPlanner.UnitInput(id: Self.ids[0], weight: 1)]
        let yesterday = Self.today.adding(days: -1)
        let done = ExamPlanItem(day: yesterday, target: .unit(Self.ids[0]))
        let missed = ExamPlanItem(day: yesterday, target: .unit(Self.ids[1]))
        let plan = Self.plan(
            [done, missed], units: units + [ExamPlanner.UnitInput(id: Self.ids[1], weight: 0.1)], days: 6, done: [done.id])
        #expect(plan.contains { $0.id == done.id })
        #expect(!plan.contains { $0.id == missed.id })
        let carried = plan.first { $0.target == .unit(Self.ids[1]) && $0.day == Self.today }
        #expect(carried?.isCarried == true)
    }

    // 줄이기(shrink)가 배열을 짧게 만들 수 있어서 읽을 때 범위를 확인한다.
    static let weights = Gen.int(in: 0...20).array(of: 6)

    @Test func everyUnitGetsADayInsideTheWindowAndWeakerUnitsGetNoFewer() async {
        await propertyCheck(input: Gen.int(in: 1...6), Gen.int(in: 1...30), Gen.int(in: 0...4), Self.weights) { count, days, finals, w in
            let units = (0..<count).map { ExamPlanner.UnitInput(id: Self.ids[$0], weight: Double(w.indices.contains($0) ? w[$0] : 0) / 10) }
            let plan = Self.plan(units: units, days: days, finalDays: finals)
            let end = Self.today.adding(days: days)
            #expect(plan.allSatisfy { $0.day >= Self.today && $0.day < end })
            for u in units { #expect(plan.contains { $0.target.units.contains(u.id) }) }
            let seats = Dictionary(grouping: plan.flatMap(\.target.units), by: { $0 }).mapValues(\.count)
            for a in units {
                for b in units where a.weight > b.weight {
                    #expect((seats[a.id] ?? 0) >= (seats[b.id] ?? 0))
                }
            }
        }
    }

    @Test func editedItemsSurviveReplanning() async {
        await propertyCheck(input: Gen.int(in: 1...6), Gen.int(in: 1...30), Gen.int(in: 0...29)) { count, days, at in
            let units = (0..<count).map { ExamPlanner.UnitInput(id: Self.ids[$0], weight: 1) }
            let mine = ExamPlanItem(day: Self.today.adding(days: at % days), target: .unit(Self.ids[0]), title: "내 복습", edited: true)
            let first = Self.plan([mine], units: units, days: days)
            let again = Self.plan(first, units: units, days: days)
            #expect(again.contains(mine))
        }
    }
}

struct PlanInputTests {
    @Test func aParentInScopeWithItsChildrenIsLeftToTheChildren() {
        let device = UUID(), at = Date(timeIntervalSince1970: 1_790_000_000)
        let matching = FolioDomain.Unit(device: device, at: at, title: "매칭", order: 0)
        let hall = FolioDomain.Unit(device: device, at: at, title: "Hall의 정리", order: 0, parentId: matching.id)
        let paths = FolioDomain.Unit(device: device, at: at, title: "증가 경로", order: 1, parentId: matching.id)
        let coloring = FolioDomain.Unit(device: device, at: at, title: "채색", order: 1)
        var exam = Exam(device: device, at: at, title: "기말고사", start: at.addingTimeInterval(86_400 * 10))
        exam.addedScopeUnitIds = [matching.id, hall.id, paths.id, coloring.id]
        let file = CourseFile(
            course: Course(device: device, at: at, title: "그래프 이론"), units: [matching, hall, paths, coloring], exams: [exam])
        let study = CourseStudy(
            file: file, cards: [], log: StudyLog(), settings: Settings(), calendar: Calendar(identifier: .gregorian), now: at)
        #expect(study.planInputs(for: exam).map(\.id) == [hall.id, paths.id, coloring.id])
        // 자식이 범위에 없으면 부모가 그대로 들어간다.
        exam.addedScopeUnitIds = [matching.id, coloring.id]
        #expect(study.planInputs(for: exam).map(\.id) == [matching.id, coloring.id])
    }

    @Test func aBundleIsCheckedWhenEveryUnitInItIsDone() {
        let device = UUID(), at = Date(timeIntervalSince1970: 1_790_000_000)
        var matching = FolioDomain.Unit(device: device, at: at, title: "매칭", order: 0)
        let coloring = FolioDomain.Unit(device: device, at: at, title: "채색", order: 1)
        matching.isDone = true
        let exam = Exam(device: device, at: at, title: "기말고사")
        let bundle = ExamPlanItem(day: LocalDate(at, in: Calendar(identifier: .gregorian)), target: .units([matching.id, coloring.id]))
        func study(_ units: [FolioDomain.Unit]) -> CourseStudy {
            let file = CourseFile(course: Course(device: device, at: at, title: "그래프 이론"), units: units, exams: [exam])
            return CourseStudy(
                file: file, cards: [], log: StudyLog(), settings: Settings(), calendar: Calendar(identifier: .gregorian), now: at)
        }
        #expect(!study([matching, coloring]).isDone(bundle, in: exam))
        var done = coloring
        done.isDone = true
        #expect(study([matching, done]).isDone(bundle, in: exam))
        #expect(study([matching, done]).file.title(of: bundle) == "매칭, 채색")
    }

    // 묶음 항목의 이름은 한 줄에 읽혀야 한다. 한 부모의 단원이면 부모 이름이고, 아니면 첫 단원과 나머지 개수다.
    @Test func aBundleIsNamedByItsParentOrItsFirstUnit() {
        let device = UUID(), at = Date(timeIntervalSince1970: 1_790_000_000)
        let connectivity = FolioDomain.Unit(device: device, at: at, title: "연결도", order: 0)
        let kids = ["Menger의 정리", "귀 분해", "2-연결 그래프"].enumerated().map { i, title in
            FolioDomain.Unit(device: device, at: at, title: title, order: i, parentId: connectivity.id)
        }
        let coloring = FolioDomain.Unit(device: device, at: at, title: "채색", order: 1)
        let matching = FolioDomain.Unit(device: device, at: at, title: "매칭", order: 2)
        let file = CourseFile(
            course: Course(device: device, at: at, title: "그래프 이론"), units: [connectivity] + kids + [coloring, matching])
        let day = LocalDate(at, in: Calendar(identifier: .gregorian))
        func title(_ units: [FolioDomain.Unit]) -> String {
            file.title(of: ExamPlanItem(day: day, target: .units(units.map(\.id))))
        }
        #expect(title([kids[0]]) == "Menger의 정리")
        #expect(title(kids) == "연결도")
        #expect(title(Array(kids.prefix(2))) == "연결도 단원 2개")
        #expect(title([coloring, matching]) == "채색, 매칭")
        #expect(title([kids[0], coloring, matching]) == "Menger의 정리 외 2개")
    }

    // 남은 오답이 없어도 오지 않은 날의 오답 항목은 체크하지 않는다. 세는 것은 시험 범위의 오답과 카드뿐이다.
    @Test func aFutureWrongItemIsNotCheckedEvenWithNothingLeft() throws {
        let device = UUID(), at = Date(timeIntervalSince1970: 1_790_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let inScope = FolioDomain.Unit(device: device, at: at, title: "매칭", order: 0)
        let outside = FolioDomain.Unit(device: device, at: at, title: "채색", order: 1)
        var exam = Exam(device: device, at: at, title: "기말고사", start: at.addingTimeInterval(86_400 * 10))
        exam.addedScopeUnitIds = [inScope.id]
        let set = ProblemSet(
            device: device, at: at, title: "연습", source: .exercise, problems: [Problem(number: "1", unitIds: [outside.id])])
        let file = CourseFile(
            course: Course(device: device, at: at, title: "그래프 이론"), units: [inScope, outside], exams: [exam], problemSets: [set])
        let wrong = ProblemSolveEvent(setId: set.id, problemId: set.problems[0].id, verdict: .wrong, basis: .solution)
        let study = CourseStudy(
            file: file, cards: [], log: StudyLog(solves: [(at, wrong)]), settings: Settings(), calendar: calendar, now: at)
        #expect(study.wrongLeft(in: exam) == (problems: 0, cards: 0))
        let today = ExamPlanItem(day: study.today, target: ExamPlanTarget(kind: .wrong))
        let later = ExamPlanItem(day: study.today.adding(days: 3), target: ExamPlanTarget(kind: .wrong))
        #expect(study.isDone(today, in: exam))
        #expect(!study.isDone(later, in: exam))
        // 범위 밖 단원의 오답은 범위를 넓히면 센다.
        var wider = exam
        wider.addedScopeUnitIds = [inScope.id, outside.id]
        #expect(study.wrongLeft(in: wider).problems == 1)
        #expect(!study.isDone(today, in: wider))
    }

    // 같은 공부일이라도 범위, 시험 날짜, 계획에 쓰는 공부 설정이 바뀌면 다시 짠다.
    @Test func aChangedBasisAsksForANewPlanOnTheSameDay() {
        let device = UUID(), at = Date(timeIntervalSince1970: 1_790_000_000)
        let calendar = Calendar(identifier: .gregorian)
        var settings = Settings()
        let today = settings.studyDay(of: at, calendar: calendar)
        let matching = FolioDomain.Unit(device: device, at: at, title: "매칭", order: 0)
        let coloring = FolioDomain.Unit(device: device, at: at, title: "채색", order: 1)
        var exam = Exam(device: device, at: at, title: "기말고사", start: at.addingTimeInterval(86_400 * 10))
        exam.addedScopeUnitIds = [matching.id]
        var file = CourseFile(course: Course(device: device, at: at, title: "그래프 이론"), units: [matching, coloring], exams: [exam])
        #expect(file.needsPlan(exam, today: today, settings: settings, calendar: calendar))
        exam.planDay = today
        exam.planBasis = ExamPlanBasis(exam: exam, in: file, settings: settings, calendar: calendar)
        file.exams = [exam]
        #expect(!file.needsPlan(exam, today: today, settings: settings, calendar: calendar))
        #expect(file.needsPlan(exam, today: today.adding(days: 1), settings: settings, calendar: calendar))

        var scoped = file
        scoped.setScope([matching.id, coloring.id], exam: exam.id)
        #expect(scoped.needsPlan(scoped.exams[0], today: today, settings: settings, calendar: calendar))
        var moved = exam
        moved.start = at.addingTimeInterval(86_400 * 12)
        #expect(file.needsPlan(moved, today: today, settings: settings, calendar: calendar))
        settings.study.planDayItems = 3
        #expect(file.needsPlan(exam, today: today, settings: settings, calendar: calendar))
        // 지난 시험과 범위 없는 시험은 짜지 않는다.
        settings = Settings()
        #expect(!file.needsPlan(exam, today: today.adding(days: 11), settings: settings, calendar: calendar))
        file.setScope([], exam: exam.id)
        #expect(!file.needsPlan(file.exams[0], today: today.adding(days: 1), settings: settings, calendar: calendar))
    }
}
