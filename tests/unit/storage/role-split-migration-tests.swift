import FolioDomain
import Foundation
import Testing

@testable import FolioStorage

struct RoleSplitMigrationTests {
    func material(_ role: String?) -> JSONValue {
        var fields: [String: JSONValue] = ["path": .string("Exams/Past/x.pdf"), "futureMaterialField": .string("keep me")]
        if let role { fields["role"] = .string(role) }
        return .object(fields)
    }

    @Test func rolesAreRenamedAndFilesStayPut() throws {
        var raw: JSONValue = .object([
            "materials": .array([material("pastExam"), material("examPrep"), material("lecture"), material(nil)])
        ])
        try CourseFile.splitRolesByOrigin(&raw)
        guard case .array(let materials)? = raw["materials"] else { Issue.record("no materials"); return }
        #expect(materials.map { $0["role"] } == [.string("inherited"), .string("exam"), .string("lecture"), nil])
        #expect(materials.allSatisfy { $0["examIds"] == .array([]) && $0["futureMaterialField"] == .string("keep me") })

        #expect(materials.allSatisfy { $0["kind"] == nil && $0["path"] == .string("Exams/Past/x.pdf") })
    }

    // v5 전의 마이그레이션은 파일 전체를 디코딩하므로, v4 자료도 여전히 읽혀야 한다.
    @Test func aV4MaterialStillDecodes() throws {
        let json = #"""
            {"createdAt":"2026-03-02T09:00:00.000Z","id":"A0000000-0000-4000-8000-000000000001","isFolder":false,
             "path":"Exams/Past/2024 Midterm.pdf","role":"pastExam","sessionIds":[],"status":"classified","unitIds":[],
             "updatedAt":"2026-03-02T09:00:00.000Z","updatedBy":"D0000000-0000-4000-8000-000000000001"}
            """#
        let m = try JSONFormat.decoder.decode(Material.self, from: Data(json.utf8))
        #expect(m.role == .inherited && m.examIds.isEmpty)
    }
}
