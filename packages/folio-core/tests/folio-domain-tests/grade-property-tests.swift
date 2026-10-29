import FolioDomain
import Foundation
import PropertyBased
import Testing

/// Properties every input must keep, checked on random courses and scores. They can't say what the right GPA is, only
/// what no right answer breaks, so the hand-worked examples in GradingTests stay the anchor. A failure prints the seed;
/// `@Test(.fixedSeed(...))` replays it.
struct GradePropertyTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)

    let catalog: Catalog = {
        func grade(_ symbol: String, _ points: Double?, credits: Bool = true) -> LetterGrade {
            LetterGrade(device: UUID(), at: Date(timeIntervalSince1970: 0), symbol: symbol, points: points,
                        countsInGpa: points != nil, countsInCredits: credits)
        }
        return Catalog(letterGrades: [
            grade("A+", 4.5), grade("A0", 4), grade("B+", 3.5), grade("B0", 3), grade("C+", 2.5), grade("C0", 2),
            grade("D0", 1), grade("F", 0, credits: false), grade("S", nil), grade("U", nil, credits: false), grade("W", nil, credits: false),
        ])
    }()

    // Whole credits and half-point grades keep every sum exact in binary, so results compare with ==.
    // A grade index past the catalog means the course is still ungraded.
    static let course = zip(Gen.int(in: 0...4), Gen.int(in: 0...11))
    static let courses = course.array(of: 0...10)

    func make(_ rows: [(Int, Int)], in semester: UUID = UUID()) -> [Course] {
        rows.map { credits, g in
            var c = Course(device: device, at: now, semesterId: semester, title: "", credits: Double(credits))
            c.finalGrade = g < catalog.letterGrades.count ? catalog.letterGrades[g].id : nil
            return c
        }
    }

    func points(_ c: Course) -> Double? {
        guard c.credits > 0, let g = catalog.grade(c.finalGrade), g.countsInGpa else { return nil }
        return g.points
    }

    // MARK: GPA

    @Test func gpaLiesBetweenTheLowestAndHighestGrade() async {
        await propertyCheck(input: Self.courses) { rows in
            let courses = make(rows)
            let counted = courses.compactMap(points)
            let gpa = GPACalculator.summary(of: courses, catalog: catalog).gpa
            #expect((gpa == nil) == counted.isEmpty)
            if let gpa { #expect(counted.min()! - 1e-9 <= gpa && gpa <= counted.max()! + 1e-9) }
        }
    }

    @Test func orderDoesNotMatter() async {
        await propertyCheck(input: Self.courses) { rows in
            let courses = make(rows)
            #expect(GPACalculator.summary(of: courses.shuffled(), catalog: catalog) == GPACalculator.summary(of: courses, catalog: catalog))
        }
    }

    @Test func aCourseOutsideTheGPAOnlyMovesTotalCredits() async {
        await propertyCheck(input: Self.courses, Self.course) { rows, extra in
            let courses = make(rows)
            let added = make([extra])[0]
            guard points(added) == nil else { return }
            let before = GPACalculator.summary(of: courses, catalog: catalog)
            let after = GPACalculator.summary(of: courses + [added], catalog: catalog)
            let credits = catalog.grade(added.finalGrade)?.countsInCredits == true ? added.credits : 0
            #expect(after.effectiveCredits == before.effectiveCredits)
            #expect(after.gradePoints == before.gradePoints)
            #expect(after.totalCredits == before.totalCredits + credits)
        }
    }

    @Test func cumulativeAddsUpItsTermsAndCreditedHoursCountOnlyTowardTotal() async {
        await propertyCheck(input: Self.courses, Self.courses, Gen.int(in: 0...20)) { a, b, hours in
            let spring = Semester(device: device, at: now, year: 2026, term: .spring)
            let fall = Semester(device: device, at: now, year: 2026, term: .fall)
            let credited = Semester(device: device, at: now, year: 2025, term: .credited, creditedHours: Double(hours))
            let courses = make(a, in: spring.id) + make(b, in: fall.id)
            let s = GPACalculator.semester(spring, courses: courses, catalog: catalog)
            let f = GPACalculator.semester(fall, courses: courses, catalog: catalog)
            let total = GPACalculator.cumulative(semesters: [credited, spring, fall], courses: courses, catalog: catalog)
            #expect(total.totalCredits == s.totalCredits + f.totalCredits + Double(hours))
            #expect(total.effectiveCredits == s.effectiveCredits + f.effectiveCredits)
            #expect(total.gradePoints == s.gradePoints + f.gradePoints)
        }
    }

    @Test func averagingTheRequiredGradeReachesTheTarget() async {
        await propertyCheck(input: Self.courses, Gen.double(in: 0...4.5), Gen.int(in: 1...60)) { rows, target, remaining in
            let current = GPACalculator.summary(of: make(rows), catalog: catalog)
            let needed = GPACalculator.requiredAverage(target: target, current: current, remainingCredits: Double(remaining))!
            let reached = (current.gradePoints + needed * Double(remaining)) / (current.effectiveCredits + Double(remaining))
            #expect(abs(reached - target) < 1e-9)
        }
    }

    // MARK: Course scores

    // (score, max, excused); the score never passes its max.
    static let entry = zip(Gen.double(in: 0...1), Gen.int(in: 0...100), Gen.bool(0.1))
    static let entries = entry.array(of: 0...12)
    static let aggregation = Gen.int(in: 0...4).map { i -> Aggregation in [.sum, .mean, .single, .dropLowest(2), .bestOf(3)][i] }

    func make(_ rows: [(Double, Int, Bool)], component: UUID) -> [ScoreEntry] {
        rows.map { share, max, excused in
            ScoreEntry(device: device, at: now, componentId: component, title: "", score: share * Double(max), max: Double(max), excused: excused)
        }
    }

    @Test func aRatioStaysBetweenZeroAndOne() async {
        await propertyCheck(input: Self.entries, Self.aggregation) { rows, aggregation in
            guard let r = GradeCalculator.ratio(of: make(rows, component: UUID()), by: aggregation) else { return }
            #expect(-1e-9 <= r && r <= 1 + 1e-9)
        }
    }

    @Test func droppingTheLowestOrKeepingTheBestNeverLowersTheMean() async {
        await propertyCheck(input: Self.entries, Gen.int(in: 1...4)) { rows, n in
            let entries = make(rows, component: UUID())
            guard let mean = GradeCalculator.ratio(of: entries, by: .mean) else { return }
            #expect(GradeCalculator.ratio(of: entries, by: .dropLowest(n))! >= mean - 1e-9)
            #expect(GradeCalculator.ratio(of: entries, by: .bestOf(n))! >= mean - 1e-9)
        }
    }

    @Test func excusedScoresDoNotCount() async {
        await propertyCheck(input: Self.entries, Self.aggregation) { rows, aggregation in
            let entries = make(rows, component: UUID())
            #expect(GradeCalculator.ratio(of: entries, by: aggregation) == GradeCalculator.ratio(of: entries.filter { !$0.excused }, by: aggregation))
        }
    }

    // Up to three components, each with a weight, a known or unknown count of scores, and its scores.
    static let component = zip(Gen.int(in: 0...50), Gen.int(in: 1...10).optional(), Self.aggregation, Self.entries)
    static let components = component.array(of: 1...3)

    @Test func securedStaysWithinWhatIsLeftAndNeverPassesTheProjection() async {
        await propertyCheck(input: Self.components) { rows in
            let (components, entries) = build(rows)
            let score = GradeCalculator.score(components: components, entries: entries)
            let weight = components.reduce(0) { $0 + $1.weight }
            #expect(score.secured >= -1e-9)
            #expect(score.secured + score.remainingWeight <= weight + 1e-9)
            if let projected = score.projected { #expect(score.secured <= projected + 1e-9) }
        }
    }

    @Test func scoringTheRequiredAverageReachesTheTarget() async {
        await propertyCheck(input: Self.components, Gen.double(in: 0...100)) { rows, target in
            let (components, entries) = build(rows)
            let score = GradeCalculator.score(components: components, entries: entries)
            guard let needed = GradeCalculator.requiredAverage(for: target, given: score) else {
                #expect(score.remainingWeight == 0)
                return
            }
            #expect(abs(score.secured + score.remainingWeight * needed / 100 - target) < 1e-9)
        }
    }

    func build(_ rows: [(Int, Int?, Aggregation, [(Double, Int, Bool)])]) -> ([GradeComponent], [ScoreEntry]) {
        let components = rows.map { weight, count, aggregation, _ in
            GradeComponent(device: device, at: now, name: "", weight: Double(weight), aggregation: aggregation, expectedCount: count)
        }
        let entries = Swift.zip(components, rows).flatMap { component, row in make(row.3, component: component.id) }
        return (components, entries)
    }
}
