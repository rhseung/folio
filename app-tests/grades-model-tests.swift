import FolioDomain
import Foundation
import Testing
@testable import Folio

/// Made-up grades only: the repository is public.
@MainActor
struct GradesModelTests {
    let device = UUID()

    func grade(_ symbol: String, _ points: Double?) -> LetterGrade {
        LetterGrade(device: device, at: .now, symbol: symbol, points: points, countsInGpa: points != nil, countsInCredits: true)
    }

    /// The fixture's semesters with a made-up A0/B0 scale in the catalog.
    func workspace() throws -> Workspace {
        let workspace = try fixtureWorkspace()
        var catalog = workspace.catalog
        catalog.letterGrades = [grade("A0", 4), grade("B0", 3), grade("F", 0)]
        workspace.saveCatalog(catalog)
        return workspace
    }

    @Test func choosingAnotherGoalDropsTheTypedRemainingCredits() throws {
        let model = GradesModel(workspace: try workspace())
        model.remaining = 30
        #expect(model.remainingCredits == 30)
        model.targetProgram = UUID()
        #expect(model.remainingCredits == nil)
        #expect(model.remainingDetail == "과정 요건까지, 수강 중 포함")
    }

    @Test func needAboveTheTopGradeIsUnreachable() throws {
        let model = GradesModel(workspace: try workspace())
        model.remaining = 10
        model.target = 3.5
        // Nothing graded yet: the remaining credits must average the target itself.
        #expect(model.needText == "3.500")
        #expect(model.needDetail == nil)
        model.target = 4.2
        #expect(model.unreachable)
        #expect(model.needDetail == "만점 4보다 높아 닿을 수 없습니다")
    }

    @Test func semestersInProgressShowEnrolledCreditsNewestFirst() throws {
        let model = GradesModel(workspace: try workspace())
        let rows = model.semesterRows
        #expect(rows.map(\.semester.id) == model.semesters.reversed().map(\.id))
        #expect(rows.allSatisfy { $0.inProgress == ($0.enrolled > 0) })
    }

    @Test func aPickedUndecidedGradeStaysAPick() throws {
        let model = GradesModel(workspace: try workspace())
        let course = try #require(model.currentMembers.first)
        let a = try #require(model.catalog.letterGrades.first { $0.symbol == "A0" })
        #expect(model.simulatedTermDetail == "성적을 고르면 계산합니다")
        model.setPick(a.id, for: course)
        #expect(model.pick(course) == a.id)
        #expect(model.simulatedTerm?.gpa == 4)
        #expect(model.simulatedTermDetail == "유효 \(course.credits.formatted())학점")
        model.setPick(nil, for: course)
        #expect(model.expected.count == 1 && model.pick(course) == nil)
        model.resetPicks()
        #expect(model.expected.isEmpty)
    }

    @Test func trendPointsDashFromTheLastRecordedPoint() {
        let spring = Semester(device: device, at: .now, year: 2026, term: .spring)
        let fall = Semester(device: device, at: .now, year: 2026, term: .fall)
        let points = GradesModel.points([
            GPATrendPoint(semester: spring, gpa: 3.8, credits: 18, cumulative: 3.8),
            GPATrendPoint(semester: fall, gpa: 3, credits: 3, cumulative: 3.68),
        ])
        #expect(points.map(\.series) == [.semester, .cumulative, .semester, .cumulative])
        #expect(GradesModel.floor(points) == 2.5)
        #expect(GradesModel.legendValue(points, series: .semester, at: spring.shortTitle) == "3.800 · 18학점")
        #expect(GradesModel.legendValue(points, series: .cumulative, at: nil) == "")

        var cumulative = points.filter { $0.series == .cumulative }
        #expect(GradesModel.dashed(cumulative).isEmpty)
        cumulative[1].simulated = true
        #expect(GradesModel.dashed(cumulative).map(\.gpa) == [3.8, 3.68])
        #expect(GradesModel.legendValue(cumulative, series: .cumulative, at: fall.shortTitle) == "3.680 예상")
    }
}

@MainActor
struct RequirementsModelTests {
    let device = UUID()

    @Test func balancePutsEachCardUnderTheShorterColumn() {
        #expect(RequirementsModel.balance([10, 3, 3, 2], by: { $0 }) == [[10], [3, 3, 2]])
        #expect(RequirementsModel.balance([4, 4], by: { $0 }) == [[4], [4]])
    }

    @Test func aCardLeadsWithItsLoneRootOrTheRootNamedLikeIt() {
        func row(_ name: String, depth: Int = 0) -> CategoryTreeRow {
            CategoryTreeRow(category: RequirementCategory(device: device, at: .now, name: name), depth: depth, group: "기초‧교양")
        }
        #expect(RequirementsModel.header(of: (group: "전공", rows: [row("전공학점"), row("전공필수", depth: 1)]))?.category.name == "전공학점")
        #expect(RequirementsModel.header(of: (group: "기초‧교양", rows: [row("기초과학"), row("기초‧교양")]))?.category.name == "기초‧교양")
        #expect(RequirementsModel.header(of: (group: "기타", rows: [row("가"), row("나")])) == nil)
        #expect(RequirementsModel.groupTitle("") == "기타")
    }

