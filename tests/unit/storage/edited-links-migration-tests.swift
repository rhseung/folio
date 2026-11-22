import FolioCore
import FolioDomain
import FolioFixtures
import Foundation
import Testing

@testable import FolioStorage

// 예전 파일은 회차의 단원과 시험 범위를 통째로 적었다. 읽은 뒤에도 화면에 보이는 연결이 같아야 하고, 저장하는
// 것은 계산값과의 차이뿐이어야 한다.
struct EditedLinksMigrationTests {
    let gist: URL
    var url: URL { gist.appending(path: "2026-3/EC4207 그래프 이론/.folio/course.json") }
    let units: [UUID]
    let sessions: [UUID]
    let exam: UUID

    // 렉처 하나(쪽 1~30)를 10쪽씩 단원 셋으로 나눈다. 첫 수업은 1~15쪽, 둘째 수업은 16~30쪽을 배웠고 그 뒤에
    // 중간고사가 있다. 계산값은 첫 수업 [단원 1, 2], 둘째 수업 [단원 2, 3]이다.
    init() throws {
        gist = try Fixture.standard.copyToTemp()
        let url = gist.appending(path: "2026-3/EC4207 그래프 이론/.folio/course.json")
        let (device, start, day) = (UUID(), Date(timeIntervalSince1970: 1_788_000_000), 86_400.0)
        var file = try StoredDocument<CourseFile>.read(from: url).model
        let lecture = Material(device: device, at: start, path: "Lectures/05_Matchings.pdf", role: .lecture, status: .classified)
        file.materials.append(lecture)
        file.units = (0..<3).map { i in
            var u = Unit(device: device, at: start, title: "단원 \(i + 1)", order: i + 1)
            u.lecturePages = [UnitPages(materialId: lecture.id, firstPage: i * 10 + 1, lastPage: i * 10 + 10)]
            return u
        }
        file.sessions = (0..<2).map { Session(device: device, at: start, week: $0 + 1, date: start + Double($0) * 7 * day) }
        file.linkMaterial(lecture.id, session: file.sessions[0].id, firstPage: 1, lastPage: 15)
        file.linkMaterial(lecture.id, session: file.sessions[1].id, firstPage: 16, lastPage: 30)
        file.exams = [Exam(device: device, at: start, title: "중간고사", start: start + 10 * day)]
        units = file.units.map(\.id)
        sessions = file.sessions.map(\.id)
        exam = file.exams[0].id

        var raw = try JSONFormat.decoder.decode(JSONValue.self, from: JSONFormat.encoder.encode(file))
        raw["schemaVersion"] = .number(7)
        let list = { (ids: [UUID]) in JSONValue.array(ids.map { .string($0.uuidString) }) }
        // 첫 수업은 단원 2를 빼고 단원 3을 더한 모양이다. 단원 3은 단원 쪽(`sessionIds`)에만 적혀 있다.
        guard case .array(var s)? = raw["sessions"], case .array(var u)? = raw["units"], case .array(var e)? = raw["exams"] else {
            throw CancellationError()
        }
        s[0]["unitIds"] = list([units[0]])
        s[0]["futureSessionField"] = .string("keep me")
        s[1]["unitIds"] = list([units[1], units[2]])
        u[0]["sessionIds"] = list([sessions[0]])
        u[2]["sessionIds"] = list([sessions[0], sessions[1]])
        // 시험 범위는 단원 1만 적었고, 단원 2는 단원 쪽(`examIds`)에만 적혀 있다.
        e[0]["scopeUnitIds"] = list([units[0]])
        u[1]["examIds"] = list([exam])
        raw["sessions"] = .array(s)
        raw["units"] = .array(u)
        raw["exams"] = .array(e)
        try JSONFormat.encoder.encode(raw).write(to: url)
    }

    @Test func storedLinksStayVisibleAsDifferences() throws {
        let file = try StoredDocument<CourseFile>.read(from: url).model
        let first = try #require(file.sessions.first { $0.id == sessions[0] })
        let second = try #require(file.sessions.first { $0.id == sessions[1] })
        #expect(file.unitIds(of: first) == [units[0], units[2]])
        #expect(first.addedUnitIds == [units[2]] && first.removedUnitIds == [units[1]])
        #expect(file.unitIds(of: second) == [units[1], units[2]])
        #expect(second.addedUnitIds.isEmpty && second.removedUnitIds.isEmpty)

        // 계산한 범위는 두 수업의 단원 [1, 2, 3]이므로, 적어 둔 [1, 2]는 단원 3을 뺀 것이다.
        let midterm = try #require(file.exams.first { $0.id == exam })
        #expect(file.computedScope(of: midterm) == units)
        #expect(file.scope(of: midterm) == [units[0], units[1]])
        #expect(midterm.addedScopeUnitIds.isEmpty && midterm.removedScopeUnitIds == [units[2]])
    }

    @Test func writingDropsTheOldKeysAndKeepsUnknownOnes() throws {
        try StoredDocument<CourseFile>.read(from: url).write(to: url)
        let raw = try JSONFormat.decoder.decode(JSONValue.self, from: Data(contentsOf: url))
        #expect(raw["schemaVersion"] == .number(Double(CourseFile.schemaVersion)))
        guard case .array(let s)? = raw["sessions"], case .array(let u)? = raw["units"], case .array(let e)? = raw["exams"] else {
            Issue.record("no sessions, units or exams")
            return
        }
        #expect(s.allSatisfy { $0["unitIds"] == nil } && e.allSatisfy { $0["scopeUnitIds"] == nil })
        #expect(u.allSatisfy { $0["sessionIds"] == nil && $0["examIds"] == nil })
        #expect(s[0]["futureSessionField"] == .string("keep me"))

        // 두 번 읽어도 차이가 더 생기지 않는다.
        let again = try StoredDocument<CourseFile>.read(from: url).model
        #expect(again.unitIds(of: again.sessions[0]) == [units[0], units[2]])
        #expect(again.scope(of: again.exams[0]) == [units[0], units[1]])
    }
}
