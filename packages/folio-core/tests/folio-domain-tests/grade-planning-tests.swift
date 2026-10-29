import FolioDomain
import Foundation
import Testing

struct GradePlanningTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)

    let catalog: Catalog = {
        func grade(_ symbol: String, _ points: Double?, credits: Bool = true, graduation: Bool? = nil) -> LetterGrade {
            var g = LetterGrade(device: UUID(), at: Date(timeIntervalSince1970: 0), symbol: symbol, points: points,
                                countsInGpa: points != nil, countsInCredits: credits)
            g.countsTowardGraduation = graduation
            return g
        }
        let major = Category(device: UUID(), at: Date(timeIntervalSince1970: 0), name: "전공", isMajor: true, minCredits: 36)
        let required = Category(device: UUID(), at: Date(timeIntervalSince1970: 0), name: "전공필수", parentId: major.id, minCredits: 18)
        let science = Category(device: UUID(), at: Date(timeIntervalSince1970: 0), name: "기초과학")
        return Catalog(categories: [major, required, science], letterGrades: [
            grade("A+", 4.5), grade("A0", 4), grade("B0", 3), grade("F", 0, credits: false), grade("S", nil),
            grade("W", nil, graduation: false),  // W counts toward total credits but earns none
        ])
    }()

    func grade(_ symbol: String) -> UUID { catalog.letterGrades.first { $0.symbol == symbol }!.id }
    func category(_ name: String) -> UUID { catalog.categories.first { $0.name == name }!.id }

    // MARK: Simulation

    /// A term in progress; picking its grades gives the same totals as grading it.
    @Test func simulatingATermGradesIt() {
        let fall = Semester(device: device, at: now, year: 2025, term: .fall)
        let spring = Semester(device: device, at: now, year: 2026, term: .spring)
        var past = Course(device: device, at: now, semesterId: fall.id, title: "past", credits: 3)
        past.finalGrade = grade("B0")
        let current = [3.0, 3, 2, 4, 3, 3].map { Course(device: device, at: now, semesterId: spring.id, title: "", credits: $0) }
        let courses = [past] + current
        let picks = ["A0", "W", "B0", "A+", "B0", "A0"]
        let expected = Dictionary(uniqueKeysWithValues: zip(current.map(\.id), picks.map { UUID?.some(grade($0)) }))

        #expect(GPACalculator.semester(spring, courses: courses, catalog: catalog).gpa == nil)
        let simulated = GPACalculator.simulate(expected, courses: courses)
        let s = GPACalculator.semester(spring, courses: simulated, catalog: catalog)
        #expect(s.totalCredits == 18)
        #expect(s.effectiveCredits == 15)
        #expect(String(format: "%.3f", s.gpa!) == "3.800")

        // Cumulative: (57 + 3 × 3) / 18.
        let total = GPACalculator.cumulative(semesters: [fall, spring], courses: simulated, catalog: catalog)
        #expect(total.totalCredits == 21)
        #expect(total.effectiveCredits == 18)
        #expect(abs(total.gpa! - 66.0 / 18) < 1e-9)
    }

    @Test func simulationOverridesOnlyPickedCourses() {
        let term = Semester(device: device, at: now, year: 2026, term: .fall)
        var graded = Course(device: device, at: now, semesterId: term.id, title: "graded", credits: 3)
        graded.finalGrade = grade("A0")
        let open = Course(device: device, at: now, semesterId: term.id, title: "open", credits: 3)
        let courses = [graded, open]

        // An explicit nil clears a recorded grade; a course left out keeps it.
        let cleared = GPACalculator.simulate([graded.id: nil, open.id: grade("B0")], courses: courses)
        #expect(GPACalculator.semester(term, courses: cleared, catalog: catalog).gpa == 3)
        let kept = GPACalculator.simulate([open.id: grade("A+")], courses: courses)
        #expect(GPACalculator.semester(term, courses: kept, catalog: catalog).gpa == 4.25)
    }

    // MARK: Graduation requirements

    @Test func categoryCreditsRollUpAndSeparateInProgress() {
        func course(_ credits: Double, _ symbol: String?, _ categories: [String]) -> Course {
            var c = Course(device: device, at: now, semesterId: nil, title: "", categoryIds: categories.map(category), credits: credits)
            c.finalGrade = symbol.map(grade)
            return c
        }
        let courses = [
            course(3, "A+", ["전공필수"]),
            course(3, "B0", ["전공"]),
            course(3, nil, ["전공필수"]),
            course(3, "F", ["전공필수"]),  // failed: no credits
            course(1, "S", ["기초과학"]),
            course(3, "A0", ["전공", "전공필수"]),  // listed under both: counts once toward 전공
            course(3, "W", ["전공필수"]),  // withdrawn: in the semester total, not in requirements
        ]
        let credits = GPACalculator.categoryCredits(courses: courses, catalog: catalog)
        #expect(credits[category("전공필수")] == CategoryCredits(earned: 6, inProgress: 3, passed: 2, taking: 1))
        #expect(credits[category("전공")] == CategoryCredits(earned: 9, inProgress: 3, passed: 3, taking: 1))
        #expect(credits[category("기초과학")] == CategoryCredits(earned: 1, inProgress: 0, passed: 1, taking: 0))
        // The course lists follow the same rule: the failed course is in neither, the double-listed one appears once.
        let listed = GPACalculator.categoryCourses(courses: courses, catalog: catalog)
        #expect(listed[category("전공필수")]?.map(\.id) == [courses[0], courses[2], courses[5]].map(\.id))
        #expect(listed[category("전공")]?.count == 4)
    }

    /// GIST counts at most 42 major credits toward the 130 unless 심화전공 is declared (2026 학사편람 p.33).
    @Test func majorCreditsPastTheCapDoNotCountTowardGraduation() {
        var catalog = catalog
        let major = catalog.categories.firstIndex { $0.name == "전공" }!
        catalog.categories[major].maxCredits = 42
        let term = Semester(device: device, at: now, year: 2026, term: .spring)
        let credited = Semester(device: device, at: now, year: 2025, term: .credited, creditedHours: 9)
        var courses = (0..<15).map { _ in
            var c = Course(device: device, at: now, semesterId: term.id, title: "", categoryIds: [category("전공필수")], credits: 3)
            c.finalGrade = grade("A0")
            return c
        }
        courses.append(Course(device: device, at: now, semesterId: term.id, title: "", categoryIds: [category("전공")], credits: 3))
        var withdrawn = Course(device: device, at: now, semesterId: term.id, title: "", categoryIds: [category("전공")], credits: 3)
        withdrawn.finalGrade = grade("W")
        courses.append(withdrawn)
        let p = GPACalculator.graduation(semesters: [credited, term], courses: courses, catalog: catalog)
        // 45 major credits earned, 3 over the cap; the child's own cap would be ignored.
        #expect(p.earned == 54 && p.counted == 51 && p.inProgress == 3)
    }
}

