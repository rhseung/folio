import FolioDomain
import Foundation
import Testing
@testable import Folio

@MainActor
struct PeopleModelTests {
    let device = UUID()

    func catalog(_ people: [(String, PersonRole, String)]) -> Catalog {
        var c = Catalog()
        c.people = people.map { Person(device: device, at: .now, name: $0.0, email: $0.2, role: $0.1) }
        return c
    }

    @Test func groupsByRoleThenNameAndHidesEmptyRoles() throws {
        let model = PeopleModel(workspace: try fixtureWorkspace())
        let c = catalog([("하조교", .assistant, ""), ("나교수", .professor, ""), ("가교수", .professor, "")])
        let groups = model.groups(in: c)
        #expect(groups.map(\.role) == [.professor, .assistant])
        #expect(groups[0].people.map(\.name) == ["가교수", "나교수"])
    }

    @Test func queryMatchesNameOrEmail() throws {
        let model = PeopleModel(workspace: try fixtureWorkspace())
        let c = catalog([("가교수", .professor, "kim@gist.ac.kr"), ("나강사", .lecturer, "lee@gist.ac.kr")])
        model.query = "LEE"
        #expect(model.groups(in: c).flatMap(\.people).map(\.name) == ["나강사"])
        model.query = "없는 사람"
        #expect(model.groups(in: c).isEmpty)
        #expect(model.emptyList == "찾는 사람이 없습니다")
    }

    @Test func selectionRemovedElsewhereFallsBackToFirstInListOrder() throws {
        let model = PeopleModel(workspace: try fixtureWorkspace())
        let c = catalog([("조교", .assistant, ""), ("교수", .professor, "")])
        model.selection = UUID()
        #expect(model.shown(in: c) == c.people[1].id)
    }

    @Test func addSelectsTheNewPersonAndClearsTheSearch() throws {
        let model = PeopleModel(workspace: try fixtureWorkspace())
        var c = Catalog()
        model.query = "김"
        model.add(to: &c)
        #expect(c.people.count == 1)
        #expect(model.selection == c.people[0].id)
        #expect(model.query.isEmpty)
        model.remove(c.people[0], from: &c)
        #expect(c.people.isEmpty && model.selection == nil)
    }

    @Test func removalMessageCountsTaughtCourses() throws {
        let model = PeopleModel(workspace: try fixtureWorkspace())
        let p = Person(device: device, at: .now, name: "김교수")
        #expect(model.removalMessage(p) == "맡은 과목이 없는 사람입니다.")
        #expect(model.subtitle(p) == "교수")
    }
}

@MainActor
struct CodesModelTests {
    let device = UUID()

    @Test func closingTheEditorDropsABlankUnusedCode() throws {
        let model = CodesModel(workspace: try fixtureWorkspace())
        var c = Catalog()
        model.add("학사과정", to: &c)
        let blank = try #require(model.editing)
        model.closeEditor(blank, catalog: &c)
        #expect(c.codes.isEmpty && model.editing == nil)

        model.add("학사과정", to: &c)
        let filled = try #require(model.editing)
        c.codes[0].prefix = "EC"
        model.closeEditor(filled, catalog: &c)
        #expect(c.codes.count == 1)
    }

    @Test func searchHidesProgramsWithoutAMatch() throws {
        let model = CodesModel(workspace: try fixtureWorkspace())
        var c = Catalog()
        c.codes = [CourseCode(device: device, at: .now, prefix: "MA", department: "수리과학과", program: "학사과정"),
                   CourseCode(device: device, at: .now, prefix: "EC", department: "전기전자컴퓨터공학부", program: "학사과정"),
                   CourseCode(device: device, at: .now, prefix: "GS", department: "기초교육학부", program: "")]
        #expect(model.shown("학사과정", in: c).map(\.prefix) == ["EC", "MA"])
        model.query = "전기"
        #expect(model.showsProgram("학사과정", in: c))
        #expect(!model.showsProgram("", in: c))
        #expect(!model.hasNoMatch(in: c))
        model.query = "XX"
        #expect(model.hasNoMatch(in: c))
        #expect(CodesModel.programTitle("") == "과정 없음")
    }
}
