import FolioDomain
import FolioFixtures
import FolioStorage
import Foundation
import Testing

struct FixtureTests {
    @Test func standardHasNoLayoutIssues() throws {
        let gist = GISTStore(url: try Fixture.standard.copyToTemp())
        #expect(try gist.layoutIssues() == [])
        #expect(try gist.courseStores().count == 3)
    }

    @Test func legacyIssuesAreAllReported() throws {
        let gist = GISTStore(url: try Fixture.legacy.copyToTemp())
        let ma = "2026-1/MA2001 선형대수학"
        let ec = "2026-3/EC4207 그래프 이론"
        let robot = "2026-3/EC4321 로봇공학"
        let expected: Set<LayoutIssue> = [
            .init(.unexpectedRootItem, "GIST OTP"),
            .init(.unexpectedRootItem, "과대표"),
            .init(.fileInSemesterFolder, "2026-1/수강신청 확인서.pdf"),
            .init(.invalidCourseFolderName, "2026-1/학사"),
            .init(.fileInCourseFolder, "\(ma)/강의계획서.pdf"),
            .init(.unknownCourseSubfolder, "\(ma)/강의자료"),
            .init(.unknownCourseSubfolder, "\(ma)/노트"),
            .init(.unknownCourseSubfolder, "\(ma)/숙제"),
            .init(.unknownCourseSubfolder, "\(ma)/족보"),
            .init(.unknownCourseSubfolder, "\(ec)/Exam Review"),
            .init(.unknownCourseSubfolder, "\(ec)/Homeworks"),
            .init(.unknownCourseSubfolder, "\(ec)/Slow Problems"),
            .init(.unknownCourseSubfolder, "\(ec)/족보 (소순범)"),
            .init(.fileInCourseFolder, "\(ec)/Introduction to Graph Theory (West).pdf"),
            .init(.fileInCourseFolder, "\(ec)/Midterm Guideline.pdf"),
            .init(.fileInCourseFolder, "\(ec)/Midterm Seating.pdf"),
            .init(.fileInCourseFolder, "\(ec)/Syllabus.pdf"),
            .init(.invalidLectureFileName, "\(ec)/Lectures/Matchings.pdf"),
            .init(.invalidAssignmentFolder, "\(robot)/Assignments/robot"),
            .init(.unknownCourseSubfolder, "\(robot)/Books"),
            .init(.unknownCourseSubfolder, "\(robot)/Manuals"),
            .init(.unknownCourseSubfolder, "\(robot)/Reports"),
            .init(.fileInCourseFolder, "\(robot)/실험 스케줄.pdf"),
        ]
        let issues = try gist.layoutIssues()
        #expect(Set(issues) == expected)
        #expect(issues.count == expected.count)
    }

    @Test func onlyDeepFoldersCollapseForSize() throws {
        let root = try Fixture.standard.copyToTemp()
        let course = root.appending(path: "2026-3/EC4207 그래프 이론")
        let data = course.appending(path: "Assignments/HW03/data")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        for i in 0...IndexRules.maxIndexedFiles {
            FileManager.default.createFile(atPath: data.appending(path: "\(i).csv").path, contents: nil)
            FileManager.default.createFile(atPath: course.appending(path: "Lectures/\(i)_x.pdf").path, contents: nil)
        }
        let tree = try FolderTree(contentsOf: root)
        let ec = try #require(tree[child: "2026-3"]?[child: "EC4207 그래프 이론"])
        #expect(ec[child: "Lectures"]?.children.count ?? 0 > IndexRules.maxIndexedFiles)
        #expect(ec[child: "Assignments"]?[child: "HW03"]?[child: "data"]?.content == .opaque(.tooManyFiles))
    }

    @Test func readerSkipsIgnoredFilesAndCodeProjects() throws {
        let root = try Fixture.legacy.copyToTemp()
        let course = root.appending(path: "2026-3/EC4321 로봇공학")
        FileManager.default.createFile(atPath: course.appending(path: ".DS_Store").path, contents: nil)
        FileManager.default.createFile(atPath: course.appending(path: "~$report.docx").path, contents: nil)

        let tree = try FolderTree(contentsOf: course, depth: IndexRules.courseFolderDepth)
        #expect(tree[child: ".DS_Store"] == nil)
        #expect(tree[child: "~$report.docx"] == nil)
        #expect(tree[child: "Assignments"]?[child: "robot"]?.content == .opaque(.codeProject))
    }
}