/// A double major gets its own GPA and remaining credits; a child category belongs to its parent's program.
@Test func programGPAAndRemainingCredits() {
    let (d, t) = (UUID(), Date(timeIntervalSince1970: 0))
    let ec = UUID(), ai = UUID()
    let a = LetterGrade(device: d, at: t, symbol: "A+", points: 4.5, countsInGpa: true, countsInCredits: true)
    let b = LetterGrade(device: d, at: t, symbol: "B0", points: 3, countsInGpa: true, countsInCredits: true)
    var ecMajor = Category(device: d, at: t, name: "전공학점", isMajor: true, minCredits: 36)
    ecMajor.programId = ec
    let ecRequired = Category(device: d, at: t, name: "전공필수", parentId: ecMajor.id, minCredits: 3)
    var aiMajor = Category(device: d, at: t, name: "AI 복수전공", minCredits: 30)
    aiMajor.programId = ai
    let catalog = Catalog(categories: [ecMajor, ecRequired, aiMajor], letterGrades: [a, b])
    func course(_ category: FolioDomain.Category, _ grade: LetterGrade?, credits: Double = 3) -> Course {
        var c = Course(device: d, at: t, title: "", categoryIds: [category.id], credits: credits)
        c.finalGrade = grade?.id
        return c
    }
    let courses = [course(ecRequired, a), course(ecMajor, b), course(aiMajor, a), course(aiMajor, nil)]
    #expect(GPACalculator.program(ec, courses: courses, catalog: catalog).gpa == 3.75)
    #expect(GPACalculator.program(ai, courses: courses, catalog: catalog).gpa == 4.5)
    #expect(GPACalculator.programRemaining(ec, courses: courses, catalog: catalog) == 30)  // the child's minimum is inside the parent's
    #expect(GPACalculator.programRemaining(ai, courses: courses, catalog: catalog) == 27)  // the ungraded course is still to come
}

struct LetterGradeModeTests {
    /// An S/U course picks from S, U, W; a letter course doesn't offer S once S is marked S/U-only.
    @Test func gradesFollowTheCoursesMode() {
        func grade(_ symbol: String, _ points: Double?, _ modes: [GradingMode]? = nil) -> LetterGrade {
            var g = LetterGrade(device: UUID(), at: .now, symbol: symbol, points: points, countsInGpa: points != nil, countsInCredits: true)
            g.modes = modes
            return g
        }
        let catalog = Catalog(letterGrades: [grade("B0", 3), grade("S", nil), grade("A+", 4.5), grade("W", nil)])
        #expect(catalog.grades(for: .passFail).map(\.symbol) == ["S", "W"])
        #expect(catalog.grades(for: .relative).map(\.symbol) == ["A+", "B0", "S", "W"])
        var marked = catalog
        marked.letterGrades[1].modes = [.passFail]
        #expect(marked.grades(for: .absolute).map(\.symbol) == ["A+", "B0", "W"])
    }
}