    @Test func noteSaysWhatTheFigureDoesNot() {
        let category = RequirementCategory(device: device, at: .now, name: "전공선택", minCredits: 18, maxCredits: 24)
        let status = { RequirementStatus(category: category, credits: $0) }
        #expect(RequirementLine.note(category, status(CategoryCredits(earned: 15, inProgress: 6))) == "수강 중 6 · 3학점 남음")
        #expect(RequirementLine.note(category, status(CategoryCredits(earned: 27))) == "최대 24학점 초과")
        #expect(RequirementLine.note(category, status(CategoryCredits(earned: 20))) == "최대 24학점")
        let colloquium = RequirementCategory(device: device, at: .now, name: "콜로퀴움", minCount: 2)
        #expect(RequirementLine.note(colloquium, RequirementStatus(category: colloquium, credits: CategoryCredits(passed: 1))) == "1과목 남음")
    }

    @Test func subtitleFallsBackWithoutAProfileAndNamesAreListed() throws {
        let model = RequirementsModel(workspace: try fixtureWorkspace())
        #expect(model.subtitle == "학사편람에서 옮겨 적은 요건입니다. 항목을 누르면 고칩니다")
        #expect(model.names([]) == "없음")
    }

    @Test func removingACategoryLiftsItsChildren() throws {
        let workspace = try fixtureWorkspace()
        let parent = RequirementCategory(device: device, at: .now, name: "전공")
        let child = RequirementCategory(device: device, at: .now, name: "전공필수", parentId: parent.id)
        RequirementEditModel(workspace: workspace, category: parent).confirm()
        RequirementEditModel(workspace: workspace, category: child).confirm()
        #expect(workspace.catalog.categories.contains { $0.id == child.id && $0.parentId == parent.id })
        RequirementsModel.remove(parent, in: workspace)
        #expect(!workspace.catalog.categories.contains { $0.id == parent.id })
        #expect(workspace.catalog.categories.first { $0.id == child.id }?.parentId == nil)
    }

    @Test func secondProgramStartsAsADoubleMajor() throws {
        let workspace = try fixtureWorkspace()
        var catalog = workspace.catalog
        catalog.codes = [CourseCode(device: device, at: .now, prefix: "EC"), CourseCode(device: device, at: .now, prefix: "MA")]
        workspace.saveCatalog(catalog)
        let model = ProfileModel(workspace: workspace)
        model.addProgram(catalog.codes[0].id)
        model.addProgram(catalog.codes[1].id)
        #expect(model.rule.programs.map(\.kind) == [.major, .doubleMajor])
        #expect(model.addableOptions.isEmpty)
        #expect(RequirementsModel(workspace: workspace).subtitle == "EC 주전공 · MA 복수전공")
    }
}

@MainActor
struct CourseGradesModelTests {
    let device = UUID()

    func component(_ name: String, _ weight: Double, _ aggregation: Aggregation = .sum, expected: Int? = nil) -> GradeComponent {
        GradeComponent(device: device, at: .now, name: name, weight: weight, aggregation: aggregation, expectedCount: expected)
    }

    @Test func weightsNotAddingUpTo100AreFlagged() throws {
        let workspace = try fixtureWorkspace()
        let course = try #require(workspace.courses.first)
        let model = CourseGradesModel(workspace: workspace, course: course.id)
        var file = course.file
        file.components = [component("Quiz", 40), component("Final", 50)]
        #expect(model.componentsNote(file) == "비중 합계 90% · 100%가 아닙니다")
        file.components = [component("Quiz", 40), component("Final", 60)]
        #expect(model.componentsNote(file) == "비중 합계 100%")
    }

    @Test func componentDetailCountsOnlyScoresThatCount() throws {
        let workspace = try fixtureWorkspace()
        let course = try #require(workspace.courses.first)
        let model = CourseGradesModel(workspace: workspace, course: course.id)
        let quiz = component("Quiz", 20, .dropLowest(1), expected: 4)
        var file = course.file
        file.components = [quiz]
        file.scores = [ScoreEntry(device: device, at: .now, componentId: quiz.id, title: "1", score: 8, max: 10),
                       ScoreEntry(device: device, at: .now, componentId: quiz.id, title: "2", score: 0, max: 10, excused: true)]
        #expect(model.componentDetail(quiz, in: file) == "최저 1회 제외 · 1/4회")
        #expect(CourseGradesModel.removeMessage(quiz, in: file) == "이 항목의 점수 2개도 함께 삭제됩니다.")
        #expect(CourseGradesModel.removeMessage(component("Final", 40), in: file) == nil)
    }

