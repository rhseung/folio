import FolioDomain
import Foundation
import Testing

struct MaterialLinkTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)

    func file() -> CourseFile {
        var file = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        file.materials = [Material(device: device, at: now, path: "Lectures/05_Matchings.pdf", role: .lecture, status: .classified)]
        file.sessions = [2, 1].map { Session(device: device, at: now, week: $0, index: 1, date: now) }
        file.units = [Unit(device: device, at: now, title: "Matchings", order: 1)]
        return file
    }

    @Test func linksSurviveEncodingAndDecoding() throws {
        var f = file()
        let m = f.materials[0].id
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 3, lastPage: 10)
        f.linkMaterial(m, session: f.sessions[1].id)
        f.linkMaterial(m, session: f.sessions[0].id, firstPage: 4, lastPage: 12)  // updates, doesn't duplicate
        f.setMaterial(m, unit: f.units[0].id, linked: true)

        let decoded = try JSONDecoder().decode(CourseFile.self, from: JSONEncoder().encode(f))
        #expect(decoded == f)
        let links = decoded.sessionLinks(of: m)
        #expect(links.map(\.session.week) == [1, 2])
        #expect(links.map(\.link.firstPage) == [nil, 4] && links.map(\.link.lastPage) == [nil, 12])
        #expect(Set(decoded.materials[0].sessionIds) == Set(f.sessions.map(\.id)))
        #expect(decoded.materials[0].unitIds == [f.units[0].id])

        f.unlinkMaterial(m, session: f.sessions[0].id)
        f.setMaterial(m, unit: f.units[0].id, linked: false)
        #expect(f.sessionLinks(of: m).map(\.session.week) == [1])
        #expect(f.materials[0].sessionIds == [f.sessions[1].id] && f.materials[0].unitIds.isEmpty)
    }

    @Test func relinkAdoptsTheDuplicateAndKeepsTheOriginalID() {
        var f = file()
        let original = f.materials[0].id
        f.linkMaterial(original, session: f.sessions[0].id, firstPage: 1, lastPage: 5)
        f.materials[0].status = .missing
        let dup = Material(device: device, at: now, path: "Lectures/05_Matchings v2.pdf", role: .lecture, status: .classified)
        f.materials.append(dup)
        f.linkMaterial(dup.id, session: f.sessions[1].id)
        f.course.syllabusMaterialId = dup.id

        f.relinkMaterial(original, to: dup.path, hash: "h", size: 7, bookmark: nil, device: device, now: now)

        #expect(f.materials.map(\.id) == [original])
        #expect(f.materials[0].path == dup.path && f.materials[0].status == .classified && f.materials[0].hash == "h")
        #expect(f.sessionLinks(of: original).count == 2 && f.course.syllabusMaterialId == original)
    }
}
