import FolioCore
import FolioDomain
import Foundation
import Testing

@testable import FolioStorage

// v9의 계획은 범위 단원을 날에 나눈 것이다. v10은 앱이 놓은 항목을 지우고 사용자가 쓴 할 일만 남긴다.
struct PlanMigrationTests {
    let unit = UUID(), set = UUID(), written = UUID(), moved = UUID()

    func item(_ day: String, _ target: [String: JSONValue], _ extra: [String: JSONValue] = [:], id: UUID = UUID()) -> JSONValue {
        .object(["id": .string(id.uuidString), "day": .string(day), "target": .object(target)].merging(extra) { _, new in new })
    }

    var v9: JSONValue {
        let at = JSONValue.string("2026-11-01T00:00:00Z")
        return .object([
            "schemaVersion": .number(9),
            "futureSection": .object(["kept": .bool(true)]),
            "exams": .array([
                .object([
                    "id": .string(UUID().uuidString), "createdAt": at, "updatedAt": at, "updatedBy": .string(UUID().uuidString),
                    "title": .string("기말고사"), "start": .string("2026-12-14T00:00:00Z"), "location": .string(""),
                    "scopeText": .string(""), "allowed": .string(""), "memo": .string(""),
                    "planDay": .string("2026-11-22"),
                    "planBasis": .object([
                        "scope": .array([.string(unit.uuidString)]), "examDay": .string("2026-12-14"), "readyPercent": .number(80),
                        "minProblems": .number(3), "finalDays": .number(3), "dayItems": .number(2),
                    ]),
                    "futureField": .string("남긴다"),
                    "plan": .array([
                        item(
                            "2026-11-22", ["kind": .string("unit"), "id": .string(unit.uuidString)],
                            ["title": .string(""), "carried": .bool(true)]),
                        item(
                            "2026-11-23", ["kind": .string("unit"), "unitIds": .array([.string(unit.uuidString)])], ["title": .string("")]),
                        // 사용자가 날짜만 옮긴 앱의 항목은 쓴 글이 없으므로 지운다.
                        item(
                            "2026-11-24", ["kind": .string("unit"), "id": .string(unit.uuidString)],
                            ["title": .string(""), "edited": .bool(true)], id: moved),
                        item(
                            "2026-11-25", ["kind": .string("problems"), "id": .string(set.uuidString)],
                            ["title": .string("2번만 다시"), "edited": .bool(true), "note": .string("모르는 필드")], id: written),
                        item("2026-11-26", ["kind": .string("custom")], ["title": .string("교재 3장"), "edited": .bool(true)]),
                        item("2026-12-11", ["kind": .string("mixed")], ["title": .string("")]),
                        item("2026-12-12", ["kind": .string("mock")], ["title": .string("")]),
                        item("2026-12-13", ["kind": .string("wrong")], ["title": .string(""), "removed": .bool(true)]),
                    ]),
                ])
            ]),
        ])
    }

    @Test func onlyWrittenTasksSurviveAndTheOldBasisGoes() throws {
        var raw = v9
        try CourseFile.keepOnlyWrittenPlanItems(&raw)
        guard case .array(let exams)? = raw["exams"], case .array(let plan)? = exams[0]["plan"] else {
            Issue.record("no plan")
            return
        }
        #expect(plan.map { $0["title"] } == [.string("2번만 다시"), .string("교재 3장")])
        #expect(plan.allSatisfy { $0["target"] == .object(["kind": .string("custom")]) && $0["edited"] == .bool(true) })
        #expect(plan[0]["id"] == .string(written.uuidString) && plan[0]["note"] == .string("모르는 필드"))
        #expect(exams[0]["planBasis"] == nil && exams[0]["planDay"] == nil)
        #expect(exams[0]["futureField"] == .string("남긴다") && raw["futureSection"] != nil)

        var twice = raw
        try CourseFile.keepOnlyWrittenPlanItems(&twice)
        #expect(twice == raw)
    }

    @Test func aVersionNineFileOpensAndKeepsUnknownFieldsWhenSaved() throws {
        var raw = v9
        raw["course"] = try JSONFormat.decoder.decode(
            JSONValue.self, from: JSONFormat.encoder.encode(Course(device: UUID(), at: .now, title: "그래프 이론")))
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "course.json")
        try JSONFormat.encoder.encode(raw).write(to: url)

        let doc = try StoredDocument<CourseFile>.read(from: url)
        let exam = doc.model.exams[0]
        #expect(exam.plan.map(\.title) == ["2번만 다시", "교재 3장"] && exam.plan.allSatisfy { $0.target == .custom && $0.isEdited })
        #expect(exam.planBasis == nil && exam.planPeriod == nil)

        try doc.write(to: url)
        let saved = try JSONFormat.decoder.decode(JSONValue.self, from: Data(contentsOf: url))
        guard case .array(let exams)? = saved["exams"], case .array(let plan)? = exams[0]["plan"] else {
            Issue.record("no plan")
            return
        }
        #expect(saved["schemaVersion"] == .number(Double(CourseFile.schemaVersion)) && CourseFile.schemaVersion == 10)
        #expect(saved["futureSection"] != nil && exams[0]["futureField"] == .string("남긴다"))
        #expect(plan[0]["note"] == .string("모르는 필드") && exams[0]["planDay"] == nil)
    }
}
