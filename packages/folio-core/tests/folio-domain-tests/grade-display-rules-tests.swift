import FolioDomain
import Foundation
import Testing

/// Made-up grades only: the repository is public.
struct GradeDisplayRulesTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)

    @Test func trendSkipsCreditedAndUngradedTermsButCumulativeCountsThem() {
        let a = LetterGrade(device: device, at: now, symbol: "A0", points: 4, countsInGpa: true, countsInCredits: true)
        let b = LetterGrade(device: device, at: now, symbol: "B0", points: 3, countsInGpa: true, countsInCredits: true)
        let catalog = Catalog(letterGrades: [a, b])
        let fall = Semester(device: device, at: now, year: 2025, term: .fall)
        let credited = Semester(device: device, at: now, year: 2025, term: .credited, creditedHours: 9)
        let spring = Semester(device: device, at: now, year: 2026, term: .spring)
        let summer = Semester(device: device, at: now, year: 2026, term: .summer)
        func course(_ s: Semester, _ credits: Double, _ grade: LetterGrade?) -> Course {
            var c = Course(device: device, at: now, semesterId: s.id, title: "", credits: credits)
            c.finalGrade = grade?.id
            return c
        }
        let courses = [course(fall, 3, a), course(fall, 3, b), course(spring, 2, a), course(summer, 3, nil)]

        let trend = GPACalculator.trend(semesters: [fall, credited, spring, summer], courses: courses, catalog: catalog)
        #expect(trend.map(\.semester.id) == [fall.id, spring.id])
        // Fall: (12 + 9) / 6. Spring alone: 8 / 2; through spring: (21 + 8) / 8, the credited hours adding no GPA.
        #expect(trend.map(\.gpa) == [3.5, 4])
        #expect(trend.map(\.credits) == [6, 2])
        #expect(trend.map(\.cumulative) == [3.5, 3.625])
    }

    @Test func treeKeepsChildrenUnderTheirRootsGroup() {
        let major = Category(device: device, at: now, name: "전공", group: "전공")
        let required = Category(device: device, at: now, name: "전공필수", group: "다른 묶음", parentId: major.id)
        let orphan = Category(device: device, at: now, name: "고아", group: "기초", parentId: UUID())
        let deep = Category(device: device, at: now, name: "세부", parentId: required.id)
        let rows = Category.tree([deep, orphan, required, major])
        #expect(rows.map(\.category.name) == ["고아", "전공", "전공필수", "세부"])
        #expect(rows.map(\.depth) == [0, 0, 1, 2])
        #expect(rows.map(\.group) == ["기초", "전공", "전공", "전공"])
        // Groups come only from categories without a parent field, not from ones whose parent is missing.
        #expect(Category.groups([deep, orphan, required, major]) == ["전공"])
    }

    @Test func requirementStatusByCreditsOrCount() {
        var credits = Category(device: device, at: now, name: "전공선택", minCredits: 18, maxCredits: 24)
        var s = RequirementStatus(category: credits, credits: CategoryCredits(earned: 15, inProgress: 6))
        #expect(!s.countsCourses && s.done == 15 && s.taking == 6 && s.goal == 18 && !s.met && !s.over)
        s = RequirementStatus(category: credits, credits: CategoryCredits(earned: 27))
        #expect(s.met && s.over)

        credits.minCredits = 0
        #expect(RequirementStatus(category: credits, credits: CategoryCredits(earned: 3)).goal == nil)
        #expect(!RequirementStatus(category: credits, credits: CategoryCredits(earned: 3)).met)

        let colloquium = Category(device: device, at: now, name: "콜로퀴움", minCount: 2)
        s = RequirementStatus(category: colloquium, credits: CategoryCredits(passed: 2, taking: 1))
        #expect(s.countsCourses && s.done == 2 && s.taking == 1 && s.goal == 2 && s.met)
    }

    @Test func gradeLinesHeadARunWithItsSummedWeight() {
        func component(_ name: String, _ weight: Double, _ group: String?) -> GradeComponent {
            var c = GradeComponent(device: device, at: now, name: name, weight: weight)
            c.group = group
            return c
        }
        let quiz = component("Quiz", 10, nil)
        let materials = component("Materials", 5, "Reports")
        let results = component("Results", 15, "Reports")
        let final = component("Final", 40, nil)
        let late = component("Discussion", 5, "Reports")
        let score = ScoreEntry(device: device, at: now, componentId: results.id, title: "1", score: 8, max: 10)

        let lines = GradeLine.lines([quiz, materials, results, final, late], scores: [score])
        #expect(lines == [
            .component(quiz, indented: false),
            .group("Reports", weight: 20, first: materials.id),
            .component(materials, indented: true),
            .component(results, indented: true),
            .entry(score, indented: true),
            .component(final, indented: false),
            .group("Reports", weight: 5, first: late.id),
            .component(late, indented: true),
        ])
        // Two runs with the same name stay apart.
        #expect(Set(lines.map(\.id)).count == lines.count)
    }
}
