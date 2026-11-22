import FolioCore
import FolioDomain
import Foundation
import Testing

@testable import FolioStorage

struct ProblemIDMigrationTests {
    let set = UUID(), unit = UUID(), exam = UUID(), item = UUID()

    var v7: JSONValue {
        .object([
            "problemSets": .array([
                .object([
                    "id": .string(set.uuidString), "title": .string("연습 1"),
                    "problems": .array([
                        .object(["number": .string("1"), "unitIds": .array([.string(unit.uuidString)]), "category": .string("proof")]),
                        .object(["number": .string("2"), "unitIds": .array([])]),
                    ]),
                ])
            ]),
            "exams": .array([
                .object([
                    "id": .string(exam.uuidString), "title": .string("기말고사"), "location": .string(""),
                    "plan": .array([
                        .object([
                            "id": .string(item.uuidString), "day": .string("2026-10-20"), "title": .string("매칭 복습"),
                            "target": .object(["kind": .string("quiz"), "id": .string(unit.uuidString)]),
                        ]),
                        .object(["id": .string(UUID().uuidString), "day": .string("2026-10-21"), "title": .string("족보")]),
                    ]),
                ])
            ]),
        ])
    }

    @Test func problemsGetStableIDsAndOldPlansStayAsEdited() throws {
        var a = v7, b = v7
        try CourseFile.identifyProblems(&a)
        try CourseFile.identifyProblems(&b)
        #expect(a["problemSets"] == b["problemSets"], "다시 읽어도 같은 id가 나와야 한다")
        guard case .array(let sets)? = a["problemSets"], case .array(let problems)? = sets[0]["problems"] else {
            Issue.record("no sets")
            return
        }
        #expect(sets[0]["source"] == .string("exercise"))
        #expect(problems[0]["id"] != problems[1]["id"] && problems[0]["category"] == .string("proof"))
        guard case .array(let exams)? = a["exams"], case .array(let plan)? = exams[0]["plan"] else {
            Issue.record("no plan")
            return
        }
        #expect(plan[0]["target"] == .object(["kind": .string("unit"), "id": .string(unit.uuidString)]))
        #expect(plan[1]["target"] == .object(["kind": .string("custom")]))
        #expect(plan.allSatisfy { $0["edited"] == .bool(true) })
    }

    @Test func theMigratedFileDecodes() throws {
        var raw = v7
        raw["schemaVersion"] = .number(7)
        raw["course"] = try JSONFormat.decoder.decode(
            JSONValue.self, from: JSONFormat.encoder.encode(Course(device: UUID(), at: .now, title: "그래프 이론")))
        if case .array(var exams)? = raw["exams"] {
            exams[0]["createdAt"] = .string("2026-10-01T00:00:00Z")
            exams[0]["updatedAt"] = .string("2026-10-01T00:00:00Z")
            exams[0]["updatedBy"] = .string(UUID().uuidString)
            exams[0]["title"] = .string("중간고사")
            exams[0]["scopeUnitIds"] = .array([])
            exams[0]["scopeText"] = .string("")
            exams[0]["allowed"] = .string("")
            exams[0]["memo"] = .string("")
            raw["exams"] = .array(exams)
        }
        if case .array(var sets)? = raw["problemSets"] {
            sets[0]["createdAt"] = .string("2026-10-01T00:00:00Z")
            sets[0]["updatedAt"] = .string("2026-10-01T00:00:00Z")
            sets[0]["updatedBy"] = .string(UUID().uuidString)
            raw["problemSets"] = .array(sets)
        }
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "course.json")
        try JSONFormat.encoder.encode(raw).write(to: url)
        let doc = try StoredDocument<CourseFile>.read(from: url)
        #expect(doc.model.problemSets[0].problems.count == 2)
        #expect(doc.model.exams[0].plan.map(\.target.kind) == [.unit, .custom])
        #expect(doc.model.exams[0].plan.allSatisfy { $0.isEdited })
    }
}
