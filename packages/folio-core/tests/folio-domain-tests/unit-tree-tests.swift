import FolioDomain
import Foundation
import Testing

typealias Unit = FolioDomain.Unit

struct UnitTreeTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)

    func unit(_ title: String, _ order: Int, parent: Unit? = nil) -> Unit {
        Unit(device: device, at: now, title: title, order: order, parentId: parent?.id)
    }

    func titles(_ units: [Unit]) -> [String] {
        UnitTree.outline(units).map { String(repeating: "-", count: $0.depth) + $0.unit.title }
    }

    @Test func outlineNestsChildrenUnderParentsInOrder() {
        let a = unit("A", 2), b = unit("B", 1)
        let units = [a, b, unit("A2", 2, parent: a), unit("A1", 1, parent: a)]
        #expect(titles(units) == ["B", "A", "-A1", "-A2"])
    }

    @Test func orphansAndCyclesStayVisible() {
        var x = unit("X", 1), y = unit("Y", 2)
        x.parentId = y.id
        y.parentId = x.id
        let orphan = Unit(device: device, at: now, title: "O", order: 3, parentId: UUID())
        #expect(Set(titles([x, y, orphan]).map { $0.trimmingCharacters(in: ["-"]) }) == ["X", "Y", "O"])
        #expect(titles([x, y, orphan]).first == "O")
    }

    @Test func moveSwapsWithinSiblingsOnly() {
        let a = unit("A", 1), b = unit("B", 5)
        let child = unit("C", 1, parent: a)
        var units = [a, b, child]
        #expect(UnitTree.move(b.id, by: -1, in: &units))
        #expect(titles(units) == ["B", "A", "-C"])
        #expect(units.first { $0.id == b.id }?.order == 1)
        #expect(!UnitTree.move(b.id, by: -1, in: &units))
        #expect(!UnitTree.move(child.id, by: 1, in: &units))
    }

    @Test func parentChangesRefuseCycles() {
        let a = unit("A", 1)
        let b = unit("B", 1, parent: a)
        let c = unit("C", 2)
        var units = [a, b, c]
        #expect(Set(UnitTree.parentChoices(for: a.id, in: units).map(\.title)) == ["C"])
        #expect(!UnitTree.setParent(a.id, to: b.id, in: &units))
        #expect(UnitTree.setParent(c.id, to: a.id, in: &units))
        #expect(titles(units) == ["A", "-B", "-C"])
        #expect(UnitTree.setParent(c.id, to: nil, in: &units))
        #expect(titles(units) == ["A", "-B", "C"])
    }

    @Test func removingAUnitClearsLinksAndLiftsChildren() {
        let parent = unit("P", 1)
        let removed = unit("R", 1, parent: parent)
        let child = unit("K", 1, parent: removed)
        var session = Session(device: device, at: now, week: 1, index: 1, date: now)
        var exam = Exam(device: device, at: now, kind: .midterm, title: "중간고사")
        session.unitIds = [removed.id]
        exam.scopeUnitIds = [removed.id, parent.id]
        var file = CourseFile(course: Course(device: device, at: now, title: "T"), units: [parent, removed, child], sessions: [session], exams: [exam])
        file.removeUnit(removed.id)
        #expect(titles(file.units) == ["P", "-K"])
        #expect(file.sessions[0].unitIds.isEmpty)
        #expect(file.exams[0].scopeUnitIds == [parent.id])
    }

    @Test func togglesKeepBothSidesInStep() {
        let u = unit("U", 1)
        let s = Session(device: device, at: now, week: 1, index: 1, date: now)
        let e = Exam(device: device, at: now, kind: .final, title: "기말고사")
        var file = CourseFile(course: Course(device: device, at: now, title: "T"), units: [u], sessions: [s], exams: [e])
        file.toggle(session: s.id, unit: u.id)
        file.toggle(exam: e.id, unit: u.id)
        #expect(file.units[0].sessionIds == [s.id] && file.sessions[0].unitIds == [u.id])
        #expect(file.units[0].examIds == [e.id] && file.exams[0].scopeUnitIds == [u.id])
        file.toggle(session: s.id, unit: u.id)
        file.toggle(exam: e.id, unit: u.id)
        #expect(file.units[0].sessionIds.isEmpty && file.sessions[0].unitIds.isEmpty)
        #expect(file.units[0].examIds.isEmpty && file.exams[0].scopeUnitIds.isEmpty)
    }

    @Test func anExamOnAChapterTakesItsSections() {
        let chapter = unit("2장", 2), other = unit("1장", 1)
        let a = unit("2.1", 1, parent: chapter), b = unit("2.2", 2, parent: chapter)
        let e = Exam(device: device, at: now, kind: .quiz, title: "Quiz1")
        var file = CourseFile(course: Course(device: device, at: now, title: "T"), units: [b, chapter, other, a], exams: [e])
        file.toggle(exam: e.id, unit: chapter.id)
        #expect(file.exams[0].scopeUnitIds == [chapter.id, a.id, b.id])
        #expect(file.units.filter { $0.examIds == [e.id] }.count == 3)
        file.toggle(exam: e.id, unit: chapter.id)
        #expect(file.exams[0].scopeUnitIds.isEmpty && file.units.allSatisfy(\.examIds.isEmpty))
    }
}
