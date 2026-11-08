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

    @Test func reviewNotesGroupByTheirClassDayNewestFirst() throws {
        let workspace = try fixtureWorkspace()
        let model = TodayModel(workspace: workspace)
        let c = workspace.calendar
        func at(_ day: Int, _ hour: Int) -> Date { c.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
        let today = workspace.settings.studyDay(of: at(28, 20), calendar: c)  // a Wednesday
        let dates = [at(26, 10), at(27, 10), at(28, 9), at(28, 13)]
        let ids = try dates.map { try #require(workspace.run(SessionAdd(course: graphTheory, date: $0))?.made) }
        let items = model.summary(now: at(28, 20)).missingReviewNotes.filter { ids.contains($0.session.id) }
        #expect(items.count == 4)

        let (groups, more) = model.noteGroups(items, today: today)
        #expect(groups.map { $0.items.map(\.session.date) } == [[at(28, 13), at(28, 9)], [at(27, 10)], [at(26, 10)]])
        #expect(groups[2].label == at(26, 10).formatted(.dateTime.weekday(.wide)))
        #expect(more == 0)

        let many = items + items
        #expect(model.noteGroups(many, today: today).more == 2)
        model.showsAllNotes = true
        #expect(model.noteGroups(many, today: today).more == 0)
    }

    @Test func aReviewCountsTowardTodayOnceAndSkipsDoNot() throws {
        let workspace = try fixtureWorkspace()
        let model = TodayModel(workspace: workspace)
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let other = try #require(workspace.run(UnitAdd(course: graphTheory, title: "채색"))?.made)
        #expect(model.reviewProgress(now: .now).doneToday == 0)
        workspace.run(ReviewRecord(course: graphTheory, unit: unit, result: .good, start: .now.addingTimeInterval(-60), end: .now))
        workspace.run(ReviewRecord(course: graphTheory, unit: unit, result: .easy, start: .now.addingTimeInterval(-60), end: .now))
        _ = workspace.skipReviews([(graphTheory, other)])
        let progress = model.reviewProgress(now: .now)
        #expect(progress.doneToday == 1)
        #expect(progress.streak == 1)
    }

    @Test func skippingSeveralReviewsAsksButOneDoesNot() throws {
        let workspace = try fixtureWorkspace()
        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let other = try #require(workspace.run(UnitAdd(course: graphTheory, title: "채색"))?.made)
        #expect(workspace.skipReviews([(graphTheory, unit)]) == nil)
        let pending = try #require(workspace.skipReviews([(graphTheory, unit), (graphTheory, other)]))
        // A list of course-and-unit pairs is told by its count, as the CLI tells it.
        #expect(pending.question.hasPrefix("단원 ") && pending.question.hasSuffix("의 복습을 건너뜁니다.") && pending.role == nil)
    }

    @Test func nearDeadlinesSayHowSoonAndFarOnesTheirDate() throws {
        let workspace = try fixtureWorkspace()
        let model = TodayModel(workspace: workspace)
        let c = workspace.calendar
        func at(_ day: Int, _ hour: Int) -> Date { c.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
        let now = at(28, 12)
        // C is six days out, the last one still "soon"; D, a week out, is the first given as a date.
        let dues = [("A", at(28, 20)), ("B", at(29, 23)), ("C", at(34, 9)), ("D", at(35, 9)), ("E", at(39, 12)), ("F", at(40, 9))]
        for (title, due) in dues { workspace.run(AssignmentAdd(course: graphTheory, title: title, due: due)) }
        let summary = model.summary(now: now)
        let mine = summary.deadlines.filter { dues.map(\.0).contains($0.assignment.title) }
        let rows = model.deadlineRows(mine, studyDay: summary.studyDay)
        #expect(rows.map(\.item.assignment.title) == ["A", "B", "C", "D", "E", "F"])
        #expect(rows.map(\.urgency) == [.urgent, .urgent, .soon, .later, .later, .later])
        #expect(rows[0].due.hasPrefix("오늘 "))
        #expect(rows[1].due.hasPrefix("내일 "))
        #expect(rows[2].due == "6일 후")
        #expect(rows[3].due == at(35, 9).formatted(.dateTime.month().day().weekday()))

        // Six fit; a seventh folds behind the button until it is pressed.
        #expect(model.shownDeadlines(rows).more == 0)
        workspace.run(AssignmentAdd(course: graphTheory, title: "G", due: at(41, 9)))
        let seven = model.deadlineRows(model.summary(now: now).deadlines.filter { "ABCDEFG".contains($0.assignment.title) }, studyDay: summary.studyDay)
        let (shown, more) = model.shownDeadlines(seven)
        #expect(more == 1)
        #expect(shown.map(\.item.assignment.title) == ["A", "B", "C", "D", "E", "F"])
        model.showsAllDeadlines = true
        #expect(model.shownDeadlines(seven).more == 0)

        model.edit(rows[0].item)
        #expect(model.editing?.assignment.title == "A")
        #expect(model.editing?.course.id == graphTheory)
    }

    @Test func deadlineDaysFollowTheDayBoundary() throws {
        let workspace = try fixtureWorkspace()
        let model = TodayModel(workspace: workspace)
        let c = workspace.calendar
        func at(_ day: Int, _ hour: Int) -> Date { c.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))! }
        #expect(workspace.settings.dayBoundaryMinutes == 4 * 60)
        // At 02:00 on the 29th the study day is still the 28th: 03:00 falls before the boundary, 05:00 after it.
        let dues = [("before", at(29, 3)), ("after", at(29, 5)), ("nextNight", at(30, 2)), ("third", at(30, 5))]
        for (title, due) in dues { workspace.run(AssignmentAdd(course: graphTheory, title: title, due: due)) }
        let summary = model.summary(now: at(29, 2))
        let rows = model.deadlineRows(summary.deadlines.filter { dues.map(\.0).contains($0.assignment.title) }, studyDay: summary.studyDay)
        #expect(rows.map(\.item.assignment.title) == ["before", "after", "nextNight", "third"])
        #expect(rows[0].due.hasPrefix("오늘 "))
        #expect(rows[1].due.hasPrefix("내일 "))
        #expect(rows[2].due.hasPrefix("내일 "))
        #expect(rows[3].due == "2일 후")
        #expect(rows.map(\.urgency) == [.urgent, .urgent, .urgent, .soon])
    }

    @Test func unitGroupsKeepQueueOrderAndEachUnitsPlaceInIt() throws {
        let workspace = try fixtureWorkspace()
        let model = TodayModel(workspace: workspace)
        let queue = workspace.reviewQueue(now: .now)
        let groups = model.unitGroups(queue)
        #expect(Set(groups.map(\.courseId)).count == groups.count)
        #expect(groups.flatMap(\.entries).count == queue.count)
        for group in groups { for pair in group.entries { #expect(queue[pair.index].item.unitId == pair.entry.item.unitId) } }
        // Courses come in the order of their first unit.
        let firsts = groups.compactMap { $0.entries.first?.index }
        #expect(firsts == firsts.sorted())
    }

    @Test func theWeekStripRunsMondayToSundayAroundTheStudyDay() throws {
        let workspace = try fixtureWorkspace()
        let model = TodayModel(workspace: workspace)
        let day = LocalDate(year: 2026, month: 10, day: 30)!  // a Friday
        let week = model.week(around: day)
        #expect(week.map(\.day.day) == [26, 27, 28, 29, 30, 31, 1])
        #expect(week.filter(\.isToday).map(\.day) == [day])
    }

    @Test func aCourseWithOnlyClassTimesShowsOnToday() throws {
        let workspace = try fixtureWorkspace()
        let c = workspace.calendar
        func at(_ hour: Int, _ minute: Int = 0) -> Date { c.date(from: DateComponents(year: 2026, month: 10, day: 29, hour: hour, minute: minute))! }
        workspace.pinnedNow = at(20)  // a Thursday in the fall term, past its midterm week
        let id = UUID()
        let code = addCode("GS", to: workspace)
        workspace.run(TranscriptAdd(id: id, semester: fallTerm, title: "콜로퀴움", code: code, number: "9331", credits: 0))
        workspace.run(CourseSet(course: id, [.schedule([ClassTime(weekday: 4, startMinute: 21 * 60, endMinute: 22 * 60, room: "Hall")])]))
        let model = TodayModel(workspace: workspace)
        let day = workspace.settings.studyDay(of: at(20), calendar: c)

        let ribbon = model.ribbonClasses(model.summary(now: at(20)), now: at(20)).filter { $0.courseId == id }
        #expect(ribbon.map(\.start) == [at(21)] && ribbon.first?.sessionId == nil)
        // A planned class has no name yet; its tooltip skips the empty part instead of doubling the dot.
        let help = model.ribbonHelp(try #require(ribbon.first))
        #expect(help.hasPrefix(model.title(id) + " · ") && !help.contains(" ·  · ") && help.components(separatedBy: " · ").count == 2)
        #expect(model.nextClass(after: at(20))?.courseId == id)
        #expect(model.nowCourse(at: at(21, 30)) == id && model.nowCourse(at: at(22)) != id)
        #expect(model.week(around: day).first { $0.day == day }?.courses.contains(id) == true)
        #expect(model.week(around: day).first { $0.day != day }?.courses.contains(id) == false)
    }

    @Test func washTakesEachCourseOnceInClassOrder() throws {
        let workspace = try fixtureWorkspace()
        let model = TodayModel(workspace: workspace)
        let other = try #require(model.current.map(\.id).first { $0 != graphTheory })
        let c = workspace.calendar
        func at(_ hour: Int) -> Date { c.date(byAdding: .hour, value: hour, to: c.startOfDay(for: .now))! }
        for (course, hour) in [(other, 9), (graphTheory, 13), (other, 15)] { workspace.run(SessionAdd(course: course, date: at(hour))) }
        // The fixture's own timetable may add other courses to the day; only these two's order is pinned here.
        let wash = model.washCourses(model.summary(now: at(12)), now: at(12))
        #expect(wash.filter { [other, graphTheory].contains($0) } == [other, graphTheory])
        #expect(Set(wash).count == wash.count)
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
        #expect(model.due(parsed)?.hasSuffix("(금) 23:59") == true)
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

@MainActor
struct ScenarioWorkspaceTests {
    @Test func aBusyDayHasStudyTimeOnItsPinnedDay() async throws {
        let workspace = try Workspace.scenario(.busyDay)
        #expect(workspace.today == LocalDate("2026-11-04"))
        let model = StudyTimeModel(workspace: workspace)
        await model.load()
        #expect(Set(model.bars.map(\.day)).count == 6)
    }
}
