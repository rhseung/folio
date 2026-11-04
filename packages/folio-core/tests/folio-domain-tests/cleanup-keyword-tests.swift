@testable import FolioDomain
import Foundation
import Testing

/// Cases taken from names in the real GIST folder.
struct CleanupKeywordTests {
    @Test func examFolderFromName() {
        #expect(Keywords.examFolder(in: "quiz3 대비 정리.pdf") == "Quiz3")
        #expect(Keywords.examFolder(in: "퀴즈 2 요약.pdf") == "Quiz2")
        #expect(Keywords.examFolder(in: "01_ec3204_mid_mock.pdf") == "Midterm")
        #expect(Keywords.examFolder(in: "기말 정리.pdf") == "Final")
        #expect(Keywords.examFolder(in: "problems.pdf") == nil)
    }

    @Test(arguments: ["Quiz3 대비 정리.pdf", "컴파일러 핵심 요약.md", "01_EC3204_mid_mock.pdf", "컴파일러 압축본.pdf", "Cheat Sheet.pdf"])
    func selfMadeNames(name: String) {
        #expect(Keywords.looksSelfMade(name))
    }

    @Test(arguments: ["Guideline.pdf", "Exercise 1.pdf", "2024 Midterm.pdf", "exercise 1.png"])
    func receivedNames(name: String) {
        #expect(!Keywords.looksSelfMade(name))
    }

    @Test func assignmentNumbers() {
        #expect(Keywords.assignmentNumber(in: "26h3.pdf")?.number == 3)
        #expect(Keywords.assignmentNumber(in: "HW1-5070류현승.pdf")! == (1, nil))
        #expect(Keywords.assignmentNumber(in: "26F_LA_hw5.pdf")?.number == 5)
        #expect(Keywords.assignmentNumber(in: "HW 1.pdf")?.number == 1)
        #expect(Keywords.assignmentNumber(in: "CG26_assignment4.pdf")?.number == 4)
        #expect(Keywords.assignmentNumber(in: "hw1_20255070_python.zip")?.number == 1)
        #expect(Keywords.assignmentNumber(in: "slow_problem_1.jpg")?.number == 1)
        #expect(Keywords.assignmentNumber(in: "2_20255070_류현승_3분반_VSEPR.pdf")! == (2, .guessedNumber))
        #expect(Keywords.assignmentNumber(in: "templateHW.tex") == nil)
    }

    @Test func weeks() {
        #expect(Keywords.week(in: "week1.pdf")! == (1, false, nil))
        #expect(Keywords.week(in: "26_week5.pdf")! == (5, false, nil))
        #expect(Keywords.week(in: "3주차 슬라이드.pdf")?.week == 3)
        #expect(Keywords.week(in: "01 행복이란 무엇인가.pdf")! == (1, true, .guessedWeek))
        #expect(Keywords.week(in: "lecture5aWp-FP_Representation.pdf")?.week == 5)
        #expect(Keywords.week(in: "Matchings.pdf") == nil)
    }

    @Test func lectureNumberingSharesPrefixAcrossFormats() {
        let course = FolderTree(name: "EC2204 컴퓨터 구조", content: .folder([
            FolderTree(name: "강의자료", content: .folder([
                FolderTree(name: "lecture1-Bool.pdf", content: .file(size: 1)),
                FolderTree(name: "lecture1-Bool.pptx", content: .file(size: 1)),
                FolderTree(name: "lecture1-Review.pdf", content: .file(size: 1)),
            ])),
        ]))
        var planner = CoursePlanner(course: course)
        let targets = Set(planner.plan().map(\.to))
        #expect(targets == ["Lectures/01-1_lecture1-Bool.pdf", "Lectures/01-1_lecture1-Bool.pptx", "Lectures/01-2_lecture1-Review.pdf"])
    }

    @Test func collisionsGetSuffixes() {
        let course = FolderTree(name: "GS1201 일반화학", content: .folder([
            FolderTree(name: "족보", content: .folder([
                FolderTree(name: "2023_final.pdf", content: .file(size: 1)),
                FolderTree(name: "Final-2023.pdf", content: .file(size: 1)),
            ])),
        ]))
        let other = FolderTree(name: "Exams", content: .folder([
            FolderTree(name: "Past", content: .folder([FolderTree(name: "2023_final.pdf", content: .file(size: 1))])),
        ]))
        var planner = CoursePlanner(course: FolderTree(name: course.name, content: .folder(course.children + [other])))
        let moves = planner.plan()
        #expect(Set(moves.map(\.to)) == ["Inherited/2023_final.pdf", "Inherited/2023_final (2).pdf", "Inherited/Final-2023.pdf"])
        #expect(moves.contains { $0.review == .nameCollision })
    }

