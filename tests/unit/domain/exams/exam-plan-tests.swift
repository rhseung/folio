import FolioCore
import FolioDomain
import Foundation
import Testing

struct ExamPlanTests {
    let device = UUID()
    let at = Date(timeIntervalSince1970: 1_790_000_000)

    func exam(_ title: String = "Midterm", start: Date? = nil, plan: [ExamPlanItem] = []) -> Exam {
        var e = Exam(device: device, at: at, title: title, start: start)
        e.plan = plan
        return e
    }

    func custom(_ day: LocalDate, _ title: String) -> ExamPlanItem {
        ExamPlanItem(day: day, target: ExamPlanTarget(kind: .custom), title: title, edited: true)
    }

    @Test func planRoundTrips() throws {
        let unit = UUID()
        let original = exam(plan: [
            ExamPlanItem(day: ymd("2026-10-18"), target: .unit(unit)),
            ExamPlanItem(day: ymd("2026-10-19"), target: ExamPlanTarget(kind: .custom), title: "족보 풀기", edited: true),
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
        let today = ymd("2026-10-19")
        let early = exam(
            "Quiz1", start: at, plan: [custom(today, "카드 풀기"), custom(ymd("2026-10-20"), "내일")])
        let late = exam(
            "Midterm", start: at.addingTimeInterval(86400),
            plan: [custom(today, "족보"), custom(ymd("2026-10-18"), "어제")])
        let one = CourseFile(course: Course(device: device, at: at, title: "그래프 이론"), exams: [late])
        let two = CourseFile(course: Course(device: device, at: at, title: "선형대수학"), exams: [early, exam("Final")])
        let items = ExamPlan.items(on: today, courses: [one, two])
        #expect(items.map(\.item.title) == ["카드 풀기", "족보"])
        #expect(items.map(\.courseId) == [two.course.id, one.course.id])
    }
}

private func ymd(_ text: String) -> LocalDate {
    guard let day = LocalDate(text) else { preconditionFailure(text) }
    return day
}
