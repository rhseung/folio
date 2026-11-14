import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import Folio

@MainActor
struct PageStripModelTests {
    let workspace: Workspace
    let earlier: UUID
    let session: UUID
    let upcoming: UUID
    let slides: FolioDomain.Material

    init() throws {
        workspace = try fixtureWorkspace()
        // 실제 시계에서 한 시간 전은 새벽 4시와 5시 사이(공부일 경계)에 전날이 되어, 오늘 수업이 오늘 것이 아니게 된다. 오후로 고정하면 한 시간 전의 수업이 같은 공부일에 남는다.
        let now = workspace.calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 14))!
        workspace.pinnedNow = now
        workspace.run(MaterialTrack(course: graphTheory))
        earlier = try #require(workspace.run(SessionAdd(course: graphTheory, date: now.addingTimeInterval(-7 * 86_400)))?.made)
        session = try #require(workspace.run(SessionAdd(course: graphTheory, date: now.addingTimeInterval(-3_600)))?.made)
        upcoming = try #require(workspace.run(SessionAdd(course: graphTheory, date: now.addingTimeInterval(7 * 86_400)))?.made)
        slides = try #require(workspace.course(graphTheory)?.file.materials.first { $0.path == "Lectures/05_Matchings.pdf" })
    }

    var file: CourseFile { workspace.course(graphTheory)!.file }
    func links(_ id: UUID) -> [SessionMaterial] { file.sessions.first { $0.id == id }?.materials ?? [] }
    func model(_ material: UUID? = nil, defaults: UserDefaults? = nil) -> PageStripModel {
        PageStripModel(workspace: workspace, course: graphTheory, material: material ?? slides.id, pageCount: 24, defaults: defaults)
    }
    func link(_ session: UUID, _ pages: ClosedRange<Int>) {
        workspace.run(
            MaterialLinkSession(
                course: graphTheory, material: slides.id, session: session, firstPage: pages.lowerBound, lastPage: pages.upperBound))
    }
    // 열을 위에서 아래로 적는다. `h`는 머리(`H`는 펼친 머리), `e`는 편집 행, `d`는 초안 행이고, 나머지는 쪽이다. `|`는 구획 색이 칠해진 쪽, `*`는 고른 쪽을 나타내며, 쪽 아래의
    // 초안 행은 ` /d`와 그 범위로 적는다.
    func column(_ model: PageStripModel) -> [String] {
        model.items.map { item in
            let lead: String =
                switch item.lead {
                case .header(let s, let open)?: (open ? "H" : "h") + s.label
                case .edit(let s)?: "e" + s.label
                case .draft(let pages)?: "d" + Session.pagesLabel(pages)
                case nil: ""
                }
            let mark =
                switch item.mark {
                case .plain: ""
                case .tinted: "|"
                case .picked: "*"
                }
            let trail: String = if case .draft(let pages)? = item.trail { " /d" + Session.pagesLabel(pages) } else { "" }
            return lead + (item.page.map { " \($0)\(mark)" } ?? "") + trail
        }
    }

    @Test func eachClassIsASectionUnderItsHeader() {
        link(earlier, 1...7)
        link(session, 9...30)
        let model = model()
        #expect(model.sections.map(\.id) == [earlier, session] && model.sections.map(\.pages) == [1...7, 9...24])
        let day = file.day(of: file.sessions.first { $0.id == earlier }!, calendar: workspace.calendar)
        #expect(model.sections[0].title == day && model.sections[0].label == "1–7쪽")
        let column = column(model)
        #expect(Array(column.prefix(2)) == ["H1–7쪽 1|", " 2|"] && column[6] == " 7|" && column[7] == " 8")
        #expect(column[8] == "H9–24쪽 9|" && column.count == 24)
    }

    @Test func earlierSectionsFoldAndAFoldIsKept() throws {
        let third = try #require(workspace.run(SessionAdd(course: graphTheory, date: workspace.now.addingTimeInterval(-3 * 86_400)))?.made)
        link(earlier, 1...4)
        link(third, 5...8)
        link(session, 9...10)
        let defaults = try #require(UserDefaults(suiteName: "PageStripModelTests.\(UUID())"))
        let model = model(defaults: defaults)
        #expect(Array(column(model).prefix(3)) == ["h1–4쪽", "H5–8쪽 5|", " 6|"])
        #expect(model.itemID(showing: 3) == .folded(earlier) && model.itemID(showing: 6) == .page(6))
        model.toggle(model.sections[0])
        model.toggle(model.sections[2])
        #expect(model.isOpen(model.sections[0]) && !model.isOpen(model.sections[2]))
        let again = self.model(defaults: defaults)
        #expect(again.isOpen(again.sections[0]) && again.isOpen(again.sections[1]) && !again.isOpen(again.sections[2]))
        #expect(column(again)[8] == "h9–10쪽" && column(again)[9] == " 11")
    }

    @Test func onlyALectureFileHasProgress() throws {
        link(earlier, 1...7)
        let other = try #require(file.materials.first { $0.role != .lecture && !$0.isFolder })
        let model = model(other.id)
        #expect(!model.isLecture && model.sections.isEmpty)
        model.extend(to: 4)
        model.start(at: 2)
        #expect(model.selection == nil && model.items.map(\.page) == Array(1...24))
        #expect(!PageStripModel(workspace: workspace, course: nil, material: nil, pageCount: 3, defaults: nil).isLecture)
    }

    @Test func aPressThenAShiftPressPicksTheRange() {
        let model = model()
        model.press(9)
        #expect(model.selection == nil)
        model.extend(to: 4)
        #expect(model.selection == 4...9 && model.selectionLabel == "4–9쪽")
        #expect(Array(column(model)[3...4]) == ["d4–9쪽 4*", " 5*"] && column(model)[9] == " 10")
        model.extend(to: 12)
        #expect(model.selection == 9...12)
        model.press(3)
        #expect(model.selection == nil && model.anchor == 3)
        model.extend(to: 3)
        #expect(model.selectionLabel == "3쪽")
        let fresh = self.model()
        fresh.extend(to: 6)
        #expect(fresh.selection == 6...6)
    }

    @Test func theDraftRowFollowsThePickedEnd() {
        let model = model()
        model.press(4)
        model.extend(to: 9)
        #expect(model.selection == 4...9 && model.draftBelow && model.draftItemID == .page(9))
        let down = column(model)
        #expect(down[3] == " 4*" && down[8] == " 9* /d4–9쪽" && down[9] == " 10")
        model.extend(to: 2)
        #expect(model.selection == 2...4 && !model.draftBelow && model.draftItemID == .page(2))
        let up = column(model)
        #expect(up[1] == "d2–4쪽 2*" && up[3] == " 4*")
        model.extend(to: 4)
        #expect(model.selection == 4...4 && !model.draftBelow && column(model)[3] == "d4쪽 4*")
        model.start(at: 12)
        #expect(!model.draftBelow && model.draftItemID == .page(12))
        model.extend(to: 15)
        #expect(model.draftBelow && column(model)[14] == " 15* /d12–15쪽")
        model.clear()
        #expect(model.draftItemID == nil)
    }

    @Test func theEditRowStaysInTheHeadersPlace() {
        link(session, 9...12)
        let model = model()
        model.edit(model.sections[0])
        model.extend(to: 14)
        #expect(!model.draftBelow && model.draftItemID == nil)
        #expect(column(model)[8] == "e9–14쪽 9*" && !column(model).contains { $0.contains("/d") })
    }

    @Test func aRangeStopsAtAnotherClassesPages() {
        link(earlier, 5...8)
        let model = model()
        model.press(2)
        model.extend(to: 12)
        #expect(model.selection == 2...4)
        model.press(12)
        model.extend(to: 1)
        #expect(model.selection == 9...12)
        model.press(6)
        model.extend(to: 10)
        #expect(model.selection == nil)
        model.start(at: 20)
        model.extend(to: 3)
        #expect(model.selection == 9...20)
    }

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

    @Test func theButtonStartsPickingATapBegins() {
        link(earlier, 5...8)
        let model = model()
        model.togglePicking()
        #expect(model.pickingShown && model.selection == nil)
        model.extend(to: 12)
        #expect(model.selection == 12...12 && model.editing == nil)
        model.extend(to: 14)
        #expect(model.selection == 12...14)
        model.togglePicking()
        #expect(!model.pickingShown && model.selection == nil)
        model.togglePicking()
        model.extend(to: 6)
        #expect(model.editing == earlier && model.selection == 5...8)
    }

    @Test func savingWritesTheRangeToTheChosenClass() {
        let model = model()
        #expect(!model.canSave)
        model.press(9)
        model.extend(to: 12)
        #expect(model.chosen == session && model.choices.map(\.id) == [session, earlier])
        #expect(model.choices[0].today && !model.choices[1].today && model.onlyToday == nil)
        #expect(model.canSave && model.refusal == nil)
        model.commit()
        #expect(links(session) == [SessionMaterial(materialId: slides.id, firstPage: 9, lastPage: 12)])
        #expect(model.selection == nil && !model.choosing && model.fresh == session)
        #expect(model.sections.map(\.pages) == [9...12] && column(model)[8] == "H9–12쪽 9|")
        #expect(links(upcoming).isEmpty)
        #expect(model.choices.map(\.id) == [earlier])
        link(earlier, 1...4)
        model.press(14)
        model.extend(to: 16)
        #expect(model.choices.isEmpty && model.chosen == nil && !model.canSave)
    }

    @Test func todaysClassAloneIsOfferedWithoutAMenu() {
        link(earlier, 1...4)
        let model = model()
        model.start(at: 5)
        #expect(model.onlyToday?.id == session && model.chosen == session)
    }

    @Test func aHeaderChangesItsClassesRange() {
        link(earlier, 1...4)
        link(session, 9...12)
        let model = model()
        model.edit(model.sections[1])
        #expect(column(model)[5] == " 6" && column(model)[8] == "e9–12쪽 9*" && !model.canSave)
        model.extend(to: 14)
        #expect(model.selection == 9...14 && model.canSave)
        model.extend(to: 2)
        #expect(model.selection == 5...14)
        #expect(column(model)[4] == "e5–14쪽 5*")
        model.commit()
        #expect(links(session) == [SessionMaterial(materialId: slides.id, firstPage: 5, lastPage: 14)])
        #expect(model.editing == nil && model.sections.map(\.pages) == [1...4, 5...14])
        model.start(at: 2)
        #expect(model.editing == earlier && model.selection == 1...4)
    }

    @Test func aSectionsProgressIsRemoved() throws {
        link(earlier, 1...4)
        link(session, 9...12)
        let defaults = try #require(UserDefaults(suiteName: "PageStripModelTests.\(UUID())"))
        let model = model(defaults: defaults)
        #expect(!model.canRemove)
        model.toggle(model.sections[1])
        model.edit(model.sections[1])
        #expect(model.canRemove)
        model.remove()
        #expect(links(session).isEmpty && model.editing == nil && model.selection == nil && !model.canRemove)
        #expect(model.sections.map(\.id) == [earlier] && column(model)[8] == " 9")
        #expect((defaults.dictionary(forKey: PageStripModel.key(slides.id)) as? [String: Bool])?[session.uuidString] == nil)
        #expect(model.choices.map(\.id) == [session])
        model.remove(model.sections[0])
        #expect(links(earlier).isEmpty && model.sections.isEmpty)
        #expect(links(upcoming).isEmpty)
    }

    @Test func removingFromAMenuKeepsOtherWork() {
        link(earlier, 1...4)
        link(session, 9...12)
        let model = model()
        model.edit(model.sections[1])
        model.extend(to: 10)
        #expect(model.canRemove(model.sections[0]))
        model.remove(model.sections[0])
        #expect(links(earlier).isEmpty && model.editing == session && model.selection == 9...10)
        model.clear()
        model.press(15)
        model.extend(to: 17)
        model.remove(model.sections[0])
        #expect(links(session).isEmpty && model.selection == 15...17)
    }

    @Test func anOverlappingSaveIsRefused() {
        link(earlier, 1...7)
        let refusal = workspace.refusal(
            MaterialLinkSession(course: graphTheory, material: slides.id, session: session, firstPage: 5, lastPage: 9))
        #expect(refusal?.contains("1–7쪽") == true)
    }

    @Test func aCancelledClassIsNotOffered() {
        workspace.run(SessionSet(course: graphTheory, session: earlier, kind: .set(.cancelled)))
        #expect(model().choices.map(\.id) == [session])
    }
}
