import FolioActions
import FolioDomain
import Foundation
import Testing

@testable import Folio

@MainActor
struct WorkspaceRevisionTests {
    @Test func aSessionsRoughNoteBumpsTheNoteRevision() throws {
        let workspace = try fixtureWorkspace()
        let session = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now))?.made)
        let revision = workspace.notesRevision
        #expect(workspace.note(.rough, of: session, in: graphTheory) != nil)
        #expect(workspace.notesRevision > revision)

        let after = workspace.notesRevision
        _ = workspace.note(.rough, of: session, in: graphTheory)
        #expect(workspace.notesRevision == after)
    }

    @Test func savingOrFlippingACardBumpsOnlyTheStudyRevision() throws {
        let workspace = try fixtureWorkspace()
        let unit = UUID()
        workspace.run(UnitAdd(id: unit, course: graphTheory, title: "그래프"))
        let (notes, study) = (workspace.notesRevision, workspace.studyRevision)
        let card = StudyCard(device: workspace.device, at: .now, unitId: unit, front: "p", back: "a")
        workspace.run(CardSave(course: graphTheory, cards: [card], movedFrom: nil))
        #expect(workspace.studyRevision == study + 1 && workspace.notesRevision == notes)

        workspace.run(CardFlip(course: graphTheory, unit: unit, card: card.id, known: false))
        #expect(workspace.studyRevision == study + 2)
    }

    @Test func aWriteThatTouchesNeitherLeavesBothAlone() throws {
        let workspace = try fixtureWorkspace()
        let (notes, study) = (workspace.notesRevision, workspace.studyRevision)
        workspace.run(ExamAdd(course: graphTheory, title: "중간고사"))
        #expect(workspace.notesRevision == notes && workspace.studyRevision == study)
    }

    @Test func aReloadBumpsBoth() throws {
        let workspace = try fixtureWorkspace()
        let (notes, study) = (workspace.notesRevision, workspace.studyRevision)
        workspace.reload()
        #expect(workspace.notesRevision > notes && workspace.studyRevision > study)
    }
}
