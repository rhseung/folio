import FolioActions
import FolioDomain
import Foundation
import SwiftUI
import Testing

@testable import Folio

@MainActor
struct SessionsModelTests {
    func session(_ workspace: Workspace, daysFromNow days: Int) throws -> Session {
        let date = Calendar.current.date(byAdding: .day, value: days, to: .now)!
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: date))?.made)
        return try #require(workspace.course(graphTheory)?.file.sessions.first { $0.id == id })
    }

    // CLI나 Claude 제안은 24:00(1440)에 끝나는 수업을 넣을 수 있다. 범위의 끝이 시작보다 앞서 멈추지 않아야 한다.
    @Test func aClassEndingAtMidnightShowsARange() {
        #expect(TimePicker.range(22 * 60, 1440) != TimePicker.label(22 * 60))
        #expect(TimePicker.range(600, 600) == TimePicker.label(600))
    }

    @Test func subtitleCountsSessionsAndMissingReviewNotes() throws {
        let workspace = try fixtureWorkspace()
        workspace.run(CourseSet(course: graphTheory, [.schedule([])]))
        let model = SessionsModel(workspace: workspace, courseId: graphTheory)
        #expect(model.subtitle(try #require(workspace.course(graphTheory)).file) == "회차가 아직 없습니다")
        _ = try session(workspace, daysFromNow: -2)
        _ = try session(workspace, daysFromNow: 3)
        #expect(model.subtitle(try #require(workspace.course(graphTheory)).file) == "회차 2개 · 남은 수업 1개 · 복습 노트 없음 1")
    }

    @Test func aClassWithNoEndOffersJoinUntilTheEndTheFormShows() throws {
        let workspace = try fixtureWorkspace()
        workspace.run(CourseSet(course: graphTheory, [.schedule([])]))
        // 시계와 상관없이 공부일의 10:30을 쓴다. 밤늦게는 폼의 끝이 그날의 끝에서 멈추지만 메뉴는 그렇지 않고, 하루 경계 전에는 달력의 오늘이 공부일과 다르기 때문이다.
        let day = try #require(workspace.today.date(in: Calendar.current))
        let start = try #require(Calendar.current.date(byAdding: .minute, value: 10 * 60 + 30, to: day))
        let id = try #require(workspace.run(SessionAdd(course: graphTheory, date: start, link: "https://zoom.us/j/1"))?.made)
        let s = try #require(workspace.course(graphTheory)?.file.sessions.first { $0.id == id })
        func formEnd() -> Date { SessionSheetModel(workspace: workspace, course: graphTheory, session: s.id).end }
        func joins(at now: Date) throws -> Bool {
            try #require(workspace.course(graphTheory)).file
                .commands(for: s, at: now, host: .own, classMinutes: workspace.settings.classMinutes, calendar: workspace.calendar)
                .contains(.join)
        }

        #expect(formEnd() == start.addingTimeInterval(TimeInterval(workspace.settings.classMinutes * 60)))
        #expect(try joins(at: formEnd().addingTimeInterval(-60)))
        #expect(try !joins(at: formEnd()))

        workspace.run(CourseSet(course: graphTheory, [.schedule([ClassTime(weekday: 1, startMinute: 13 * 60, endMinute: 15 * 60)])]))
        #expect(formEnd() == start.addingTimeInterval(2 * 3600))
        #expect(try joins(at: formEnd().addingTimeInterval(-60)))
        #expect(try !joins(at: formEnd()))
    }

    @Test func theTableRunsWeekByWeekAndAnExamOffTheTimetableGoesToTheOtherCell() throws {
        let workspace = try fixtureWorkspace()
        workspace.run(CourseSet(course: graphTheory, [.schedule([])]))
        let model = SessionsModel(workspace: workspace, courseId: graphTheory)
        _ = try session(workspace, daysFromNow: -14)
        _ = try session(workspace, daysFromNow: 14)
        workspace.run(ExamAdd(course: graphTheory, title: "중간", start: Calendar.current.date(byAdding: .day, value: 1, to: .now)!))
        let table = model.table(try #require(workspace.course(graphTheory)).file)
        #expect(table.columns.isEmpty)
        #expect(table.weeks.map(\.start) == table.weeks.map(\.start).sorted())
        #expect(table.weeks.filter(\.isThisWeek).count == 1)
        // 시간표가 없으므로 모든 일정이 "그 밖" 칸에 있다.
        let entries = table.weeks.flatMap(\.other.entries)
        #expect(entries.count == 3)
        #expect(entries.contains { $0.subject == "중간" && $0.look == .exam })
    }

    @Test func plannedClassesRunToTheTermsEndAndCancellingOneSavesIt() throws {
        let workspace = try fixtureWorkspace()
        workspace.run(
            CourseSet(course: graphTheory, [.schedule([ClassTime(weekday: 2, startMinute: 10 * 60 + 30, endMinute: 11 * 60 + 45)])]))
        let model = SessionsModel(workspace: workspace, courseId: graphTheory)
        let course = try #require(workspace.course(graphTheory))
        let semester = try #require(workspace.semester(of: course.file.course))
        let end = try #require(semester.end?.date(in: workspace.calendar))
        let now = try #require(semester.start?.date(in: workspace.calendar)).addingTimeInterval(7 * 7 * 86_400)
        func planned() throws -> [Session] {
            model.table(try #require(workspace.course(graphTheory)).file, now: now).weeks.flatMap(\.cells).flatMap(\.entries)
                .compactMap { if case .planned(let s) = $0.item { s } else { nil } }
        }

        let plan = try planned()
        #expect(plan.count >= 2 && plan.allSatisfy { $0.date > now && $0.date <= end })
        #expect(plan.allSatisfy { workspace.calendar.isoWeekday(of: $0.date) == 2 })

        let second = try #require(workspace.plannedSessions(for: course, now: now).first { $0.draft.date == plan[1].date })
        model.menu.make(second, kind: .cancelled)
        let saved = try #require(workspace.course(graphTheory)?.file.sessions.first { $0.date == second.suggestion.date })
        #expect(saved.isCancelled && saved.week == second.draft.week)
        #expect(try planned().map(\.date) == plan.map(\.date).filter { $0 != second.suggestion.date })
        #expect(model.subtitle(try #require(workspace.course(graphTheory)).file, now: now).contains("남은 수업 \(plan.count - 1)개"))
    }

    @Test func titleIsTheUnitsElseClass() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionsModel(workspace: workspace, courseId: graphTheory)
        let s = try session(workspace, daysFromNow: -1)
        func entry() throws -> SessionTableEntry {
            let file = try #require(workspace.course(graphTheory)).file
            return try #require(model.table(file).weeks.flatMap(\.cells).flatMap(\.entries).first { $0.session?.id == s.id })
        }
        #expect(model.title(try entry()) == "수업")
        #expect(model.isUntitled(try entry()))

        let unit = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        workspace.run(UnitLink(course: graphTheory, unit: unit, sessions: [s.id]))
        #expect(model.title(try entry()) == "매칭")
        #expect(!model.isUntitled(try entry()))
    }

    @Test func aLinkToASessionScrollsToItsWeekAndOpensIt() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionsModel(workspace: workspace, courseId: graphTheory)
        let s = try session(workspace, daysFromNow: -21)
        let table = model.table(try #require(workspace.course(graphTheory)).file)
        model.follow(nil, in: table)
        #expect(model.anchor?.id == AnyHashable(table.thisWeek) && model.anchor?.animated == false)
        #expect(model.popover == nil)
        model.follow(s.id, in: table)
        #expect(model.popover == s.id)
        #expect(model.anchor?.id == table.week(containing: s.id).map(AnyHashable.init) && model.anchor?.animated == true)
    }

    @Test func untouchedFutureSessionsAreListedAndRemovedTogether() throws {
        let workspace = try fixtureWorkspace()
        let model = SessionsModel(workspace: workspace, courseId: graphTheory)
        _ = try session(workspace, daysFromNow: 7)
        _ = try session(workspace, daysFromNow: -7)
        model.loadUntouched(try #require(workspace.course(graphTheory)))
        #expect(model.untouched.count == 1 && model.untouchedMore == 0)
        model.removeUntouched()
        try #require(model.pending).perform()
        #expect(workspace.course(graphTheory)?.file.sessions.count == 1)
    }

    @Test func removingALinkedSessionSaysWhyInsteadOfAsking() throws {
        let workspace = try fixtureWorkspace()
        let free = try session(workspace, daysFromNow: 7)
        var noted = try session(workspace, daysFromNow: 14)
        workspace.run(SessionNote(course: graphTheory, session: noted.id, kind: .rough))
        noted = try #require(workspace.course(graphTheory)?.file.sessions.first { $0.id == noted.id })
        let count = try #require(workspace.course(graphTheory)).file.sessions.count

        var asked: PendingAction?
        func remove(_ s: Session) {
            let source = SessionMenuSource(
                workspace: workspace, courseId: graphTheory, session: s, host: .own, now: workspace.now, openNote: { _ in },
                openLink: OpenLinkAction(), openURL: OpenURLAction { _ in .handled },
                sheets: ItemSheetsAction(confirm: { asked = $0 }))
            if case .action(let action) = source.row(.remove).kind { action() }
        }

        remove(noted)
        #expect(asked?.refusal != nil)
        remove(free)
        let pending = try #require(asked)
        #expect(pending.refusal == nil && pending.question.hasPrefix("회차 ") && pending.question.hasSuffix("을(를) 지웁니다."))
        #expect(try #require(workspace.course(graphTheory)).file.sessions.count == count)
        pending.perform()
        #expect(try #require(workspace.course(graphTheory)).file.sessions.count == count - 1)
    }

    // LaunchServices는 Zoom 앱 실행 결과를 background queue에서 알려 준다. 실행이 거절되어도 웹 링크는 열려야 한다.
    @Test func joinFallsBackToTheWebLinkFromABackgroundQueue() async {
        let web = URL(string: "https://zoom.us/j/1")!
        let opened = await withCheckedContinuation { (done: CheckedContinuation<URL, Never>) in
            let fallback = JoinOnlineButton.fallback(
                to: web,
                with: OpenURLAction { url in
                    done.resume(returning: url)
                    return .handled
                })
            DispatchQueue.global().async { fallback(false) }
        }
        #expect(opened == web)
    }
}
