import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

/// The fixture course gets two units and three cards; the first card is answered wrong today.
@MainActor
struct QuizFixture {
    let workspace: Workspace
    let courseId: UUID
    let units: [UUID]
    let cards: [QuizCard]
    let model: QuizModel

    init() throws {
        workspace = try fixtureWorkspace()
        courseId = try #require(workspace.courses.first).id
        units = [UUID(), UUID()]
        workspace.run(UnitAdd(id: units[0], course: courseId, title: "그래프"))
        workspace.run(UnitAdd(id: units[1], course: courseId, title: "트리"))
        let d = workspace.device
        cards = [QuizCard(device: d, at: .now, unitId: units[0], type: .free, category: .definition, prompt: "p1", answer: "a1"),
                 QuizCard(device: d, at: .now, unitId: units[0], type: .free, category: .theorem, prompt: "p2", answer: "a2"),
                 QuizCard(device: d, at: .now, unitId: units[1], type: .free, category: .definition, prompt: "p3", answer: "a3")]
        workspace.run(QuizCardSave(course: courseId, cards: cards))
        workspace.run(QuizRecord(course: courseId, attempt: QuizAttemptEvent(cardId: cards[0].id, verdict: .wrong, grader: .self)))
        model = QuizModel(workspace: workspace)
        model.load(course)
    }

    var course: LoadedCourse { workspace.course(courseId)! }
}

@MainActor
struct QuizModelTests {
    @Test func cardsAreGroupedUnderTheirUnitsAndCounted() throws {
        let f = try QuizFixture()
        #expect(f.model.cardsSubtitle(f.course) == "카드 3장 · 단원 2개 · 오답 1장")
        let groups = f.model.cardGroups(f.course)
        #expect(groups.count == 1 && groups[0].root == nil && groups[0].count == 3)
        let shape = groups[0].entries.map { entry -> String in
            switch entry {
            case .unit(let u, _, let n): "\(u.title):\(n)"
            case .card(let c, let depth): "\(c.prompt)@\(depth)"
            }
        }
        #expect(shape == ["그래프:2", "p1@1", "p2@1", "트리:1", "p3@1"])
        #expect(f.model.unitCardsText(0) == "카드 없음")
        #expect(f.model.isOpen(f.cards[0]) && !f.model.isOpen(f.cards[1]))
    }

    @Test func statsCountTheOpenWrongAnswerAndTodaysAttempt() throws {
        let f = try QuizFixture()
        let stats = f.model.stats(f.course)
        #expect(stats.total.open == 1 && stats.due.map(\.id) == [f.cards[0].id] && stats.solvedToday == 1)
        #expect(stats.shownUnits.map(\.title) == ["그래프", "트리"])
        #expect(f.model.dueChip(f.cards[0]).tone == .danger)
        #expect(f.model.dueEmpty == "남은 오답이 없습니다")
        #expect(f.model.solveWrong(of: f.units[1], units: stats.units).label == "오답 · 트리")
        let days = f.model.dailyCounts(today: f.workspace.today)
        #expect(days.count == 14 && days.last?.day == f.workspace.today && days.last?.count == 1)
        #expect(days.dropLast().allSatisfy { $0.count == 0 })
    }

    @Test func problemSetsAreAddedAndSummarized() throws {
        let f = try QuizFixture()
        #expect(f.model.problemsSubtitle(f.course).hasPrefix("문제집, 증명집"))

        let draft = ProblemSetDraftModel(workspace: f.workspace, course: f.course)
        #expect(!draft.canAdd && draft.numbersDetail == "예: 1-10, 12, 13a")
        draft.title = "  족보 "
        draft.numbers = "1-3"
        draft.unitIds = [f.units[0]]
        #expect(draft.canAdd && draft.numbersDetail == "3문제")
        draft.add()

        let set = try #require(f.course.file.problemSets.first)
        #expect(set.title == "족보")
        f.model.record(.wrong, set: set.id, number: "1", in: f.course)
        #expect(f.model.problemsSubtitle(f.course) == "묶음 1개 · 문제 3개 · 푼 문제 1개 · 남은 오답 1")
        #expect(f.model.summary(set) == "3문제 · 맞음 0 · 틀림 1 · 해결 0 · 안 푼 2")
        #expect(f.model.problemsByUnit(f.course).units.map(\.title) == ["그래프"])
        #expect(f.model.linkedTitles(set.problems[0], units: f.course.outline.map(\.unit)) == "그래프")
    }

