import FolioDomain
import Foundation
import Testing

struct GradingTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)

    let catalog: Catalog = {
        func grade(_ symbol: String, _ points: Double?, credits: Bool = true) -> LetterGrade {
            LetterGrade(
                device: UUID(), at: Date(timeIntervalSince1970: 0), symbol: symbol, points: points,
                countsInGpa: points != nil, countsInCredits: credits)
        }
        return Catalog(letterGrades: [
            grade("A+", 4.5), grade("A0", 4), grade("B0", 3), grade("C+", 2.5), grade("C0", 2), grade("F", 0, credits: false),
            grade("S", nil), grade("W", nil),
        ])
    }()

    func id(_ symbol: String) -> UUID { catalog.letterGrades.first { $0.symbol == symbol }!.id }

    // MARK: GPA — made-up grades with expected values worked out by hand (AGENTS.md "테스트 기준")

    @Test func aTermWithAWithdrawal() {
        let catalog = catalog
        let spring = Semester(device: device, at: now, year: 2026, term: .spring)
        let grades: [(Double, String)] = [(3, "A0"), (3, "W"), (2, "B0"), (4, "A+"), (3, "B0"), (3, "A0")]
        let courses = grades.map { credits, symbol in
            var c = Course(device: device, at: now, semesterId: spring.id, title: symbol, credits: credits)
            c.finalGrade = catalog.letterGrades.first { $0.symbol == symbol }!.id
            return c
        }
        let s = GPACalculator.semester(spring, courses: courses, catalog: catalog)

        #expect(s.totalCredits == 18)
        #expect(s.effectiveCredits == 15)

        // (12 + 6 + 18 + 9 + 12) / 15이다.
        #expect(String(format: "%.3f", s.gpa!) == "3.800")
    }

    @Test func passFailZeroCreditAndUngradedStayOutOfGPA() {
        let catalog = catalog
        let term = Semester(device: device, at: now, year: 2025, term: .spring)
        func course(_ credits: Double, _ symbol: String?) -> Course {
            var c = Course(device: device, at: now, semesterId: term.id, title: "", credits: credits)
            c.finalGrade = symbol.map { s in catalog.letterGrades.first { $0.symbol == s }!.id }
            return c
        }
        let s = GPACalculator.semester(term, courses: [course(3, "B0"), course(1, "S"), course(0, "S"), course(3, nil)], catalog: catalog)

        #expect(s.totalCredits == 4)
        #expect(s.effectiveCredits == 3)
        #expect(s.gpa == 3)
    }

    @Test func creditedTermAddsCreditsOnly() {
        let catalog = catalog
        let credited = Semester(device: device, at: now, year: 2025, term: .credited, creditedHours: 9)
        let fall = Semester(device: device, at: now, year: 2025, term: .fall)
        var c = Course(device: device, at: now, semesterId: fall.id, title: "", credits: 3)
        c.finalGrade = id("A0")
        var waived = Course(device: device, at: now, semesterId: credited.id, title: "", credits: 9)
        waived.finalGrade = id("S")
        let total = GPACalculator.cumulative(semesters: [credited, fall], courses: [c, waived], catalog: catalog)

        #expect(total.totalCredits == 12)
        #expect(total.gpa == 4)
    }

    @Test func requiredAverageForTargetGPA() {
        let current = GPACalculator.Summary(totalCredits: 16, effectiveCredits: 16, gradePoints: 64)  // 4.0이다.
        #expect(GPACalculator.requiredAverage(target: 4.2, current: current, remainingCredits: 16) == 4.4)
        #expect(GPACalculator.requiredAverage(target: 4.2, current: current, remainingCredits: 0) == nil)
    }

    // MARK: Course score

    func component(_ name: String, _ weight: Double, _ aggregation: Aggregation = .sum, expected: Int? = nil) -> GradeComponent {
        GradeComponent(device: device, at: now, name: name, weight: weight, aggregation: aggregation, expectedCount: expected)
    }

    func entry(_ component: GradeComponent, _ score: Double, _ max: Double, excused: Bool = false, mean: Double? = nil, sd: Double? = nil)
        -> ScoreEntry
    {
        ScoreEntry(
            device: device, at: now, componentId: component.id, title: "", score: score, max: max, mean: mean, stdDev: sd, excused: excused)
    }

    @Test func graphTheoryDropsLowestQuiz() {
        let quiz = component("Quiz", 10, .dropLowest(1), expected: 5)
        let entries = [entry(quiz, 35, 50), entry(quiz, 45, 50), entry(quiz, 10, 50)]
        #expect(GradeCalculator.ratio(of: entries, by: .dropLowest(1)) == 0.8)
        #expect(GradeCalculator.ratio(of: [entries[2]], by: .dropLowest(1)) == 0.2)
        #expect(GradeCalculator.ratio(of: [entries[0], entry(quiz, 0, 50, excused: true)], by: .dropLowest(1)) == 0.7)
    }

    // 퀴즈 9회 중 최저 2회를 빼면, 7회까지는 점수를 그대로 세고 8회째에 하나, 9회째에 둘을 뺀다.
    @Test func dropLowestWaitsForTheQuizzesItCanDrop() {
        let quiz = component("Quiz", 10, .dropLowest(2), expected: 9)
        let seven = [10.0, 20, 30, 40, 50, 60, 70].map { entry(quiz, $0, 100) }
        #expect(abs(GradeCalculator.ratio(of: seven, by: .dropLowest(2), expected: 9)! - 0.4) < 1e-9)
        let eight = seven + [entry(quiz, 80, 100)]
        #expect(abs(GradeCalculator.ratio(of: eight, by: .dropLowest(2), expected: 9)! - 0.5) < 1e-9)
        let nine = eight + [entry(quiz, 90, 100)]
        #expect(abs(GradeCalculator.ratio(of: nine, by: .dropLowest(2), expected: 9)! - 0.6) < 1e-9)

        // 면제된 퀴즈가 횟수를 줄이므로, 남은 8회 중에서는 7번째 점수부터 하나를 뺀다.
        let excused = GradeCalculator.score(components: [quiz], entries: seven + [entry(quiz, 0, 100, excused: true)])
        #expect(abs(excused.components[0].ratio! - 0.45) < 1e-9)
    }

    @Test func securedProjectedAndRequired() {
        let quiz = component("Quiz", 20, .mean, expected: 4)
        let midterm = component("Midterm", 30, .single)
        let final = component("Final", 50, .single)
        let entries = [entry(quiz, 8, 10), entry(quiz, 10, 10), entry(midterm, 60, 100)]
        let score = GradeCalculator.score(components: [quiz, midterm, final], entries: entries)

        // 퀴즈의 절반 넘게 0.9이므로 9점이 확보되고, 중간고사는 18점이다.
        #expect(abs(score.secured - 27) < 1e-9)
        #expect(abs(score.remainingWeight - 60) < 1e-9)
        // 예상 점수는 퀴즈 0.9×20 + 중간고사 0.6×30 + 기말고사 전체 비율 27/40 × 50이다.
        #expect(abs(score.projected! - (18 + 18 + 27.0 / 40 * 50)) < 1e-9)
        #expect(abs(GradeCalculator.requiredAverage(for: 87, given: score)! - 100) < 1e-9)
    }

    @Test func scoresWithoutACountSecureNothingButShapeTheProjection() {
        let hw = component("HW", 40, .mean)
        let final = component("Final", 60, .single)
        let score = GradeCalculator.score(components: [hw, final], entries: [entry(hw, 9, 10)])
        #expect(score.secured == 0 && abs(score.remainingWeight - 100) < 1e-9)
        #expect(abs(score.projected! - 90) < 1e-9)
    }

    @Test func relativeStandingComparesTheZWithTheAShare() {
        let half = GradeCalculator.standing(z: 0.42, topGradeRatio: 0.5)
        #expect(abs(half.cutZ) < 1e-6 && half.inTopGrade)
        #expect(abs(half.above - 0.3372) < 1e-3)
        #expect(!GradeCalculator.standing(z: -0.1, topGradeRatio: 0.5).inTopGrade)
        // 30%만 A를 받으려면 약 +0.52σ가 필요하다.
        let strict = GradeCalculator.standing(z: 0.42, topGradeRatio: 0.3)
        #expect(abs(strict.cutZ - 0.5244) < 1e-3 && !strict.inTopGrade)
    }

    @Test func zScoreIsWeightedAcrossComponents() {
        let a = component("A", 25, .single), b = component("B", 75, .single)
        let score = GradeCalculator.score(
            components: [a, b], entries: [entry(a, 80, 100, mean: 70, sd: 10), entry(b, 50, 100, mean: 60, sd: 10)])
        #expect(score.z == (0.25 * 1 + 0.75 * -1))
    }

    // 선형대수학은 결석 6회면 최대 B0, 9회 이상이면 F이다(7회 C+, 8회 C0). 평균만 있고 표준편차가 없는 점수는 과목이 공개한 sd/max 비율을 빌리고, 빌렸다고 알린다.
    @Test func missingStandardDeviationBorrowsTheCourseSpread() {
        let a = component("Midterm", 50, .single), b = component("Final", 50, .single)
        // 중간고사는 100점 중 sd 10이므로 spread가 만점의 0.1이다. 기말고사는 50점 중 40점, 평균 30점이고 sd가 없으므로 10 / (0.1 * 50) = 2이다.
        let score = GradeCalculator.score(components: [a, b], entries: [entry(a, 80, 100, mean: 70, sd: 10), entry(b, 40, 50, mean: 30)])
        #expect(score.components[1].z == 2)
        #expect(score.zEstimated)
        #expect(score.z == 1.5)
        #expect(abs(score.meanGap! - 0.15) < 1e-9)
    }

    @Test func withoutAnyStandardDeviationOnlyTheSideOfTheMeanCounts() {
        let a = component("Midterm", 100, .single)
        let score = GradeCalculator.score(components: [a], entries: [entry(a, 62, 100, mean: 70)])
        #expect(score.z == nil)
        #expect(score.meanGap == -0.08)
        #expect(GradeCalculator.inTopGrade(meanGap: -0.08, topGradeRatio: 0.5) == false)
        #expect(GradeCalculator.inTopGrade(meanGap: -0.08, topGradeRatio: 0.6) == nil)
        #expect(GradeCalculator.inTopGrade(meanGap: 0.05, topGradeRatio: 0.5) == true)
        #expect(GradeCalculator.inTopGrade(meanGap: 0.05, topGradeRatio: 0.3) == nil)
    }

    @Test func linearAlgebraAttendanceCaps() {
        let catalog = catalog
        let policy = GradePolicy(
            attendanceCap: [
                AttendanceCap(absences: 6, maxGrade: id("B0")), AttendanceCap(absences: 7, maxGrade: id("C+")),
                AttendanceCap(absences: 8, maxGrade: id("C0")), AttendanceCap(absences: 9, maxGrade: id("F")),
            ], cutoffs: [GradeCutoff(grade: id("A+"), minScore: 90), GradeCutoff(grade: id("B0"), minScore: 70)])

        func letter(_ score: Double, _ absences: Int) -> String? {
            GradeCalculator.letterGrade(score: score, absences: absences, policy: policy, catalog: catalog)?.symbol
        }
        #expect(letter(95, 5) == "A+")
        #expect(letter(95, 6) == "B0")
        #expect(letter(75, 6) == "B0")
        #expect(letter(95, 8) == "C0")
        #expect(letter(95, 9) == "F")
        #expect(letter(95, 12) == "F")

        #expect(GradeCalculator.absencesUntilNextCap(absences: 4, policy: policy) == 2)
        #expect(GradeCalculator.absencesUntilNextCap(absences: 9, policy: policy) == nil)
        #expect(GradeCalculator.nextCap(absences: 5, policy: policy)?.absences == 6)
        #expect(GradeCalculator.nextCap(absences: 8, policy: policy)?.absences == 9)

        let session = UUID()
        let attendance = [AttendanceState.present, .late, .absent, .excused, .absent].map {
            Attendance(device: device, at: now, sessionId: session, state: $0)
        }
        #expect(GradeCalculator.absences(in: attendance, policy: policy) == 2)

        let lates = [AttendanceState.absent, .late, .late, .late, .late, .late, .excused].map {
            Attendance(device: device, at: now, sessionId: session, state: $0)
        }
        var latePolicy = policy
        #expect(GradeCalculator.absences(in: lates, policy: latePolicy) == 1)
        latePolicy.latesPerAbsence = 3
        #expect(GradeCalculator.absences(in: lates, policy: latePolicy) == 2)
        latePolicy.latesPerAbsence = 2
        #expect(GradeCalculator.absences(in: lates, policy: latePolicy) == 3)
    }

    @Test func aggregationRoundTripsAsText() throws {
        for a in [Aggregation.sum, .mean, .single, .dropLowest(2), .bestOf(3)] {
            let data = try JSONEncoder().encode([a])
            #expect(try JSONDecoder().decode([Aggregation].self, from: data) == [a])
        }
        #expect(String(decoding: try JSONEncoder().encode([Aggregation.dropLowest(1)]), as: UTF8.self) == #"["dropLowest:1"]"#)
    }
}
