import FolioActions
import FolioCore
import FolioDomain
import Foundation
import Testing

@testable import Folio

// 그래프 이론에 범위 단원 둘과 정리 노트 둘을 두고, 열흘 뒤의 기말을 오늘부터 나흘에 놓는다. 채색에는 정리 노트가 없다.
@MainActor
struct PlanModelTests {
    struct Planned {
        let workspace: Workspace
        let exam: UUID
        let hall: UUID
        let paths: UUID
        let coloring: UUID
    }

    func planned() throws -> Planned {
        let workspace = try fixtureWorkspace()
        // 가을학기 안의 날이다. 오늘 화면의 계획은 이번 학기 과목만 본다.
        workspace.pinnedNow = workspace.calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 11, minute: 20))
        let matching = try #require(workspace.run(UnitAdd(course: graphTheory, title: "매칭"))?.made)
        let coloring = try #require(workspace.run(UnitAdd(course: graphTheory, title: "채색"))?.made)
        let start = try #require(workspace.today.adding(days: 10).date(in: workspace.calendar)).addingTimeInterval(9 * 3600)
        let exam = try #require(
            workspace.run(ExamAdd(course: graphTheory, title: "기말고사", start: start, scope: [matching, coloring]))?.made)
        let hall = try #require(
            workspace.run(
                NoteAdd(
                    course: graphTheory, title: "기말 01 홀의 정리", kind: .unit,
                    body: "# 홀의 정리\n\n> [!theorem] Hall\n> 조건을 만족하면 완전 매칭이 있다.\n", units: [matching]))?.made)
        let paths = try #require(
            workspace.run(NoteAdd(course: graphTheory, title: "기말 02 증가 경로", kind: .unit, body: "# 증가 경로\n", units: [matching]))?
                .made)
        workspace.run(ExamPlanMake(course: graphTheory, exam: exam, start: workspace.today, end: workspace.today.adding(days: 3)))
        return Planned(workspace: workspace, exam: exam, hall: hall, paths: paths, coloring: coloring)
    }

    @Test func theCourseBoardShowsTodayAsRowsAndLaterDaysAsCards() throws {
        let p = try planned()
        let model = PlanModel(workspace: p.workspace, scope: .course(graphTheory))
        let board = model.board
        // 나흘에 노트 둘이라 오늘과 모레다. 노트 만들기는 첫날 맨 앞이다.
        #expect(board.today.map(\.title) == ["정리 노트 만들기", "기말 01 홀의 정리"])
        #expect(board.today[1].steps.map(\.stage) == [.read, .proof, .solve])
        #expect(model.detail(board.today[0]) == "채색 단원" && model.detail(board.today[1]).isEmpty)
        #expect(model.badge(board.today[0])?.text == "노트 없음" && model.steps(board.today[0]).isEmpty)
        #expect(model.todayNote(board) == model.dayLabel(p.workspace.today) + " · 노트 1")
        #expect(board.next.map(\.day) == [p.workspace.today.adding(days: 2)])
        #expect(model.daySummary(board.next[0]) == "노트 1")
        #expect(model.nextNote(board) == model.dayLabel(p.workspace.today.adding(days: 2)) + "부터 · 남은 노트 1")
        #expect(model.showsNext && !model.showsCourse && !model.addsTasks)

        // 오늘 화면은 과목 이름을 줄에 적고 다음 날은 보이지 않는다.
        let today = PlanModel(workspace: p.workspace, scope: .today)
        #expect(today.board.today.map(\.title) == board.today.map(\.title))
        #expect(today.detail(today.board.today[0]) == "그래프 이론 · 채색 단원" && today.showsCourse && !today.showsNext)
        #expect(today.periods.isEmpty)
    }

    @Test func pressingAStepOpensItsPlace() throws {
        let p = try planned()
        let model = PlanModel(workspace: p.workspace, scope: .course(graphTheory))
        let rows = model.board.today
        guard case .link(let unit, let besideUnit)? = model.destination(rows[0], stage: nil),
            case .link(let name, let besideName)? = model.destination(rows[1], stage: nil),
            case .link(let note, let cards)? = model.destination(rows[1], stage: .read),
            case .link(let problems, let besideProblems)? = model.destination(rows[1], stage: .proof)
        else {
            Issue.record("no link")
            return
        }
        #expect(unit == AppLink(.unit, p.coloring) && note == AppLink(.note, p.hall) && name == note)
        #expect(problems == .course(graphTheory, page: .problems))
        // 정독 칩만 노트 옆 칸에 그 노트의 카드를 연다. 줄의 이름은 노트만 연다.
        #expect(cards == AppLink(.noteCards, p.hall) && besideUnit == nil && besideName == nil && besideProblems == nil)
    }

    // 정독 칩은 노트에 이은 카드 가운데 넘긴 만큼을 적고, 다 넘기면 끝난 칩이 된다.
    @Test func theReadChipCountsTheNotesFlippedCards() throws {
        let p = try planned()
        let unit = try #require(p.workspace.course(graphTheory)?.file.notes.first { $0.id == p.hall }?.unitIds.first)
        var cards = (0..<3).map { StudyCard(device: p.workspace.device, at: p.workspace.now, unitId: unit, front: "카드 \($0)", back: "뒤") }
        cards.append(
            StudyCard(
                device: p.workspace.device, at: p.workspace.now, unitId: unit, kind: .trueFalse, front: "문장", back: "이유", answer: false))
        p.workspace.run(CardSave(course: graphTheory, cards: cards, note: p.hall))
        let model = PlanModel(workspace: p.workspace, scope: .course(graphTheory))
        func read() throws -> (row: PlanRow, step: PlanRow.Step) {
            let row = try #require(model.board.today.last)
            return (row, try #require(row.steps.first { $0.stage == .read }))
        }
        #expect(try read().step.progress == PlanProgress(done: 0, total: 4))
        #expect(model.chip(try read().step, in: try read().row) == "정독")

        p.workspace.run(CardFlip(course: graphTheory, unit: unit, card: cards[0].id, known: false))
        p.workspace.run(CardFlip(course: graphTheory, unit: unit, card: cards[3].id, answer: true))
        #expect(try read().step.progress == PlanProgress(done: 2, total: 4))
        #expect(model.chip(try read().step, in: try read().row) == "정독 2/4")

        for card in cards[1...2] { p.workspace.run(CardFlip(course: graphTheory, unit: unit, card: card.id)) }
        #expect(try read().step.isDone && model.chip(try read().step, in: try read().row) == "정독")
    }

    @Test func postponingAdvancingAndPickingADayMoveOnlyThatRow() throws {
        let p = try planned()
        let model = PlanModel(workspace: p.workspace, scope: .course(graphTheory))
        let today = p.workspace.today
        let hall = try #require(model.board.today.last)
        // 정독을 끝낸 뒤 미루면 남은 증명과 문제풀이만 내일로 간다.
        model.toggle(hall.steps[0], in: hall)
        let left = try #require(model.board.today.last)
        #expect(left.steps.map(\.isDone) == [true, false, false] && model.postponesToTomorrow(left) && model.canPostpone(left))
        #expect(
            left.steps.map(\.progress) == [
                PlanProgress(done: 1, total: 1), PlanProgress(done: 0, total: 1), PlanProgress(done: 0, total: 1),
            ])
        #expect(model.chip(left.steps[0], in: left) == "정독" && model.chip(left.steps[1], in: left) == "증명")
        model.postpone(left)
        var board = model.board
        #expect(board.today.last?.steps.map(\.stage) == [.read] && board.today.last?.isDone == true)
        #expect(board.next.map(\.day) == [today.adding(days: 1), today.adding(days: 2)])
        let moved = try #require(board.next.first?.rows.first)
        #expect(moved.steps.map(\.stage) == [.proof, .solve] && moved.lateFrom == today)
        // 미뤄도 단계의 진행은 그대로다.
        #expect(moved.steps.map(\.progress) == left.steps.dropFirst().map(\.progress))
        #expect(board.next[1].rows.map(\.title) == ["기말 02 증가 경로"])

        // 모레의 노트를 오늘로 앞당긴다.
        let paths = try #require(board.next[1].rows.first)
        #expect(paths.commands(today: today).contains(.advance))
        model.advance(paths)
        board = model.board
        #expect(board.today.map(\.title).contains("기말 02 증가 경로") && board.next.map(\.day) == [today.adding(days: 1)])

        // 날짜 고르기는 오늘부터 시험 전날까지에서 지금 있는 날을 뺀 날을 내놓는다.
        let again = try #require(board.next.first?.rows.first)
        let days = model.moveDays(again)
        #expect(days.count == 9 && !days.contains(today.adding(days: 1)) && days.first == today && days.last == today.adding(days: 9))
        model.move(again, to: today.adding(days: 5))
        #expect(model.board.next.map(\.day) == [today.adding(days: 5)] && model.board.next[0].rows[0].isLate == false)
    }

    @Test func removingARowAsksOnceAndKeepsItOut() throws {
        let p = try planned()
        let model = PlanModel(workspace: p.workspace, scope: .course(graphTheory))
        let row = try #require(model.board.today.last)
        model.remove(row)
        let pending = try #require(model.pending)
        #expect(pending.question.contains("기말 01 홀의 정리 정독") && pending.refusal == nil)
        pending.perform()
        #expect(model.board.today.map(\.title) == ["정리 노트 만들기"])
        p.workspace.replanExams()
        #expect(model.board.today.map(\.title) == ["정리 노트 만들기"])
    }

    @Test func changingThePeriodPlacesTheNotesAgain() throws {
        let p = try planned()
        let model = PlanModel(workspace: p.workspace, scope: .course(graphTheory))
        let today = p.workspace.today
        let period = try #require(model.periods.first)
        #expect(model.periods.count == 1 && period.period == ExamPlanPeriod(start: today, end: today.adding(days: 3)))
        #expect(model.periodNote(model.periods) == model.dayLabel(today) + " – " + model.dayLabel(today.adding(days: 3)))

        let end = try #require(today.adding(days: 1).date(in: p.workspace.calendar))
        model.setEnd(end, of: period)
        #expect(model.periods.first?.period.end == today.adding(days: 1))
        #expect(model.board.next.map(\.day) == [today.adding(days: 1)])

        // 끝낼 날이 시험 날이면 받지 않는다.
        let examDay = try #require(today.adding(days: 10).date(in: p.workspace.calendar))
        model.setEnd(examDay, of: try #require(model.periods.first))
        #expect(model.periods.first?.period.end == today.adding(days: 1) && p.workspace.error != nil)
    }

    @Test func aNewNoteIsPlacedWithoutTheUserAsking() throws {
        let p = try planned()
        let model = PlanModel(workspace: p.workspace, scope: .course(graphTheory))
        p.workspace.replanExams()
        let before = model.board
        p.workspace.run(NoteAdd(course: graphTheory, title: "기말 03 채색수", kind: .unit, body: "# 채색수\n", units: [p.coloring]))
        p.workspace.replanExams()
        let after = model.board
        #expect(before.today.first?.title == "정리 노트 만들기" && !after.today.contains { $0.title == "정리 노트 만들기" })
        #expect(after.nextNotes + after.notes == before.nextNotes + before.notes + 1)
    }

    @Test func theExamScopeAddsWrittenTasksAndFoldsLaterDays() throws {
        let p = try planned()
        let model = PlanModel(workspace: p.workspace, scope: .exam(course: graphTheory, exam: p.exam))
        #expect(model.addsTasks && !model.canAdd)
        model.newTitle = " 교재 3장 다시 읽기 "
        #expect(model.canAdd)
        for offset in [4, 5, 6, 7] {
            model.newTitle = "할 일 \(offset)"
            model.newDay = try #require(p.workspace.today.adding(days: offset).date(in: p.workspace.calendar))
            model.add()
        }
        #expect(model.newTitle.isEmpty)
        let board = model.board
        let shown = p.workspace.settings.study.planShownDays
        #expect(board.next.count == 5 && model.days(board).shown.count == shown && model.days(board).folded == 5 - shown)
        model.showsAll = true
        #expect(model.days(board).shown.count == 5)
        let custom = try #require(board.next.last?.rows.first)
        #expect(model.label(custom.steps[0], in: custom) == "완료" && model.destination(custom, stage: nil) == nil)
    }
}
