import FolioDomain
import FolioFixtures
@testable import FolioStorage
import Foundation
import Testing

/// course.json v1 -> v2: sessions lose `kind` and `lab`; a lab becomes a unit the session links to.
struct SessionKindMigrationTests {
    let gist: URL
    var url: URL { gist.appending(path: "2026-3/EC4207 그래프 이론/.folio/course.json") }

    init() throws {
        gist = try Fixture.standard.copyToTemp()
        var raw = try JSONFormat.decoder.decode(JSONValue.self, from: Data(contentsOf: url))
        #expect(raw["schemaVersion"] == .number(1))
        func session(_ id: Int, week: Int, day: Int, kind: String, topic: String = "", lab: Int? = nil, index: Int = 1) -> JSONValue {
            var s: [String: JSONValue] = [
                "id": .string("5E000000-0000-4000-8000-00000000000\(id)"), "createdAt": .string("2026-09-01T00:00:00.000Z"),
                "updatedAt": .string("2026-09-01T00:00:00.000Z"), "updatedBy": .string("D0000000-0000-4000-8000-000000000001"),
                "week": .number(Double(week)), "index": .number(Double(index)), "date": .string("2026-09-\(day)T01:00:00.000Z"),
                "kind": .string(kind), "topic": .string(topic), "unitIds": .array([]), "inkIds": .array([]), "materials": .array([]),
            ]
            if let lab { s["lab"] = .number(Double(lab)) }
            return .object(s)
        }
        var cancelled = session(1, week: 2, day: 10, kind: "cancelled")
        cancelled["futureSessionField"] = .string("keep me")
        raw["sessions"] = .array([
            cancelled,
            session(2, week: 2, day: 11, kind: "recitation"),
            // v1 numbered week 5's lectures 1 and 2 around the recitation between them, which it stored as 3.
            session(7, week: 5, day: 29, kind: "lecture", index: 1),
            session(8, week: 5, day: 30, kind: "recitation", index: 3),
            session(9, week: 5, day: 31, kind: "lecture", index: 2),
            session(3, week: 3, day: 15, kind: "lab", topic: "TLC (1)", lab: 4),
            session(4, week: 3, day: 17, kind: "lab", topic: "TLC (2)", lab: 4),
            session(5, week: 4, day: 22, kind: "lab", topic: "VSEPR", index: 1),
            session(6, week: 4, day: 24, kind: "makeup", topic: "보충"),
        ])
        // Lab04 already exists as a unit, so its sessions join it instead of making another.
        raw["units"] = .array([.object([
            "id": .string("0E000000-0000-4000-8000-000000000004"), "createdAt": .string("2026-09-01T00:00:00.000Z"),
            "updatedAt": .string("2026-09-01T00:00:00.000Z"), "updatedBy": .string("D0000000-0000-4000-8000-000000000001"),
            "title": .string("Lab04 Thin-layer chromatography"), "order": .number(0), "sessionIds": .array([]), "examIds": .array([]),
        ])])
        try JSONFormat.encoder.encode(raw).write(to: url)
    }

    @Test func labsBecomeUnitsAndCancelledBecomesAFlag() throws {
        let file = try StoredDocument<CourseFile>.read(from: url).model
        let s = file.sessions
        #expect(s.map(\.isCancelled) == [true, false, false, false, false, false, false, false, false])
        #expect(s[1].topic == "리시테이션" && s[8].topic == "보충")

        let tlc = try #require(file.units.first { $0.labNumber == 4 })
        #expect(file.units.filter { $0.labNumber == 4 }.count == 1)
        #expect(tlc.sessionIds == [s[5].id, s[6].id] && s[5].unitIds == [tlc.id])
        // A lab without a number gets no unit guessed for it.
        #expect(file.units.count == 1 && s[7].unitIds.isEmpty)
        #expect(file.labWeeks == [4: 3])
        #expect(file.labNumbers["Thin-layer chromatography"] == 4)
    }

    @Test func weeksWithARecitationAreNumberedByDate() throws {
        let s = try StoredDocument<CourseFile>.read(from: url).model.sessions
        #expect(s[2...4].map(\.index) == [1, 2, 3])
        #expect(s[0].index == 1 && s[1].index == 2)
        // A week without a recitation keeps its numbers.
        #expect(s[7].index == 1)
    }

    @Test func readingTwiceMakesTheSameUnit() throws {
        let a = try StoredDocument<CourseFile>.read(from: url).model.units.map(\.id)
        let b = try StoredDocument<CourseFile>.read(from: url).model.units.map(\.id)
        #expect(a == b && a.count == 1)
    }

    @Test func savedFileDropsKindAndKeepsUnknownFields() throws {
        try StoredDocument<CourseFile>.read(from: url).write(to: url)
        let raw = try JSONFormat.decoder.decode(JSONValue.self, from: Data(contentsOf: url))
        #expect(raw["schemaVersion"] == .number(2))
        guard case .array(let sessions)? = raw["sessions"] else { Issue.record("no sessions"); return }
        #expect(sessions.allSatisfy { $0["kind"] == nil && $0["lab"] == nil })
        #expect(sessions[0]["cancelled"] == .bool(true) && sessions[1]["cancelled"] == nil)
        #expect(sessions[0]["futureSessionField"] == .string("keep me"))
    }
}