    @Test func removingACardReloadsTheList() throws {
        let f = try QuizFixture()
        f.model.removingCard = f.cards[2]
        f.model.removeCard(in: f.course)
        #expect(f.model.cards.map(\.id) == [f.cards[0].id, f.cards[1].id])
        #expect(f.model.removingCard == nil)
    }
}

@MainActor
struct QuizSolveModelTests {
    @Test func wrongOnlyRoundRecordsTheVerdictWhenMovingOn() throws {
        let f = try QuizFixture()
        let solve = QuizSolveModel(quiz: f.model)
        solve.prepare(f.course)
        #expect(solve.scope.unitIds == Set(f.units))
        #expect(solve.footer(solve.pane(f.course)) == "2단원 · 모든 유형 · 3장")
        #expect(solve.pane(f.course).wrong == 1)

        solve.solveOnlyWrong(f.course)
        #expect(solve.deck.map(\.id) == [f.cards[0].id] && solve.crumb == "퀴즈 › 오답만")
        solve.answer = "내 답"
        solve.judge(.correct, on: f.cards[0])
        #expect(solve.nextTitle == "마치기")
        solve.next(f.course)
        #expect(solve.round == [.correct] && solve.current == nil)
        #expect(f.model.attempts.count == 2)
        #expect(solve.historyDetail(f.model.attempts.last!).hasSuffix(" · 직접"))
    }

    @Test func filtersAndOptionsFollowTheScope() throws {
        let f = try QuizFixture()
        let solve = QuizSolveModel(quiz: f.model)
        solve.prepare(f.course)
        solve.toggle(.theorem)
        #expect(solve.footer(solve.pane(f.course)) == "2단원 · 정리 · 1장")
        let pane = solve.pane(f.course)
        #expect(solve.allSelected(pane))
        solve.toggleAll(pane, course: f.course)
        #expect(solve.scope.unitIds.isEmpty && solve.pane(f.course).preview == 0)
        solve.missingKey = true
        #expect(solve.gradingOptions.map(\.1) == ["직접"])
        var tally = WrongTally()
        tally.items = 4
        tally.attempted = 1
        #expect(solve.unitDetail(tally) == "4장")
        #expect(solve.unitHelp(tally) == "진도 25% · 푼 카드 1 / 4")
    }
}

@MainActor
struct CardSheetModelTests {
    @Test func editorTitlesAndSaveFollowTheDraft() throws {
        let f = try QuizFixture()
        #expect(CardEditorModel(workspace: f.workspace, course: f.course, draft: CardDraft(unitId: f.units[0])).title == "카드 추가")
        let editor = CardEditorModel(workspace: f.workspace, course: f.course, draft: CardDraft(f.cards[2]))
        #expect(editor.title == "카드 편집" && editor.deleteTitle == "카드 삭제")
        editor.draft.unitId = f.units[0]
        #expect(editor.saveCard())
        f.model.load(f.course)
        #expect(f.model.cards.filter { $0.unitId == f.units[0] }.count == 3)
    }

    @Test func generatorConfirmsMakingThenSavingThePicked() throws {
        let f = try QuizFixture()
        let unit = try #require(f.course.file.units.first)
        let generate = GenerateCardsModel(workspace: f.workspace, course: f.course, unit: unit)
        #expect(generate.confirmTitle == "만들기" && generate.title == "그래프 · Claude로 카드 만들기")
        generate.candidates = [f.cards[0], f.cards[1]]
        generate.kept = Set(generate.candidates.map(\.id))
        generate.toggle(f.cards[0])
        #expect(generate.confirmTitle == "고른 1장 저장")
    }
}

@MainActor
struct RecordingPlayerModelTests {
    @Test func searchKeepsTranscriptIndicesAndMarksBookmarks() throws {
        let f = try QuizFixture()
        let recording = Recording(device: f.workspace.device, at: .now, sessionId: nil, file: "Recordings/a.m4a", bookmarks: [10])
        let model = RecordingPlayerModel(workspace: f.workspace, courseId: f.courseId, store: f.course.store, recording: recording)
        model.transcript = LectureTranscript(locale: "ko-KR", lines: [.init(start: 0, end: 5, text: "그래프 정의"),
                                                                      .init(start: 5, end: 11, text: "트리"),
                                                                      .init(start: 11, end: 20, text: "그래프 탐색")])
        #expect(model.shownLines.map(\.bookmarked) == [false, true, false])
        model.query = "그래프"
        #expect(model.shownLines.map(\.index) == [0, 2])
        #expect(model.hasLines)
    }
}
