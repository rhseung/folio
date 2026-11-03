import Foundation
import FolioDomain
import Testing

struct StandardLayoutTests {
    @Test(arguments: [("2026-1", Term.spring), ("2026-2", .summer), ("2026-3", .fall), ("2026-4", .winter)])
    func parsesSemesterFolder(name: String, term: Term) throws {
        let folder = try #require(SemesterFolder(name: name))
        #expect(folder.year == 2026)
        #expect(folder.term == term)
        #expect(SemesterFolder(year: 2026, term: term)?.name == name)
    }

    @Test(arguments: ["2026-5", "2026-0", "2026-03", "+2026-3", "2026-3 가을", "26-3", "2026", "학사"])
    func rejectsNonSemesterNames(name: String) {
        #expect(SemesterFolder(name: name) == nil)
    }

    @Test func creditedTermHasNoFolder() {
        #expect(SemesterFolder(year: 2026, term: .credited) == nil)
    }

    @Test func widgetFileIsInTheCourseMetadata() throws {
        let id = UUID()
        let course = URL(filePath: "/GIST/2026-3/EC4207 그래프 이론")
        let expected = course.appending(path: ".folio/widgets/\(id.uuidString).html")
        #expect(StandardLayout.widgetFile(id, noteFolder: course.appending(path: "Notes")) == expected)
        #expect(StandardLayout.widgetFile(id, noteFolder: course.appending(path: "Notes/Week 9")) == expected)
        #expect(StandardLayout.widgetFile(id, noteFolder: URL(filePath: "/GIST/Notes")) == nil)
    }

    @Test func fileNameRules() {
        #expect(StandardLayout.isCourseFolderName("EC4207 그래프 이론"))
        #expect(!StandardLayout.isCourseFolderName("그래프 이론"))
        #expect(!StandardLayout.isCourseFolderName("EC4207"))

        #expect(StandardLayout.isLectureFileName("05_Matchings.pdf"))
        #expect(StandardLayout.isLectureFileName("05-2_Cofactors.pdf"))
        #expect(!StandardLayout.isLectureFileName("Matchings.pdf"))
        #expect(!StandardLayout.isLectureFileName("5_Matchings.pdf"))
        #expect(StandardLayout.lectureWeek("05-2_Cofactors.pdf") == 5)
        #expect(StandardLayout.lectureWeek("10_SDT.pdf") == 10)
        #expect(StandardLayout.lectureWeek("03 Syntax.pdf") == nil)

        #expect(StandardLayout.isPastExamFileName("2024 Midterm (소순범).pdf"))
        #expect(StandardLayout.isPastExamFileName("2024 Midterm (소순범) Solution.pdf"))
        #expect(StandardLayout.isPastExamFileName("2025 Final.pdf"))
        #expect(!StandardLayout.isPastExamFileName("2024 중간.pdf"))

        #expect(StandardLayout.isExamFolderName("Quiz2"))
        #expect(!StandardLayout.isExamFolderName("Exam Review"))

        #expect(StandardLayout.assignmentFolder("HW03")! == ("HW", 3))
        #expect(StandardLayout.assignmentFolder("HW3") == nil)
        #expect(StandardLayout.assignmentFolder("Quiz01") == nil)
        #expect(StandardLayout.assignmentFolder("Quiz01", extraPrefixes: ["Quiz"]) != nil)
    }

    @Test func roleFollowsFolder() {
        #expect(MaterialRole(path: "Lectures/05_Matchings.pdf") == .lecture)
        #expect(MaterialRole(path: "Assignments/HW03/26h3.pdf") == .assignment)
        #expect(MaterialRole(path: "Assignments/Lab01/Lab1 Manual.pdf") == .lab)
        #expect(MaterialRole(path: "Exams/Past/2025 Final.pdf") == .pastExam)
        #expect(MaterialRole(path: "Exams/Midterm/Problems.pdf") == .examPrep)
        #expect(MaterialRole(path: "Syllabus.pdf") == nil)
        #expect(MaterialRole(path: "Assignments/stray.pdf") == nil)
        #expect(MaterialRole(path: "Notes/a.md") == nil)

        let overrides: [String: MaterialRole] = ["Lectures/Guest": .other, "Extra": .exercise]
        #expect(MaterialTracking.role(for: "Lectures/Guest/talk.pdf", overrides: overrides) == .other)
        #expect(MaterialTracking.role(for: "Lectures/Guests.pdf", overrides: overrides) == .lecture)
        #expect(MaterialTracking.role(for: "Extra/sheet.pdf", overrides: overrides) == .exercise)
    }
}

@Test func courseFolderNameFromCodeAndNumber() {
    #expect(StandardLayout.courseFolderName(prefix: "EC", number: "4207-01", title: "그래프 이론") == "EC4207 그래프 이론")
    #expect(StandardLayout.courseFolderName(prefix: "GS", number: "1211", title: " 일반화학실험/I ") == "GS1211 일반화학실험-I")
    #expect(StandardLayout.courseFolderName(prefix: "", number: "4207", title: "x") == nil)
}

@Test func intakeNamesKeepWeekOrderAndNeverReuseAName() {
    #expect(MaterialIntake.lectureName("Matchings.pdf", week: 5) == "05_Matchings.pdf")
    #expect(MaterialIntake.lectureName("05-2_Matchings.pdf", week: 6) == "05-2_Matchings.pdf")
    #expect(MaterialIntake.freeName("a.pdf", taken: []) == "a.pdf")
    #expect(MaterialIntake.freeName("a.pdf", taken: ["a.pdf", "a 2.pdf"]) == "a 3.pdf")
    #expect(MaterialIntake.freeName("code", taken: ["code"]) == "code 2")
}

@Test func anExamKeepsItsOwnFolderAndANewOneIsNamedByTitle() {
    var midterm = Exam(device: UUID(), at: .now, title: "중간고사")
    midterm.folder = "Midterm"
    let loose = Exam(device: UUID(), at: .now, title: "구술")
    #expect(MaterialIntake.folder(of: midterm) == "Exams/Midterm")
    #expect(MaterialIntake.folder(of: loose) == nil)
    #expect(MaterialIntake.examFolder(title: "Midterm", among: [midterm]) == "Midterm 2")
    #expect(MaterialIntake.examFolder(title: " Past ", among: []) == "Past 2")
    #expect(MaterialIntake.examFolder(title: "1/2차: 필기", among: []) == "1-2차- 필기")
    #expect(MaterialIntake.examFolder(title: "..", among: []) == "Exam")
}

@Test func aPathTreeFoldsSharedFoldersAndSortsNaturally() {
    let paths = ["Assignments/HW10/a.pdf", "Assignments/HW2/b.pdf", "Assignments/HW2/sub/c.pdf", "Assignments/x.pdf"]
    let tree = PathTree(paths) { $0 }
    #expect(tree.path == "Assignments")
    #expect(tree.items.map(\.name) == ["x.pdf"])
    #expect(tree.folders.map(\.path) == ["Assignments/HW2", "Assignments/HW10"])
    #expect(tree.folders[0].folders.map(\.name) == ["sub"])
    #expect(tree.count == 4)
    #expect(PathTree(["Lectures/01_a.pdf"]) { $0 }.path == "Lectures")
}