    /// Past exams keep their names in `Inherited`; a source folder moves whole and only loose files are marked.
    @Test func pastExamsGoToInherited() {
        let course = FolderTree(name: "GS1211 일반화학실험", content: .folder([
            FolderTree(name: "Exams", content: .folder([
                FolderTree(name: "Past", content: .folder([
                    FolderTree(name: "관훈 선배 리포트", content: .folder([FolderTree(name: "Lab1.pdf", content: .file(size: 1))])),
                    FolderTree(name: "mid-sol.pdf", content: .file(size: 1)),
                ])),
            ])),
            FolderTree(name: "족보 (소순범)", content: .folder([FolderTree(name: "2024 중간.pdf", content: .file(size: 1))])),
        ]))
        var planner = CoursePlanner(course: course)
        let moves = Dictionary(uniqueKeysWithValues: planner.plan().map { ($0.from, $0) })
        #expect(moves["Exams/Past/관훈 선배 리포트"].map { ($0.to, $0.kind, $0.review) }! == ("Inherited/관훈 선배 리포트", nil, nil))
        #expect(moves["Exams/Past/mid-sol.pdf"].map { ($0.to, $0.kind) }! == ("Inherited/mid-sol.pdf", .pastExam))
        #expect(moves["족보 (소순범)/2024 중간.pdf"].map { ($0.to, $0.kind) }! == ("Inherited/소순범/2024 중간.pdf", .pastExam))
    }

    /// Where the journal says files came from `Exam Review`, `Exercises` is mixed: those go to Study for sure, the rest
    /// only as a suggestion. An `Exercises` with no such history is the professor's and stays.
    @Test func selfMadeFilesLeaveExercises() {
        let file = { (name: String) in FolderTree(name: name, content: .file(size: 1)) }
        let mixed = FolderTree(name: "GS2004 선형대수학", content: .folder([
            FolderTree(name: "Exercises", content: .folder([file("Proofs.pdf"), file("Proofs.tex"), file("exercise 1.png")])),
        ]))
        var planner = CoursePlanner(course: mixed, selfMade: ["Exercises/Proofs.pdf", "Exercises/Proofs.tex"])
        let moves = Dictionary(uniqueKeysWithValues: planner.plan().map { ($0.from, $0) })
        #expect(moves["Exercises/Proofs.pdf"].map { ($0.to, $0.exam, $0.review) }! == ("Study/Proofs.pdf", "Midterm", nil))
        #expect(moves["Exercises/exercise 1.png"].map { ($0.to, $0.exam, $0.review) }! == ("Study/exercise 1.png", nil, .guessedOrigin))

        var clean = CoursePlanner(course: mixed)
        #expect(clean.plan().isEmpty)
    }

    /// A new exam names its folder from its title, so the guessed `Midterm` must become the folder of the exam it means,
    /// or no link at all when the course has no such exam.
    @Test func examLinksNameExamsThatExist() {
        let file = { (name: String) in FolderTree(name: name, content: .file(size: 1)) }
        let course = FolderTree(name: "GS2004 선형대수학", content: .folder([
            FolderTree(name: "Exercises", content: .folder([file("Proofs.pdf"), file("Final Mock.pdf")])),
            file("Guideline.pdf"),
        ]))
        let selfMade: Set<String> = ["Exercises/Proofs.pdf", "Exercises/Final Mock.pdf"]
        var midterm = Exam(device: UUID(), at: .now, title: "중간고사")
        midterm.folder = "중간고사"
        var titled = CoursePlanner(course: course, selfMade: selfMade, exams: [midterm])
        let moves = Dictionary(uniqueKeysWithValues: titled.plan().map { ($0.from, $0) })
        #expect(moves["Exercises/Proofs.pdf"]?.exam == "중간고사")
        #expect(moves["Exercises/Final Mock.pdf"]?.exam == nil && moves["Exercises/Final Mock.pdf"]?.review == nil)
        #expect(moves["Guideline.pdf"]?.to == "Exams/중간고사/Guideline.pdf" && moves["Guideline.pdf"]?.review == .guessedExam)

        var none = CoursePlanner(course: course, selfMade: selfMade, exams: [])
        #expect(none.plan().allSatisfy { $0.exam == nil })
    }

    @Test func journalFollowsSelfMadeFiles() {
        let moves: [(from: String, to: String)] = [
            ("c/Exam Review/a.pdf", "c/Exercises/a.pdf"),
            ("c/Exam Review/b.pdf", "c/Exercises/b.pdf"),
            ("c/Exercises/b.pdf", "c/Exercises/old/b.pdf"),
            ("c/Exercises/old", "c/Archive/old"),
            ("c/Lectures/x.pdf", "c/Exercises/x.pdf"),
        ]
        #expect(CleanupPlanner.selfMade(moves: moves) == ["c/Exercises/a.pdf", "c/Archive/old/b.pdf"])
    }