/// 학사편람 2025 p.8: a double major shares at most 9 credits with the major; the student picks which by listing a
/// course under both, and what goes past the cap comes off the double major, graded credits first.
@Test func doubleMajorSharesAtMostItsCapWithTheMajor() {
    let (d, t) = (UUID(), Date(timeIntervalSince1970: 0))
    let a = LetterGrade(device: d, at: t, symbol: "A0", points: 4, countsInGpa: true, countsInCredits: true)
    let ec = CourseCode(device: d, at: t, prefix: "EC"), ai = CourseCode(device: d, at: t, prefix: "AI")
    var major = Category(device: d, at: t, name: "전공학점", isMajor: true, minCredits: 36)
    major.programId = ec.id
    let required = Category(device: d, at: t, name: "전공필수", parentId: major.id)
    var double = Category(device: d, at: t, name: "AI 복수전공", minCredits: 36)
    double.programId = ai.id
    double.maxSharedCredits = 9
    let common = Category(device: d, at: t, name: "기초과학")
    let catalog = Catalog(codes: [ec, ai], categories: [major, required, double, common], letterGrades: [a])
    func course(_ categories: [FolioDomain.Category], graded: Bool = true, credits: Double = 3) -> Course {
        var c = Course(device: d, at: t, semesterId: nil, title: "", codes: [ec.id, ai.id], categoryIds: categories.map(\.id), credits: credits)
        if graded { c.finalGrade = a.id }
        return c
    }
    let courses = [
        course([required, double]), course([major, double]), course([major, double], credits: 4),  // 10 shared, graded
        course([major, double], graded: false),  // 3 more, in progress
        course([double]), course([double, common]),  // not shared with another program
    ]
    let credits = GPACalculator.categoryCredits(courses: courses, catalog: catalog)
    // 13 shared against 9: graded 10 lose 1, in-progress 3 lose the other 3.
    #expect(credits[double.id] == CategoryCredits(earned: 15, inProgress: 0, passed: 5, taking: 1))
    #expect(credits[major.id] == CategoryCredits(earned: 10, inProgress: 3, passed: 3, taking: 1))
    let shared = GPACalculator.shared(courses: courses, catalog: catalog)
    #expect(shared.count == 1 && shared[0].courses.map(\.id) == courses[0..<4].map(\.id) && shared[0].isOver)

    // Within the cap nothing changes; a minor's cap of 0 takes every shared credit off it.
    let within = GPACalculator.categoryCredits(courses: Array(courses[0..<2]), catalog: catalog)
    #expect(within[double.id]?.earned == 6 && within[major.id]?.earned == 6)
    var minor = double
    minor.maxSharedCredits = 0
    let asMinor = GPACalculator.categoryCredits(courses: Array(courses[0..<2]), catalog: Catalog(codes: [ec, ai], categories: [major, required, minor], letterGrades: [a]))
    #expect(asMinor[minor.id]?.earned == 0 && asMinor[major.id]?.earned == 6)
}

@Test func onlySharedCodeOrApprovedCoursesCountTowardBothPrograms() {
    let (d, t) = (UUID(), Date(timeIntervalSince1970: 0))
    let a = LetterGrade(device: d, at: t, symbol: "A0", points: 4, countsInGpa: true, countsInCredits: true)
    // A second AI code, as another handbook year adds: matching is by prefix, not id.
    let ec = CourseCode(device: d, at: t, prefix: "EC"), ai = CourseCode(device: d, at: t, prefix: "AI"), ai2 = CourseCode(device: d, at: t, prefix: "AI")
    var major = Category(device: d, at: t, name: "전공학점", isMajor: true)
    major.programId = ec.id
    var double = Category(device: d, at: t, name: "AI 복수전공")
    double.programId = ai.id
    double.maxSharedCredits = 9
    let catalog = Catalog(codes: [ec, ai, ai2], categories: [major, double], letterGrades: [a])
    func course(_ codes: [CourseCode], approved: Bool? = nil) -> Course {
        var c = Course(device: d, at: t, semesterId: nil, title: "", codes: codes.map(\.id), categoryIds: [major.id, double.id], credits: 3)
        c.finalGrade = a.id
        c.sharingApproved = approved
        return c
    }
    let shared = course([ec, ai2]), ecOnly = course([ec]), approved = course([ec], approved: true)
    let credits = GPACalculator.categoryCredits(courses: [shared, ecOnly, approved], catalog: catalog)
    #expect(credits[double.id]?.earned == 6 && credits[major.id]?.earned == 9)
    let s = GPACalculator.shared(courses: [shared, ecOnly, approved], catalog: catalog)
    #expect(s.count == 1 && s[0].courses.map(\.id) == [shared.id, approved.id] && s[0].unallowed.map(\.id) == [ecOnly.id] && !s[0].isOver)

    #expect(GPACalculator.blocksSharing(ecOnly, categoryIds: [major.id, double.id], catalog: catalog))
    #expect(!GPACalculator.blocksSharing(ecOnly, categoryIds: [major.id], catalog: catalog))
    #expect(!GPACalculator.blocksSharing(ecOnly, categoryIds: [double.id], catalog: catalog))
    #expect(!GPACalculator.blocksSharing(shared, categoryIds: [major.id, double.id], catalog: catalog))
    #expect(!GPACalculator.blocksSharing(approved, categoryIds: [major.id, double.id], catalog: catalog))
}
