import FolioDomain
import FolioStorage
import Foundation
import Testing

@testable import Folio

@MainActor
struct UnfiledCoursesModelTests {
    func unfile(_ workspace: Workspace, source: String?? = .none) throws {
        let gist = try #require(workspace.gist)
        let folder = gist.url.appending(path: "_Credited/영재고 AP/GS1101 일반물리학 및 연습 I")
        var course = try CourseStore(url: folder).load().model.course
        course.codes = [addCode("GS", to: workspace)]
        try FileManager.default.removeItem(at: folder)
        var transcript = try gist.loadTranscript()
        transcript.model.unfiledCourses = [course]
        if case .some(let source) = source, let i = transcript.model.semesters.firstIndex(where: { $0.id == creditedTerm }) {
            transcript.model.semesters[i].source = source
        }
        try gist.save(transcript)
        workspace.reload()
    }

    @Test func nothingUnfiledShowsNothing() throws {
        let model = UnfiledCoursesModel(workspace: try fixtureWorkspace())
        #expect(model.courses.isEmpty)
    }

    @Test func movingFilesTheCourseUnderItsSource() throws {
        let workspace = try fixtureWorkspace()
        try unfile(workspace)
        let model = UnfiledCoursesModel(workspace: workspace)
        #expect(model.courses.map(\.id) == [creditedCourse])
        #expect(!workspace.allCourses.contains { $0.id == creditedCourse })
        #expect(model.refusal == nil && !model.confirmation.isEmpty)
        #expect(model.detail(model.courses[0]).contains("3학점"))

        model.move()
        #expect(model.courses.isEmpty)
        #expect(workspace.allCourses.contains { $0.id == creditedCourse })
        let root = try #require(workspace.gist).url
        #expect(
            FileManager.default.fileExists(atPath: root.appending(path: "_Credited/영재고 AP/GS1101 일반물리학 및 연습 I/.folio/course.json").path))
    }

    @Test func aCreditedTermWithoutASourceRefuses() throws {
        let workspace = try fixtureWorkspace()
        try unfile(workspace, source: .some(nil))
        let model = UnfiledCoursesModel(workspace: workspace)
        #expect(model.courses.count == 1)
        #expect(model.refusal?.contains("출처") == true)
    }
}
