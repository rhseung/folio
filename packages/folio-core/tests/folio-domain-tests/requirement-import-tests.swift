@testable import FolioDomain
import Foundation
import Testing

struct RequirementImportTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)

    func row(_ name: String, parent: String? = nil, min: Double? = nil, count: Int? = nil, from: String? = nil) -> RequirementSpec {
        RequirementSpec(name: name, group: "g", isMajor: false, parent: parent, minCredits: min, maxCredits: nil, minCount: count, rule: nil, renamedFrom: from)
    }

    /// Courses point at category IDs, so updating 콜로퀴움 or renaming 초과선택 must keep the ID.
    @Test func keepsIDsAddsParentsAndLeavesUnmentionedAlone() {
        let colloquium = Category(device: device, at: now, name: "콜로퀴움", group: "g", minCredits: 4)
        let extra = Category(device: device, at: now, name: "초과선택", group: "g")
        let other = Category(device: device, at: now, name: "타 전공", group: "g", parentId: extra.id)
        let r = RequirementImporter.merge([
            row("타 전공", parent: "자유선택"),  // parent comes later in the file
            row("콜로퀴움", count: 2),
            row("자유선택", min: 1, from: "초과선택"),
            row("전공학점", min: 36),
        ], into: [colloquium, extra, other, Category(device: device, at: now, name: "예체능")], device: device, now: now)

        let byName = Dictionary(uniqueKeysWithValues: r.categories.map { ($0.name, $0) })
        #expect(byName["콜로퀴움"]?.id == colloquium.id)
        #expect(byName["콜로퀴움"]?.minCredits == nil && byName["콜로퀴움"]?.minCount == 2)
        #expect(byName["자유선택"]?.id == extra.id)
        #expect(byName["타 전공"]?.parentId == extra.id)
        #expect(r.added == ["전공학점"])
        #expect(r.untouched == ["예체능"])
        #expect(Set(r.changed) == ["콜로퀴움", "자유선택"])

        let again = RequirementImporter.merge([row("타 전공", parent: "자유선택"), row("콜로퀴움", count: 2), row("자유선택", min: 1, from: "초과선택"), row("전공학점", min: 36)],
                                              into: r.categories, device: device, now: now)
        #expect(again.added.isEmpty && again.changed.isEmpty)
    }

    /// A double major's categories show only while that program is declared; their children go with them.
    @Test func programCategoriesFollowTheDeclaredPrograms() throws {
        let ec = CourseCode(device: device, at: now, prefix: "EC", department: "전기전자컴퓨터공학과", program: "학사과정", source: "")
        let ecGrad = CourseCode(device: device, at: now, prefix: "EC", department: "전기전자컴퓨터공학과", program: "대학원과정", source: "")
        let ai = CourseCode(device: device, at: now, prefix: "AI", department: "AI융합학과", program: "학사과정", source: "")
        let file = try JSONDecoder().decode(RequirementFile.self, from: Data("""
            {"admissionYear": 2025, "programs": [{"code": "EC", "kind": "major"}],
             "categories": [{"name": "교양", "group": "g", "isMajor": false},
                            {"name": "전공학점", "group": "전공", "isMajor": true, "program": "EC"},
                            {"name": "AI 복수전공", "group": "복수전공", "isMajor": false, "program": "AI"},
                            {"name": "AI 선택", "group": "복수전공", "isMajor": false, "parent": "AI 복수전공"}]}
            """.utf8))
        #expect(file.admissionYear == 2025 && file.programs?.first?.kind == .major)
        let r = RequirementImporter.merge(file.categories, into: [], codes: [ecGrad, ec, ai], device: device, now: now)
        #expect(r.categories.first { $0.name == "전공학점" }?.programId == ec.id)  // the undergraduate code, not the graduate twin

        let catalog = Catalog(codes: [ecGrad, ec, ai], categories: r.categories)
        #expect(catalog.scoped(to: [.init(codeId: ec.id, kind: .major)]).categories.map(\.name) == ["교양", "전공학점"])
        #expect(catalog.scoped(to: [.init(codeId: ec.id, kind: .major), .init(codeId: ai.id, kind: .doubleMajor)]).categories.count == 4)

        let bare = try JSONDecoder().decode(RequirementFile.self, from: Data(#"[{"name": "교양", "group": "g", "isMajor": false}]"#.utf8))
        #expect(bare.categories.count == 1 && bare.programs == nil)
    }
}

struct HandbookClassifierTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 0)

    /// 행복의 조건 is PPE in the 2026 handbook; a 2025 course is never judged by the 2026 table.
    @Test func suggestsFromTheHandbookOfTheCoursesYear() {
        let hs = CourseCode(device: device, at: now, prefix: "HS")
        let pp = CourseCode(device: device, at: now, prefix: "PP")
        let humanities = Category(device: device, at: now, name: "인문사회")
        let hus = Category(device: device, at: now, name: "HUS", parentId: humanities.id)
        let ppe = Category(device: device, at: now, name: "PPE", parentId: humanities.id)
        let science = Category(device: device, at: now, name: "기초과학")
        let catalog = Catalog(codes: [hs, pp], categories: [humanities, hus, ppe, science], handbooks: [
            Handbook(year: 2026, source: "", areas: ["HS2734": "PPE", "HS1001": "HUS", "GS2001": "인문사회"]),
        ])
        let spring = Semester(device: device, at: now, year: 2026, term: .spring)
        let older = Semester(device: device, at: now, year: 2025, term: .fall)
        func course(_ codes: [CourseCode], _ number: String, in semester: Semester, _ categories: [FolioDomain.Category] = []) -> Course {
            var c = Course(device: device, at: now, semesterId: semester.id, title: number, categoryIds: categories.map(\.id), credits: 3)
            c.codes = codes.map(\.id)
            c.number = number
            return c
        }
        let happiness = course([pp, hs], "2734-01", in: spring, [humanities, science])
        let done = course([hs], "1001", in: spring, [humanities, hus])  // already right; the extra parent is not worth a prompt
        let lastYear = course([hs], "2734", in: older)
        let s = HandbookClassifier.suggest(courses: [happiness, done, lastYear], semesters: [spring, older], catalog: catalog)
        #expect(s.count == 1)
        #expect(s.first?.code == "HS2734")
        #expect(s.first?.categoryIds == [science.id, ppe.id])  // 인문사회 is replaced, unrelated 기초과학 kept

        // The audit gathers the same suggestion with the uncategorized courses; a code can be looked up before taking it.
        let audit = RequirementAudit(courses: [happiness, done, lastYear], semesters: [spring, older], catalog: catalog)
        #expect(audit.suggestions == s && audit.unassigned.map(\.id) == [lastYear.id] && audit.overShared.isEmpty && !audit.isEmpty)
        #expect(audit.keeping([.unassigned]).suggestions.isEmpty && !audit.keeping([.unassigned]).isEmpty)
        #expect(audit.keeping([.shared, .unallowed]).isEmpty)
        #expect(HandbookClassifier.areas(of: "hs2734", catalog: catalog).map(\.area) == ["PPE"])
        #expect(HandbookClassifier.areas(of: "HS9999", catalog: catalog).isEmpty)
    }
}
