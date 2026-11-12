import FolioActions
import FolioDomain
import Foundation
import Testing
@testable import Folio

/// Note and card lists read files the course document doesn't hold, so they re-read when these revisions move. Each
/// write path bumps them through the action's changes, not through the screen that ran it.
@MainActor
struct WorkspaceRevisionTests {
    @Test func aSessionsRoughNoteBumpsTheNoteRevision() throws {
        let workspace = try fixtureWorkspace()
        let session = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now))?.made)
        let revision = workspace.notesRevision
        #expect(workspace.note(.rough, of: session, in: graphTheory) != nil)
        #expect(workspace.notesRevision > revision)

        // Opening the same note again writes nothing.
        let after = workspace.notesRevision
        _ = workspace.note(.rough, of: session, in: graphTheory)
        #expect(workspace.notesRevision == after)
    }

    @Test func savingOrAnsweringACardBumpsOnlyTheQuizRevision() throws {
        let workspace = try fixtureWorkspace()
        let unit = UUID()
        workspace.run(UnitAdd(id: unit, course: graphTheory, title: "그래프"))
        let (notes, quiz) = (workspace.notesRevision, workspace.quizRevision)
        let card = QuizCard(device: workspace.device, at: .now, unitId: unit, type: .free, category: .definition, prompt: "p", answer: "a")
        workspace.run(QuizCardSave(course: graphTheory, cards: [card]))
        #expect(workspace.quizRevision == quiz + 1 && workspace.notesRevision == notes)

        workspace.run(QuizRecord(course: graphTheory, attempt: QuizAttemptEvent(cardId: card.id, verdict: .wrong, grader: .self)))
        #expect(workspace.quizRevision == quiz + 2)
    }

    @Test func aWriteThatTouchesNeitherLeavesBothAlone() throws {
        let workspace = try fixtureWorkspace()
        let (notes, quiz) = (workspace.notesRevision, workspace.quizRevision)
        workspace.run(ExamAdd(course: graphTheory, title: "중간고사"))
        #expect(workspace.notesRevision == notes && workspace.quizRevision == quiz)
    }

    /// A reload follows writes from outside the app (iCloud, the folio command), whose changes the app never sees.
    @Test func aReloadBumpsBoth() throws {
        let workspace = try fixtureWorkspace()
        let (notes, quiz) = (workspace.notesRevision, workspace.quizRevision)
        workspace.reload()
        #expect(workspace.notesRevision > notes && workspace.quizRevision > quiz)
    }
}
