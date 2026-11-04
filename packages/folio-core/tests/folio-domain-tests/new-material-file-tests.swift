import FolioDomain
import Foundation
import Testing

struct NewMaterialFileTests {
    let device = UUID()
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test(arguments: ["Assignments/HW04", "Exams/중간고사", "Study", "Study/풀이", "Archive", "Assignments/HW04/src"])
    func ownFoldersTakeNewFiles(_ folder: String) {
        #expect(NewMaterialFile.accepts(folder: folder))
    }

    @Test(arguments: ["", "Assignments", "Exams", "Lectures", "Syllabus", "Exercises", "Textbooks", "Inherited", "Notes", "Ink",
                      "Recordings", ".folio", "Assignments/../Lectures", "Study/.hidden", "Study//x", "Elsewhere"])
    func otherFoldersDoNot(_ folder: String) {
        #expect(!NewMaterialFile.accepts(folder: folder))
    }

    /// Below Assignments and Exams only an item's folder: a CLI typo must not make a folder no exam owns.
    @Test func onlyItemFoldersBelowAssignmentsAndExams() {
        let places = ["Study", "Archive", "Assignments/HW04", "Exams/중간고사"]
        for ok in ["Assignments/HW04", "Assignments/HW04/src", "Exams/중간고사", "Study/풀이", "Archive"] {
            #expect(NewMaterialFile.accepts(folder: ok, places: places), "\(ok)")
        }
        for bad in ["Exams/중간고사오타", "Assignments/foo", "Assignments/HW05/src", "Lectures"] {
            #expect(!NewMaterialFile.accepts(folder: bad, places: places), "\(bad)")
        }
    }

    @Test func defaultIsTheAssignmentDueLast() {
        let day: TimeInterval = 86_400
        let lab = Assignment(device: device, at: now, title: "Lab 1", due: now + day)
        let hw = Assignment(device: device, at: now, title: "HW 4", due: now + 3 * day)
        let undated = Assignment(device: device, at: now + 2 * day, title: "HW 3")
        let places = NewMaterialFile.places(assignments: [lab, hw, undated], exams: [], assignmentFolders: [])
        #expect(NewMaterialFile.defaultPlace(assignments: [lab, hw, undated], places: places) == "Assignments/HW04")
        #expect(NewMaterialFile.defaultPlace(assignments: [lab, undated], places: places) == "Assignments/HW03")
        #expect(NewMaterialFile.defaultPlace(assignments: [], places: places) == "Study")
    }

    @Test func fileNames() {
        #expect(NewMaterialFile.isFileName("hw4.tex"))
        #expect(NewMaterialFile.isFileName("풀이 1.py"))
        for bad in ["", " hw.tex", "a/b.tex", "a:b.tex", ".hw.tex", ".."] { #expect(!NewMaterialFile.isFileName(bad), "\(bad)") }
    }

    @Test func placesListEveryAssignmentAndExamOnce() {
        let assignments = [Assignment(device: device, at: now, title: "HW 4"), Assignment(device: device, at: now, title: "HW 3")]
        let exams = [Exam(device: device, at: now, title: "중간고사", folder: "중간고사"), Exam(device: device, at: now, title: "폴더 없음")]
        let places = NewMaterialFile.places(assignments: assignments, exams: exams, assignmentFolders: ["HW03", "Lab01"])
        #expect(places == ["Study", "Archive", "Assignments/HW03", "Assignments/HW04", "Assignments/Lab01", "Exams/중간고사"])
    }

    /// The `.tex` starts as a document Tectonic builds; anything else starts empty.
    @Test func startingText() {
        let tex = NewMaterialFile.text(for: "hw4.TEX")
        #expect(tex.hasPrefix("\\documentclass[11pt]{article}\n\\usepackage{kotex}\n"))
        #expect(tex.hasSuffix("\\begin{document}\n\n\\end{document}\n"))
        #expect(NewMaterialFile.text(for: "a.py") == "")
        #expect(NewMaterialFile.text(for: "a.txt") == "")
    }
}