    /// An exam names its folder from its title, so a folder under Exams stays; only a loose file goes to an exam.
    @Test func examFoldersNamedByTitleStay() {
        let course = FolderTree(name: "EC4207 그래프 이론", content: .folder([
            FolderTree(name: "Exams", content: .folder([
                FolderTree(name: "기말고사", content: .folder([FolderTree(name: "Guideline.pdf", content: .file(size: 1))])),
                FolderTree(name: "Quiz 3", content: .folder([])),
                FolderTree(name: "Seating.pdf", content: .file(size: 1)),
            ])),
        ]))
        var planner = CoursePlanner(course: course)
        #expect(planner.plan().map(\.from) == ["Exams/Seating.pdf"])
        #expect(planner.removals == ["Exams/Quiz 3"])
    }

    /// An exam folder keeps the exam's record; a summary made for it goes to Study, linked, as a suggestion.
    @Test func selfMadeFilesLeaveExamFolders() {
        let course = FolderTree(name: "EC4207 그래프 이론", content: .folder([
            FolderTree(name: "Exams", content: .folder([
                FolderTree(name: "Quiz3", content: .folder([
                    FolderTree(name: "Quiz3 대비 정리.pdf", content: .file(size: 1)), FolderTree(name: "Guideline.pdf", content: .file(size: 1)),
                ])),
            ])),
        ]))
        var planner = CoursePlanner(course: course)
        let moves = planner.plan()
        #expect(moves.map { [$0.from, $0.to, $0.exam ?? ""] } == [["Exams/Quiz3/Quiz3 대비 정리.pdf", "Study/Quiz3 대비 정리.pdf", "Quiz3"]])
        #expect(moves.first?.review == .guessedOrigin)
    }

    /// 2026-2 일반화학실험: experiments counted in schedule order; the leading `2_`/`3_` are not lab numbers.
    @Test func labFilesFollowTheExperimentSchedule() {
        let labs = [
            "Accuracy & Precision", "Separation of benzoic acid and acetanilide (extraction)",
            "Purification of benzoic acid and acetanilide (recrystallization, mp)", "Molecular modeling 1 (VSEPR)",
            "Thin-layer chromatography", "Synthesis of aspirin", "Analysis of synthetic aspirin",
            "Quantitative analysis of aspirin using UV-Vis", "Freezing point depression",
        ]
        let file = { (name: String) in FolderTree(name: name, content: .file(size: 1)) }
        let course = FolderTree(name: "GS1211 일반화학실험", content: .folder([
            FolderTree(name: "Manuals", content: .folder([
                file("accuracy and precision.pdf"), file("Molecular modeling (VSEPR).pdf"),
                file("Recrystallization and melting point determination.pdf"), file("Unrelated.pdf"),
            ])),
            FolderTree(name: "Reports", content: .folder([
                file("2_20255070_류현승_3분반_Accuracy and precision.pdf"), file("3_20255070_류현승_3분반_VSEPR.docx"),
                file("Analysis of synthetic aspirin.pdf"),
            ])),
        ]))
        // Weekly from week 3, so experiment n's session is in week n + 2.
        var planner = CoursePlanner(course: course, labs: Dictionary(uniqueKeysWithValues: labs.enumerated().map { ($1, $0 + 1) }),
                                    labWeeks: Dictionary(uniqueKeysWithValues: labs.indices.map { ($0 + 1, $0 + 3) }))
        let to = Dictionary(uniqueKeysWithValues: planner.plan().map { ($0.from, $0.to) })
        #expect(to["Manuals/accuracy and precision.pdf"] == "Lectures/03_accuracy and precision.pdf")
        #expect(to["Manuals/Recrystallization and melting point determination.pdf"] == "Lectures/05_Recrystallization and melting point determination.pdf")
        #expect(to["Manuals/Molecular modeling (VSEPR).pdf"] == "Lectures/06_Molecular modeling (VSEPR).pdf")
        #expect(to["Reports/2_20255070_류현승_3분반_Accuracy and precision.pdf"]?.hasPrefix("Assignments/Lab01/") == true)
        #expect(to["Reports/3_20255070_류현승_3분반_VSEPR.docx"]?.hasPrefix("Assignments/Lab04/") == true)
        #expect(to["Reports/Analysis of synthetic aspirin.pdf"]?.hasPrefix("Assignments/Lab07/") == true)
        #expect(to["Manuals/Unrelated.pdf"]?.hasPrefix("Lectures/") == true)
    }

    /// The two parts of one experiment share its number, so either part's name finds it.
    @Test func partsOfAnExperimentShareTheNumber() {
        let labs = ["Accuracy & Precision": 1, "Separation of benzoic acid and acetanilide (extraction)": 2,
                    "Purification of benzoic acid and acetanilide (recrystallization, mp)": 2, "Molecular modeling 1 (VSEPR)": 3]
        #expect(Keywords.labNumber(of: "Recrystallization and melting point determination.pdf", labs: labs) == 2)
        #expect(Keywords.labNumber(of: "benzoic acid acetanilide.pdf", labs: labs) == 2)
        #expect(Keywords.labNumber(of: "3_20255070_류현승_3분반_VSEPR.pdf", labs: labs) == 3)
    }
}
