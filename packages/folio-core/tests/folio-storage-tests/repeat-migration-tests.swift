import FolioDomain
@testable import FolioStorage
import Foundation
import Testing

/// course.json v6 -> v7: the one repeat `"weekly"` becomes a rule of interval, unit and weekdays.
struct RepeatMigrationTests {
    @Test func weeklyBecomesOneWeekAndOtherFieldsStay() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var file = CourseFile(course: Course(device: UUID(), at: .now, title: "로봇공학"))
        file.assignments = [Assignment(device: UUID(), at: .now, title: "Weekly Quiz", due: .now), Assignment(device: UUID(), at: .now, title: "HW1")]
        var raw = try JSONFormat.decoder.decode(JSONValue.self, from: JSONFormat.encoder.encode(file))
        raw["schemaVersion"] = .number(6)
        guard case .array(var assignments)? = raw["assignments"] else { Issue.record("no assignments"); return }
        assignments[0]["repeats"] = .string("weekly")
        assignments[0]["futureField"] = .string("keep me")
        raw["assignments"] = .array(assignments)
        let url = folder.appending(path: "course.json")
        try JSONFormat.encoder.encode(raw).write(to: url)

        let doc = try StoredDocument<CourseFile>.read(from: url)
        #expect(doc.model.assignments[0].repeats == .weekly)
        #expect(doc.model.assignments[1].repeats == nil)
        try doc.write(to: url)
        let written = try JSONFormat.decoder.decode(JSONValue.self, from: Data(contentsOf: url))
        guard case .array(let saved)? = written["assignments"] else { Issue.record("no assignments"); return }
        #expect(saved[0]["repeats"] == .object(["every": .number(1), "unit": .string("week"), "weekdays": .array([])]))
        #expect(saved[0]["futureField"] == .string("keep me"))
        #expect(written["schemaVersion"] == .number(Double(CourseFile.schemaVersion)))
    }

    @Test func aRuleAlreadySpelledOutIsLeftAlone() throws {
        let rule: JSONValue = .object(["every": .number(2), "unit": .string("week"), "weekdays": .array([.number(1), .number(3)]), "until": .string("x")])
        var raw: JSONValue = .object(["assignments": .array([.object(["repeats": rule])])])
        try CourseFile.spellOutRepeats(&raw)
        #expect(raw == .object(["assignments": .array([.object(["repeats": rule])])]))
    }
}
