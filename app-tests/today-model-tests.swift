import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct TodayModelTests {
    @Test func noteRowsShowTheNewestFirstAndCountTheRest() throws {
        let model = TodayModel(workspace: try fixtureWorkspace())
        let items = Array(1...8)
        let (shown, more) = model.noteRows(items, limit: 6)
        #expect(shown == [8, 7, 6, 5, 4, 3])
        #expect(more == 2)
        #expect(model.noteRows(Array(items.prefix(2)), limit: 6).more == 0)
    }

    @Test func aReviewCountsTowardTodayOnceAndSkipsDoNot() throws {
        let workspace = try fixtureWorkspace()
        let model = TodayModel(workspace: workspace)
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let other = try #require(workspace.run(UnitAdd(course: graphTheory, title: "채색"))?.made)
        #expect(model.reviewProgress(now: .now).doneToday == 0)
        workspace.run(ReviewRecord(course: graphTheory, unit: unit, result: .good, start: .now.addingTimeInterval(-60), end: .now))
        workspace.run(ReviewRecord(course: graphTheory, unit: unit, result: .easy, start: .now.addingTimeInterval(-60), end: .now))
        workspace.skipReviews([(graphTheory, other)])
        let progress = model.reviewProgress(now: .now)
        #expect(progress.doneToday == 1)
        #expect(progress.streak == 1)
    }

    @Test func deadlinesGroupByDayAndNameTheMonthWhereItTurns() throws {
        let workspace = try fixtureWorkspace()
        let model = TodayModel(workspace: workspace)
        let c = workspace.calendar
        // Two days out, so the boundary hour never makes one of them today's.
        let base = try #require(c.date(byAdding: .day, value: 2, to: c.startOfDay(for: .now)))
        func at(_ days: Int, _ hour: Int) -> Date { c.date(byAdding: .hour, value: days * 24 + hour, to: base)! }
        let dues = [("A", at(0, 12)), ("B", at(0, 18)), ("C", at(1, 12)), ("D", at(42, 12))]
        for (title, due) in dues { workspace.run(AssignmentAdd(course: graphTheory, title: title, due: due)) }
        let summary = model.summary(now: .now)
        let days = model.deadlineDays(summary.deadlines.filter { ["A", "B", "C", "D"].contains($0.assignment.title) }, studyDay: summary.studyDay)
        #expect(days.map { $0.items.map(\.assignment.title) } == [["A", "B"], ["C"], ["D"]])
        #expect(days.allSatisfy { !$0.isToday })
        #expect(days[0].day == String(c.component(.day, from: at(0, 12))))
        // "월 " not "월": 월 alone is Monday.
        #expect(days[1].label.contains("월 ") == (c.component(.month, from: at(1, 12)) != c.component(.month, from: at(0, 12))))
        #expect(days[2].label.contains("월 "))

        model.edit(days[0].items[0])
        #expect(model.editing?.assignment.title == "A")
        #expect(model.editing?.course.id == graphTheory)
    }
}

@MainActor
struct QuickAddModelTests {
    @Test func savingAddsTheAssignmentAndClearsTheLine() throws {
        let workspace = try fixtureWorkspace()
        let model = QuickAddModel(workspace: workspace, fixedCourse: graphTheory)
        #expect(model.parsed == nil)
        model.text = "HW5 금 23:59"
        let parsed = try #require(model.parsed)
        #expect(model.canAdd(parsed))
        #expect(model.courseTitle(parsed) == "그래프 이론")
        #expect(model.due(parsed) != nil)
        model.add(parsed)
        #expect(model.text.isEmpty)
        #expect(workspace.course(graphTheory)?.file.assignments.contains { $0.title == "HW5" } == true)
    }
}

@MainActor
struct StudyTimeModelTests {
    @Test func barsStackPerDayAndSwitchToHoursPastTwoHours() throws {
        let workspace = try fixtureWorkspace()
        let model = StudyTimeModel(workspace: workspace)
        let today = workspace.today
        let robotics = UUID(uuidString: "C0000000-0000-4000-8000-000000000003")!
        model.bars = [.init(day: today, courseId: graphTheory, seconds: 1800), .init(day: today, courseId: robotics, seconds: 600)]
        var chart = model.chart
        #expect(!chart.inHours)
        #expect(chart.days.count == StudyTimeModel.days && chart.days.last == today)
        let todays = chart.segments.filter { $0.day == StudyTimeModel.todayLabel }
        #expect(todays.map(\.start).first == 0)
        #expect(todays.last.map { $0.end } == 40)
        #expect(model.tooltip(StudyTimeModel.todayLabel, in: chart)?.day == "오늘")
        #expect(model.axisLabel(30, inHours: false) == "30분")

        model.bars.append(.init(day: today, courseId: graphTheory, seconds: 2 * 3600))
        chart = model.chart
        #expect(chart.inHours)
    }

    @Test func dayLabels() throws {
        let today = try #require(LocalDate("2026-10-30"))
        #expect(StudyTimeModel.label(today, today: today) == "오늘")
        #expect(StudyTimeModel.label(try #require(LocalDate("2026-10-01")), today: today) == "10/1")
        #expect(StudyTimeModel.label(try #require(LocalDate("2026-10-12")), today: today) == "12")
    }
}