    /// 선형대수학's rule: six absences cap the grade at B0, nine or more give F.
    @Test func attendanceCapsSayWhatTheNextAbsenceCosts() throws {
        let workspace = try fixtureWorkspace()
        var catalog = workspace.catalog
        let b = LetterGrade(device: device, at: .now, symbol: "B0", points: 3, countsInGpa: true, countsInCredits: true)
        let f = LetterGrade(device: device, at: .now, symbol: "F", points: 0, countsInGpa: true, countsInCredits: false)
        catalog.letterGrades = [b, f]
        workspace.saveCatalog(catalog)
        let course = try #require(workspace.courses.first)
        let model = CourseGradesModel(workspace: workspace, course: course.id)
        var file = course.file
        file.attendance = []
        file.policy.attendanceCap = [AttendanceCap(absences: 9, maxGrade: f.id), AttendanceCap(absences: 6, maxGrade: b.id)]
        file.policy.latesPerAbsence = 3
        let a = model.attendance(file)
        #expect(a.absences == 0 && a.cap == nil)
        #expect(a.detail == "6회 B0 · 9회 F · 지각 3회를 결석 1회로 셈")
        #expect(model.nextText(a) == "6회 더 결석하면 최대 B0")
        file.policy = GradePolicy()
        #expect(model.attendance(file).detail == "결석 상한 규칙이 없습니다")
    }

    @Test func wordingOfNeedsAndGaps() {
        #expect(CourseGradesModel.needText(120) == "만점으로도 부족")
        #expect(CourseGradesModel.needText(-3) == "이미 확보")
        #expect(CourseGradesModel.needText(72.34) == "72.3% 필요")
        #expect(CourseGradesModel.needText(nil) == "남은 항목 없음")
        #expect(2.46.sigmas == "평균 +2.5σ")
        #expect(0.04.sigmas == "평균")
        #expect(8.0.points == "평균 +8점")
        #expect((-1.5).points == "평균 -1.5점")
        #expect(Aggregation.bestOf(2).label == "상위 2회")
        let titled = ScoreEntry(device: device, at: .now, componentId: UUID(), title: "Quiz 3", score: 1, max: 1)
        #expect(CourseGradesModel.removeTitle(titled) == "‘Quiz 3’ 점수를 삭제할까요?")
    }
}

@MainActor
struct GradeEditingModelTests {
    let device = UUID()

    @Test func aScoreNeedsNumbersAndSaysHowFarFromTheMean() throws {
        let workspace = try fixtureWorkspace()
        let course = try #require(workspace.courses.first)
        let model = ScoreEntryModel(workspace: workspace, course: course,
                                    entry: ScoreEntry(device: device, at: .now, componentId: UUID(), title: "", score: 0, max: 10))
        #expect(model.isNew && model.score.isEmpty && !model.valid)
        #expect(model.sheetTitle == "점수 추가" && model.confirmTitle == "추가")
        model.score = "8"
        #expect(model.valid)
        model.mean = "x"
        #expect(!model.valid)
        model.mean = "6"
        #expect(model.meanDetail == "평균 +2점 · 표준편차는 없으면 비워 둡니다")
        model.stdDev = "2"
        #expect(model.meanDetail == "평균 +1.0σ")
    }

    @Test func theCountMenuKeepsTheRule() throws {
        let workspace = try fixtureWorkspace()
        let course = try #require(workspace.courses.first)
        let model = ComponentModel(workspace: workspace, course: course,
                                   component: GradeComponent(device: device, at: .now, name: " ", weight: 10, aggregation: .dropLowest(1)))
        #expect(model.invalid)
        model.countValue = 3
        #expect(model.aggregation == .dropLowest(3) && model.countLabel == "제외할 횟수")
        model.aggregation = .bestOf(2)
        model.countValue = 4
        #expect(model.aggregation == .bestOf(4) && model.countLabel == "반영할 횟수")
        model.aggregation = .single
        #expect(model.count == nil)
    }

    @Test func policyRejectsOutOfRangeShares() throws {
        let workspace = try fixtureWorkspace()
        var catalog = workspace.catalog
        catalog.letterGrades = [LetterGrade(device: device, at: .now, symbol: "A0", points: 4, countsInGpa: true, countsInCredits: true),
                                LetterGrade(device: device, at: .now, symbol: "F", points: 0, countsInGpa: true, countsInCredits: false)]
        workspace.saveCatalog(catalog)
        let course = try #require(workspace.courses.first)
        let model = PolicyModel(workspace: workspace, course: course)
        model.topShare = "100"
        #expect(model.invalid)
        model.topShare = "30"
        model.lates = "0"
        #expect(model.invalid)
        model.lates = ""
        model.ratio = "75"
        #expect(!model.invalid)
        model.caps = []
        model.addCap()
        #expect(model.caps.map(\.absences) == [6])
        #expect(model.caps.first?.maxGrade == catalog.letterGrades[1].id)
    }
}
