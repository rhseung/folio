import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing
@testable import Folio

/// Graph theory's matchings slides with two classes a week apart and one still to come.
@MainActor
struct PageStripModelTests {
    let workspace: Workspace
    let earlier: UUID
    let session: UUID
    let upcoming: UUID
    let slides: FolioDomain.Material

    init() throws {
        workspace = try fixtureWorkspace()
        workspace.run(MaterialTrack(course: graphTheory))
        earlier = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(-7 * 86_400)))?.made)
        session = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(-3_600)))?.made)
        upcoming = try #require(workspace.run(SessionAdd(course: graphTheory, date: .now.addingTimeInterval(7 * 86_400)))?.made)
        slides = try #require(workspace.course(graphTheory)?.file.materials.first { $0.path == "Lectures/05_Matchings.pdf" })
    }

    var file: CourseFile { workspace.course(graphTheory)!.file }
    func links(_ id: UUID) -> [SessionMaterial] { file.sessions.first { $0.id == id }?.materials ?? [] }
    func model(_ material: UUID? = nil) -> PageStripModel {
        PageStripModel(workspace: workspace, course: graphTheory, material: material ?? slides.id, pageCount: 24)
    }

    @Test func eachClassIsABracketAndOverlapsTakeAnotherLane() {
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: earlier, firstPage: 1, lastPage: 7))
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: session, firstPage: 5, lastPage: 30))
        let model = model()
        #expect(model.brackets.map(\.session) == [earlier, session])
        // Cut at the file's last page, as its progress is.
        #expect(model.brackets.map(\.pages) == [1...7, 5...24])
        #expect(model.brackets.map(\.lane) == [0, 1] && model.lanes == 2)
        let day = file.day(of: file.sessions.first { $0.id == earlier }!, calendar: workspace.calendar)
        #expect(model.brackets[0].day == day && model.brackets[0].link == AppLink(.session, earlier))
    }

    @Test func onlyALectureFileHasProgress() throws {
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: earlier, firstPage: 1, lastPage: 7))
        let other = try #require(file.materials.first { $0.role != .lecture && !$0.isFolder })
        let model = model(other.id)
        #expect(!model.picks && model.brackets.isEmpty && model.lanes == 0)
        model.extend(to: 4)
        model.start(at: 2)
        #expect(model.selection == nil)
        // A file no course tracks has none either.
        #expect(!PageStripModel(workspace: workspace, course: nil, material: nil, pageCount: 3).picks)
    }

    /// Pressed, then ⇧-pressed before it: the range runs either way round and reads as pages.
    @Test func aPressThenAShiftPressPicksTheRange() {
        let model = model()
        model.press(9)
        #expect(model.selection == nil)
        model.extend(to: 4)
        #expect(model.selection == 4...9 && model.selectionLabel == "4–9쪽")
        model.extend(to: 12)
        #expect(model.selection == 9...12)
        // A plain press lets the range go and starts the next one there.
        model.press(3)
        #expect(model.selection == nil && model.anchor == 3)
        model.extend(to: 3)
        #expect(model.selectionLabel == "3쪽")
        // ⇧ with nothing pressed before starts and ends at that page.
        let fresh = self.model()
        fresh.extend(to: 6)
        #expect(fresh.selection == 6...6)
    }

    /// iPad: a long press starts a one-page range, and the next tap moves its end.
    @Test func aLongPressStartsARangeATapWidens() {
        let model = model()
        model.start(at: 10)
        #expect(model.selection == 10...10)
        model.extend(to: 14)
        #expect(model.selection == 10...14)
        model.extend(to: 8)
        #expect(model.selection == 8...10)
        model.clear()
        #expect(model.selection == nil)
    }

    /// The popover offers the classes held so far, latest first, and starts on the last one. Saving writes the range
    /// as the class's pages of the file and lets the range go.
    @Test func savingWritesTheRangeToTheChosenClass() {
        let model = model()
        #expect(!model.canSave)
        model.choose()
        #expect(!model.choosing)
        model.press(9)
        model.extend(to: 12)
        model.choose()
        #expect(model.choosing && model.chosen == session)
        #expect(model.choices.map(\.id) == [session, earlier])
        #expect(model.canSave && model.refusal == nil && model.replaces == nil)
        model.commit()
        #expect(links(session) == [SessionMaterial(materialId: slides.id, firstPage: 9, lastPage: 12)])
        #expect(model.selection == nil && !model.choosing)
        #expect(model.brackets.map(\.pages) == [9...12])
        #expect(links(upcoming).isEmpty)
    }

    /// A class that already names other pages of the file says they are replaced; the same pages say nothing.
    @Test func replacingAClassesPagesIsSaid() {
        workspace.run(MaterialLinkSession(course: graphTheory, material: slides.id, session: earlier, firstPage: 1, lastPage: 7))
        let model = model()
        model.press(5)
        model.extend(to: 9)
        model.choose()
        model.chosen = earlier
        #expect(model.choices.first { $0.id == earlier }?.pages == "1–7쪽")
        #expect(model.replaces == "이 수업에 적어 둔 1–7쪽을 바꿉니다")
        model.press(1)
        model.extend(to: 7)
        model.chosen = earlier
        #expect(model.replaces == nil)
        model.press(5)
        model.extend(to: 9)
        model.chosen = earlier
        model.commit()
        #expect(links(earlier) == [SessionMaterial(materialId: slides.id, firstPage: 5, lastPage: 9)])
    }

    /// A cancelled class taught nothing and isn't offered.
    @Test func aCancelledClassIsNotOffered() {
        workspace.run(SessionSet(course: graphTheory, session: earlier, kind: .set(.cancelled)))
        #expect(model().choices.map(\.id) == [session])
    }
}
