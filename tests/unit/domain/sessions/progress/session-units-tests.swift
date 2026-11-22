import FolioDomain
import Foundation
import PropertyBased
import Testing

struct SessionUnitsTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_793_149_200)
    let day: TimeInterval = 86_400

    // 렉처 하나(쪽 1~30)를 단원 셋으로 나눈 과목: 매칭 1~10, 흐름 10~20(첫 쪽이 매칭의 끝 쪽과 같다), 절단 21~30.
    func course() -> CourseFile {
        var f = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        f.materials = [Material(device: device, at: now, path: "Lectures/05_Matchings.pdf", role: .lecture, status: .classified)]
        let pages = [(1, 10), (10, 20), (21, 30)]
        f.units = ["매칭", "흐름", "절단"].enumerated().map { i, title in
            var u = Unit(device: device, at: now, title: title, order: i + 1)
            u.lecturePages = [UnitPages(materialId: f.materials[0].id, firstPage: pages[i].0, lastPage: pages[i].1)]
            return u
        }
        f.sessions = (0..<4).map { Session(device: device, at: now, week: 9 + $0, date: now + Double($0) * 7 * day) }
        return f
    }

    var lecture: (CourseFile) -> UUID { { $0.materials[0].id } }

    @Test func unitsComeFromTheProgressPages() {
        var f = course()
        f.linkMaterial(lecture(f), session: f.sessions[0].id, firstPage: 1, lastPage: 15)
        #expect(f.unitIds(of: f.sessions[0]) == [f.units[0].id, f.units[1].id])
        #expect(f.sessions(of: f.units[1].id).map(\.id) == [f.sessions[0].id])
    }

    @Test func oneSharedBorderPageDoesNotCount() {
        var f = course()
        // 10쪽은 매칭의 끝이자 흐름의 첫 쪽이다. 1~10을 배운 수업은 흐름을 배우지 않았다.
        f.linkMaterial(lecture(f), session: f.sessions[0].id, firstPage: 1, lastPage: 10)
        #expect(f.unitIds(of: f.sessions[0]) == [f.units[0].id])
        // 20~25는 흐름과 20쪽 하나만 겹친다.
        f.linkMaterial(lecture(f), session: f.sessions[1].id, firstPage: 20, lastPage: 25)
        #expect(f.unitIds(of: f.sessions[1]) == [f.units[2].id])
    }

    @Test func aOnePageUnitOrAOnePageClassCounts() {
        var f = course()
        f.units[2].lecturePages[0] = UnitPages(materialId: lecture(f), firstPage: 21, lastPage: 21)
        f.linkMaterial(lecture(f), session: f.sessions[0].id, firstPage: 21, lastPage: 24)
        f.linkMaterial(lecture(f), session: f.sessions[1].id, firstPage: 10, lastPage: 10)
        #expect(f.unitIds(of: f.sessions[0]) == [f.units[2].id])
        #expect(f.unitIds(of: f.sessions[1]) == [f.units[0].id, f.units[1].id])
    }

    @Test func aClassWithoutPagesOrACancelledClassHasNoComputedUnit() {
        var f = course()
        f.linkMaterial(lecture(f), session: f.sessions[0].id)
        f.sessions[1].isCancelled = true
        f.linkMaterial(lecture(f), session: f.sessions[1].id, firstPage: 1, lastPage: 30)
        #expect(f.computedUnitIds(of: f.sessions[0]).isEmpty)
        #expect(f.computedUnitIds(of: f.sessions[1]).isEmpty)
    }

    @Test func handPickedUnitsStoreOnlyTheDifference() {
        var f = course()
        f.linkMaterial(lecture(f), session: f.sessions[0].id, firstPage: 1, lastPage: 15)
        f.setUnits([f.units[1].id, f.units[2].id], session: f.sessions[0].id)
        #expect(f.sessions[0].addedUnitIds == [f.units[2].id] && f.sessions[0].removedUnitIds == [f.units[0].id])
        #expect(f.unitIds(of: f.sessions[0]) == [f.units[1].id, f.units[2].id])

        f.setUnits([f.units[0].id, f.units[1].id], session: f.sessions[0].id)
        #expect(f.sessions[0].addedUnitIds.isEmpty && f.sessions[0].removedUnitIds.isEmpty)
    }

    @Test func changingAUnitRangeMovesTheUnitsNobodyTouched() {
        var f = course()
        f.linkMaterial(lecture(f), session: f.sessions[0].id, firstPage: 1, lastPage: 15)
        f.toggle(session: f.sessions[0].id, unit: f.units[2].id)
        // 흐름을 16쪽부터로 고치면 이 수업은 흐름을 배우지 않은 것이 되지만, 손으로 더한 절단은 남는다.
        f.units[1].lecturePages[0].firstPage = 16
        #expect(f.unitIds(of: f.sessions[0]) == [f.units[0].id, f.units[2].id])
    }

    @Test func computedUnitsFollowTheirInputs() async {
        await propertyCheck(input: Gen.int(in: 1...30), Gen.int(in: 0...10), Gen.int(in: 1...30)) { first, length, split in
            var f = course()
            let last = min(first + length, 30)
            f.linkMaterial(lecture(f), session: f.sessions[0].id, firstPage: first, lastPage: last)
            f.units[0].lecturePages[0].lastPage = split
            f.units[1].lecturePages[0].firstPage = split
            let expected = f.units.filter { u in
                let p = u.lecturePages[0].pages
                let (lo, hi) = (max(first, p.lowerBound), min(last, p.upperBound))
                return hi >= lo && (hi > lo || p.count == 1 || first == last)
            }.map(\.id)
            #expect(f.computedUnitIds(of: f.sessions[0]) == expected)
            // 고른 단원을 계산값과 같게 두면 아무것도 저장하지 않는다.
            f.setUnits(expected, session: f.sessions[0].id)
            #expect(f.sessions[0].addedUnitIds.isEmpty && f.sessions[0].removedUnitIds.isEmpty)
        }
    }

    // 노트의 단원은 노트가 가리키는 회차들이 배운 단원을 단원 순서대로 모은 것이다. 노트 메타는 회차마다 단원을 한 번만
    // 구하므로, 단원마다 모든 회차를 다시 보는 정의와 같은 답을 내는지 본다.
    @Test func reviewNoteUnitsAreTheUnionOfItsClasses() async {
        await propertyCheck(input: Gen.int(in: 1...30), Gen.int(in: 1...30), Gen.int(in: 0...2), Gen.int(in: 0...2)) {
            a, b, added, removed in
            var f = course()
            let note = UUID()
            f.notes = [NoteEntry(id: note, device: device, at: now, path: "Notes/복습.md", meta: NoteMeta(id: note, kind: .review))]
            f.linkMaterial(lecture(f), session: f.sessions[0].id, firstPage: min(a, b), lastPage: max(a, b))
            f.linkMaterial(lecture(f), session: f.sessions[1].id, firstPage: b, lastPage: 30)
            f.sessions[0].addedUnitIds = [f.units[added].id]
            f.sessions[1].removedUnitIds = [f.units[removed].id]
            f.linkNote(note, to: f.sessions[0].id, as: .review)
            f.linkNote(note, to: f.sessions[1].id, as: .review)
            let linked = f.sessions(pointingAt: note)
            let expected = UnitTree.outline(f.units).map(\.unit.id).filter { u in linked.contains { f.unitIds(of: $0).contains(u) } }
            #expect(f.meta(of: f.notes[0]).unitIds == expected)
            #expect(f.units.map(\.id).filter { f.sessions(of: $0).contains { $0.id == f.sessions[0].id } } == f.unitIds(of: f.sessions[0]))
        }
    }
}
