import FolioCore
import FolioDomain
import Foundation
import Testing

struct ProblemExtractionTests {
    let device = UUID(), now = Date(timeIntervalSince1970: 1_790_000_000)

    func material(_ path: String, kind: MaterialKind? = nil) -> Material {
        Material(device: device, at: now, path: path, kind: kind, status: .classified)
    }

    func file(_ materials: [Material], sets: [ProblemSet] = []) -> CourseFile {
        var f = CourseFile(course: Course(device: device, at: now, title: "그래프 이론"))
        f.materials = materials
        f.problemSets = sets
        return f
    }

    @Test func onlyNewSheetsInTheFourFoldersAreExtractedOnTheirOwn() {
        let exam = material("Inherited/소순범/2024 Midterm.pdf")
        let notes = material("Inherited/소순범/요약 노트.pdf")
        let tagged = material("Inherited/소순범/scan01.pdf", kind: .pastExam)
        let book = material("Textbooks/West.pdf", kind: .book)
        let exercise = material("Exercises/Exercise 1.pdf")
        let homework = material("Assignments/HW03/26h3.pdf")
        let submission = material("Assignments/HW03/HW3-5070.pdf", kind: .submission)
        let solution = material("Inherited/소순범/2024 Midterm Solution.pdf")
        let slides = material("Lectures/05_Matchings.pdf")
        let tex = material("Exercises/Sheet 2.tex")
        let all = [exam, notes, tagged, book, exercise, homework, submission, solution, slides, tex]
        let f = file(all)
        #expect(all.filter { ProblemExtraction.automatic($0, in: f) }.map(\.path) == [exam, tagged, book, exercise, homework].map(\.path))
        // 손으로는 렉처와 `.tex` 문제지에서도 뽑는다. 해설과 제출본은 문제지가 아니다.
        #expect(ProblemExtraction.accepts(slides) && ProblemExtraction.accepts(tex))
        #expect(!ProblemExtraction.accepts(solution) && !ProblemExtraction.accepts(submission))

        let done = file(all, sets: [ProblemSet(device: device, at: now, title: "2024 Midterm", materialId: exam.id)])
        #expect(!ProblemExtraction.automatic(exam, in: done))
    }

