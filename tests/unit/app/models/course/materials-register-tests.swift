import FolioActions
import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import Folio

@MainActor
struct MaterialsRegisterTests {
    let workspace: Workspace
    let course: LoadedCourse

    init() throws {
        workspace = try fixtureWorkspace()
        course = try #require(workspace.course(graphTheory))
    }

    @Test func openingThePageRegistersFilesAddedInFinder() async throws {
        let assignments = course.file.assignments
        try Data("새 렉처".utf8).write(to: course.store.url.appending(path: "Lectures/06_Colorings.pdf"))
        let model = MaterialsModel(workspace: workspace, course: course)
        await model.load()
        #expect(model.materials.contains { $0.path == "Lectures/06_Colorings.pdf" && $0.role == .lecture })
        // 과제 없는 과제 폴더(HW03, SP01)의 파일은 등록하지만 과제는 버튼을 누를 때만 만든다.
        #expect(model.materials.contains { $0.path == "Assignments/HW03/26h3.pdf" })
        #expect(model.course.file.assignments == assignments)
    }

    @Test func openingAgainDoesNotRewriteCourseJSON() async throws {
        await MaterialsModel(workspace: workspace, course: course).load()
        let url = course.store.courseFileURL
        let saved = try Data(contentsOf: url)
        let modified = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        await MaterialsModel(workspace: workspace, course: course).load()
        var reread = url
        reread.removeAllCachedResourceValues()
        #expect(try Data(contentsOf: url) == saved)
        #expect(try reread.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == modified)
    }

    @Test func theButtonStillMakesAssignmentsFromTheirFolders() async throws {
        let model = MaterialsModel(workspace: workspace, course: course)
        await model.load()
        model.track()
        #expect(Set(model.course.file.assignments.map(\.title)).isSuperset(of: ["HW03", "SP01"]))
    }
}
