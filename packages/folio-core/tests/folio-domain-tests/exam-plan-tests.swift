import FolioDomain
import Foundation
import Testing

struct ExamPlanTests {
    let device = UUID()
    let at = Date(timeIntervalSince1970: 1_790_000_000)

    func exam(_ title: String = "Midterm", start: Date? = nil, plan: [ExamPlanItem] = []) -> Exam {
        var e = Exam(device: device, at: at, kind: .midterm, title: title, start: start)
        e.plan = plan
        return e
    }

    @Test func planRoundTrips() throws {
        let unit = UUID()
        let original = exam(plan: [
            ExamPlanItem(day: LocalDate("2026-10-18")!, title: "1-3단원 복습", target: ExamPlanTarget(kind: .unit, id: unit)),
            ExamPlanItem(day: LocalDate("2026-10-19")!, title: "족보 풀기"),
        ])
        let data = try JSONEncoder().encode(original)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let first = try #require((json["plan"] as? [[String: Any]])?.first)
        #expect(first["day"] as? String == "2026-10-18")
        #expect((first["target"] as? [String: Any])?["kind"] as? String == "unit")
        #expect(try JSONDecoder().decode(Exam.self, from: data) == original)
    }

    @Test func examWithoutPlanKeyStillLoads() throws {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(exam())) as? [String: Any])
        json["plan"] = nil
        let decoded = try JSONDecoder().decode(Exam.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.plan.isEmpty)
        #expect(decoded.title == "Midterm")
    }

    @Test func latestCheckWins() {
        let a = UUID(), b = UUID(), c = UUID()
        let t = { (s: Double) in Date(timeIntervalSince1970: s) }
        // Logs from two devices arrive unsorted.
        let events: [(at: Date, event: PlanCheckEvent)] = [
            (t(30), PlanCheckEvent(itemId: a, done: false)),
            (t(10), PlanCheckEvent(itemId: a, done: true)),
            (t(10), PlanCheckEvent(itemId: b, done: true)),
            (t(20), PlanCheckEvent(itemId: b, done: false)),
            (t(40), PlanCheckEvent(itemId: b, done: true, auto: true)),
            (t(5), PlanCheckEvent(itemId: c, done: false)),
        ]
        #expect(ExamPlan.done(events) == [b])
    }

    @Test func todaysItemsAcrossCourses() {
        let today = LocalDate("2026-10-19")!
        let early = exam("Quiz1", start: at, plan: [ExamPlanItem(day: today, title: "카드 풀기"), ExamPlanItem(day: LocalDate("2026-10-20")!, title: "내일")])
        let late = exam("Midterm", start: at.addingTimeInterval(86400), plan: [ExamPlanItem(day: today, title: "족보"), ExamPlanItem(day: LocalDate("2026-10-18")!, title: "어제")])
        let one = CourseFile(course: Course(device: device, at: at, title: "그래프 이론"), exams: [late])
        let two = CourseFile(course: Course(device: device, at: at, title: "선형대수학"), exams: [early, exam("Final")])
        let items = ExamPlan.items(on: today, courses: [one, two])
        #expect(items.map(\.item.title) == ["카드 풀기", "족보"])
        #expect(items.map(\.courseId) == [two.course.id, one.course.id])
    }
}