    @Test func thePickerLeavesOutAnswersAndListsProblemSourcesFirst() {
        let book = material("Textbooks/West.pdf", kind: .book)
        let slides = material("Lectures/05_Matchings.pdf")
        let guideline = material("Exams/Midterm/Guideline.pdf")
        let homework = material("Assignments/HW01/hw1.pdf")
        let template = material("Assignments/HW01/templateHW.tex")
        let exercise = material("Exercises/Exercise 1.pdf")
        let exam = material("Inherited/소순범/2024 Midterm.pdf")
        let scan = material("Inherited/scan01.pdf", kind: .pastExam)
        let named = material("Assignments/HW01/HW1-5070.pdf")
        let linked = material("Assignments/HW01/final answer.pdf")
        let tagged = material("Assignments/HW01/report.pdf", kind: .submission)
        let solution = material("Exercises/Exercise 1 Solution.pdf")
        var f = file([book, slides, guideline, homework, template, exercise, exam, scan, named, linked, tagged, solution])
        var hw = Assignment(device: device, at: now, title: "HW01")
        hw.submissionMaterialIds = [linked.id]
        f.assignments = [hw]
        // 낸 답안(이름, 과제의 제출본, 종류)과 해설은 빠진다.
        #expect(
            ProblemExtraction.sheets(in: f).map(\.path) == [exam, scan, exercise, homework, book, template, guideline, slides].map(\.path))
        // 과제의 문제지로 이은 파일은 제출본 같은 이름이어도 문제지다.
        hw.problemMaterialId = named.id
        f.assignments = [hw]
        #expect(ProblemExtraction.sheets(in: f).map(\.path).contains(named.path))
    }

    @Test func theSourceAndTitleComeFromTheFolder() {
        #expect(ProblemExtraction.source(of: material("Inherited/a.pdf")) == .pastExam)
        #expect(ProblemExtraction.source(of: material("Exams/중간고사/시험지.pdf")) == .pastExam)
        #expect(ProblemExtraction.source(of: material("Textbooks/West.pdf")) == .textbook)
        #expect(ProblemExtraction.source(of: material("Assignments/HW03/26h3.pdf")) == .assignment)
        #expect(ProblemExtraction.source(of: material("Exercises/Exercise 1.pdf")) == .exercise)
        #expect(ProblemExtraction.title(of: material("Inherited/소순범/2024 Midterm.pdf")) == "2024 Midterm")
        #expect(ProblemExtraction.title(of: material("Assignments/HW03/26h3.pdf")) == "HW03 26h3")
        #expect(ProblemExtraction.title(of: material("Assignments/HW03/HW03 problems.pdf")) == "HW03 problems")
    }

    @Test func aSolutionPairsByItsNameWithoutTheMarker() {
        let sheet = material("Inherited/소순범/2024 Midterm.pdf")
        let solution = material("Inherited/소순범/2024 Midterm Solution.pdf")
        let other = material("Inherited/소순범/2023 Midterm Solution.pdf")
        let elsewhere = material("Exercises/2024 Midterm Solution.pdf")
        #expect(ProblemExtraction.solution(for: sheet, in: [sheet, other, elsewhere, solution])?.id == solution.id)

        let hw = material("Assignments/HW03/HW3.pdf"), sol = material("Assignments/HW03/HW3_sol.pdf")
        #expect(ProblemExtraction.solution(for: hw, in: [hw, sol])?.id == sol.id)
        let korean = material("Inherited/2022 중간.pdf"), joined = material("Inherited/2022 중간해설.pdf")
        #expect(ProblemExtraction.solution(for: korean, in: [korean, joined])?.id == joined.id)
        #expect(ProblemExtraction.solution(for: korean, in: [korean, material("Inherited/2022 중간 요약.pdf")]) == nil)

        // 사용자가 이은 해설이 이름보다 먼저다.
        var linked = material("Inherited/소순범/답.pdf")
        linked.solutionOf = sheet.id
        #expect(ProblemExtraction.solution(for: sheet, in: [solution, linked])?.id == linked.id)
    }

    @Test func problemsWithoutUnitsGoToTheUnitHoldingTheirLecturePage() {
        let lecture = UUID()
        var matching = Unit(device: device, at: now, title: "매칭", order: 0)
        matching.lecturePages = [UnitPages(materialId: lecture, firstPage: 1, lastPage: 20)]
        var hall = Unit(device: device, at: now, title: "Hall 정리", order: 0, parentId: matching.id)
        hall.lecturePages = [UnitPages(materialId: lecture, firstPage: 9, lastPage: 14)]
        let flows = Unit(device: device, at: now, title: "흐름", order: 1)
        var sheet = material("Inherited/2024 Midterm.pdf")
        sheet.unitIds = [flows.id]
        let units = [matching, hall, flows]

        let problems = [
            Problem(number: "1", unitIds: [flows.id], lecturePages: [ProblemPage(materialId: lecture, page: 3)]),
            Problem(number: "2", lecturePages: [ProblemPage(materialId: lecture, page: 10)]),
            Problem(number: "3", lecturePages: [ProblemPage(materialId: lecture, page: 3), ProblemPage(materialId: lecture, page: 40)]),
            Problem(number: "4"),
        ]
        let linked = ProblemExtraction.linked(problems, units: units, sheet: sheet)
        // Claude가 고른 단원은 그대로 둔다.
        #expect(linked[0].unitIds == [flows.id])
        // 쪽이 상위와 하위 단원에 모두 들면 더 좁은 단원이다.
        #expect(linked[1].unitIds == [hall.id])
        // 단원의 쪽 구간 밖의 쪽은 버린다.
        #expect(linked[2].unitIds == [matching.id] && linked[2].lecturePages == [ProblemPage(materialId: lecture, page: 3)])
        // 렉처 쪽이 없으면 문제지에 이어진 단원 하나다.
        #expect(linked[3].unitIds == [flows.id])

        sheet.unitIds = [flows.id, matching.id]
        #expect(ProblemExtraction.linked([Problem(number: "4")], units: units, sheet: sheet)[0].unitIds.isEmpty)
    }

    @Test func aDraftsProblemsLiveInItsProposalInput() {
        let input: JSONValue = ["course": "C", "title": "2024 Midterm", "solution": .string(UUID().uuidString), "problems": []]
        var draft = StudyDraft(
            device: device, at: now, kind: .problems, title: "2024 Midterm",
            proposal: ActionProposal(command: "problem-set add", input: input))
        #expect(draft.problems.isEmpty && draft.solutionMaterialId != nil)
        let problems = [Problem(number: "1", page: 2, text: "$K_5$", format: .short, answer: "10")]
        draft.problems = problems
        #expect(draft.problems == problems && draft.proposal.input["title"] == "2024 Midterm")
    }
}
