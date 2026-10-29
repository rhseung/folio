@testable import FolioDomain
import Testing

/// Cases taken from names in the real GIST folder.
struct CleanupKeywordTests {
    @Test(arguments: [
        ("Mid-term-2022.pdf", nil, "2022 Midterm.pdf"),
        ("final-term-2024.pdf", nil, "2024 Final.pdf"),
        ("2023_final.pdf", nil, "2023 Final.pdf"),
        ("Mid-term-Answers-2024.docx", nil, "2024 Midterm Solution.docx"),
        ("2024 Midterm.pdf", "소순범", "2024 Midterm (소순범).pdf"),
    ] as [(String, String?, String)])
    func renamesPastExamsWithoutLoss(name: String, source: String?, expected: String) {
        #expect(Keywords.pastExamName(name, source: source) == expected)
    }

    @Test(arguments: [
        "2024 일반화학 I_리자오지에_기말고사 출제발췌.pdf",  // professor name would be lost
        "2023 기말 복기.pdf",
        "Sample-Mid-Term.pdf",                           // no year
        "final-sol.pdf",
        "CG2023_final_2023.pdf",
    ])
    func keepsNamesThatWouldLoseInformation(name: String) {
        #expect(Keywords.pastExamName(name, source: nil) == nil)
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
        var planner = CoursePlanner(course: course)
        let moves = planner.plan()
        #expect(Set(moves.map(\.to)) == ["Exams/Past/2023 Final.pdf", "Exams/Past/2023 Final (2).pdf"])
        #expect(moves.contains { $0.review == .nameCollision })
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
