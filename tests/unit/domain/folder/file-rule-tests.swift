import Foundation
import Testing

@testable import FolioDomain

// 규칙 표로 옮기기 전의 자료 추측과 정리 계획이 낸 결과를 그대로 적었다. 표를 고친 뒤에도 같은 이름은 같은 곳으로 가야 한다.
struct FileRuleTests {
    static let names = [
        "04_Trees.pdf", "05-2_Coloring.pdf", "GT_Lecture 5 - Matchings.pdf", "6주차 흐름.pdf", "week3.pdf", "26_week5.pdf",
        "lec7 notes.pdf", "Lab 2 manual.pdf", "실험 안내 3.pdf", "매뉴얼.pdf", "HW3.pdf", "gt_hw_2_solution.pdf", "homework 1.pdf",
        "Assignment2.pdf", "Lab 2 report.pdf", "slow_problem_1.jpg", "SP1.pdf", "report3.docx", "project 1.zip", "reading 2.pdf",
        "과제1.hwp", "숙제 2.pdf", "2024 중간고사 기출.pdf", "족보 2023.pdf", "past exam 2022.pdf", "previous_exams.pdf",
        "GT_Syllabus_2026.pdf", "강의계획서.pdf", "OT.pdf", "orientation.pdf", "Midterm seating.pdf", "기말 자리 배치.pdf",
        "seating.pdf", "시험 안내.pdf", "Guideline.pdf", "Quiz3 대비 정리.pdf", "Cheat Sheet.pdf", "01 행복이란 무엇인가.pdf",
        "1_intro.pdf", "Introduction to Graph Theory.pdf", "Diestel (5th).pdf", "solution manual.pdf", "Exercise 3.pdf",
        "practice.pdf", "연습문제.pdf", "notes.md", "Matchings.pdf", "scan.pdf", "Ch3.pdf", "chapter 4.pdf",
        "lecture5aWp-FP_Representation.pdf", "mid_mock.pdf",
    ]

    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .gmt
        return c
    }()
    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 14)) ?? .distantPast

    static func intake(_ name: String) -> String {
        let places =
            MaterialIntake.places(assignmentFolders: ["HW01", "HW02", "HW03", "Lab02", "SP01", "Report03", "Project01", "Reading02"])
            + ["Exams/중간고사", "Exams/기말고사"]
        let day = { (m: Int, d: Int) in calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: 10)) ?? .distantPast }
        let exams = [
            Exam(device: UUID(), at: now, title: "기말고사", start: day(12, 15), folder: "기말고사"),
            Exam(device: UUID(), at: now, title: "중간고사", start: day(10, 20), folder: "중간고사"),
        ]
        let g = MaterialIntake.guess(
            IncomingFile(name: name), places: places, sessions: [], exams: exams, now: now, settings: Settings(), calendar: calendar)
        let why =
            switch g.why {
            case .named(let w)?: w
            case .slides(let p)?: "slides \(p)"
            case .book(let p)?: "book \(p)"
            case nil: "-"
            }
        return "\(name) -> \(g.folder) (\(why))"
    }

    static func cleanup(_ files: [String], in folder: String? = nil) -> [String] {
        let nodes = files.map { FolderTree(name: $0, content: .file(size: 1)) }
        let children = folder.map { [FolderTree(name: $0, content: .folder(nodes))] } ?? nodes
        var planner = CoursePlanner(course: FolderTree(name: "EC4207 그래프 이론", content: .folder(children)))
        return planner.plan().map { m in
            "\(m.from) -> \(m.to) (\(m.review.map { "\($0)" } ?? "-"), \(m.exam ?? "-"))"
        }
    }

    @Test func intakeGuessesStayTheSame() {
        #expect(
            Self.names.map(Self.intake).joined(separator: "\n")
                == """
                04_Trees.pdf -> Lectures (04_)
                05-2_Coloring.pdf -> Lectures (05-2_)
                GT_Lecture 5 - Matchings.pdf -> Lectures (Lecture 5)
                6주차 흐름.pdf -> Lectures (6주차)
                week3.pdf -> Lectures (week3)
                26_week5.pdf -> Lectures (26_)
                lec7 notes.pdf -> Lectures (lec7)
                Lab 2 manual.pdf -> Lectures (manual)
                실험 안내 3.pdf -> Lectures (실험 안내)
                매뉴얼.pdf -> Lectures (매뉴얼)
                HW3.pdf -> Assignments/HW03 (HW3)
                gt_hw_2_solution.pdf -> Assignments/HW02 (hw_2)
                homework 1.pdf -> Assignments/HW01 (homework 1)
                Assignment2.pdf -> Assignments/HW02 (Assignment2)
                Lab 2 report.pdf -> Assignments/Lab02 (Lab 2)
                slow_problem_1.jpg -> Assignments/SP01 (slow_problem_1)
                SP1.pdf -> Assignments/SP01 (SP1)
                report3.docx -> Assignments/Report03 (report3)
                project 1.zip -> Assignments/Project01 (project 1)
                reading 2.pdf -> Assignments/Reading02 (reading 2)
                과제1.hwp -> Assignments/HW01 (과제1)
                숙제 2.pdf -> Assignments/HW02 (숙제 2)
                2024 중간고사 기출.pdf -> Inherited (기출)
                족보 2023.pdf -> Inherited (족보)
                past exam 2022.pdf -> Inherited (past exam)
                previous_exams.pdf -> Inherited (previous_exams)
                GT_Syllabus_2026.pdf -> Syllabus (syllabus)
                강의계획서.pdf -> Syllabus (강의계획서)
                OT.pdf -> Lectures (-)
                orientation.pdf -> Syllabus (orientation)
                Midterm seating.pdf -> Exams/중간고사 (seating)
                기말 자리 배치.pdf -> Exams/기말고사 (자리)
                seating.pdf -> Exams/중간고사 (seating)
                시험 안내.pdf -> Exams/중간고사 (시험 안내)
                Guideline.pdf -> Exams/중간고사 (guideline)
                Quiz3 대비 정리.pdf -> Lectures (-)
                Cheat Sheet.pdf -> Lectures (-)
                01 행복이란 무엇인가.pdf -> Lectures (-)
                1_intro.pdf -> Lectures (-)
                Introduction to Graph Theory.pdf -> Textbooks (introduction to)
                Diestel (5th).pdf -> Lectures (-)
                solution manual.pdf -> Lectures (manual)
                Exercise 3.pdf -> Exercises (Exercise)
                practice.pdf -> Exercises (practice)
                연습문제.pdf -> Exercises (연습)
                notes.md -> Lectures (-)
                Matchings.pdf -> Lectures (-)
                scan.pdf -> Lectures (-)
                Ch3.pdf -> Lectures (-)
                chapter 4.pdf -> Lectures (-)
                lecture5aWp-FP_Representation.pdf -> Lectures (lecture5)
                mid_mock.pdf -> Lectures (-)
                """)
    }

    @Test func topLevelCleanupStaysTheSame() {
        #expect(
            Self.cleanup(Self.names).joined(separator: "\n")
                == """
                01 행복이란 무엇인가.pdf -> Lectures/01-2_행복이란 무엇인가.pdf (guessedWeek, -)
                04_Trees.pdf -> Lectures/04_Trees.pdf (guessedWeek, -)
                05-2_Coloring.pdf -> Archive/05-2_Coloring.pdf (unknownFile, -)
                1_intro.pdf -> Lectures/01-1_intro.pdf (guessedWeek, -)
                2024 중간고사 기출.pdf -> Archive/2024 중간고사 기출.pdf (unknownFile, -)
                26_week5.pdf -> Lectures/05_26_week5.pdf (-, -)
                6주차 흐름.pdf -> Archive/6주차 흐름.pdf (unknownFile, -)
                Assignment2.pdf -> Archive/Assignment2.pdf (unknownFile, -)
                Ch3.pdf -> Archive/Ch3.pdf (unknownFile, -)
                Cheat Sheet.pdf -> Study/Cheat Sheet.pdf (guessedOrigin, -)
                Diestel (5th).pdf -> Textbooks/Diestel (5th).pdf (guessedFolder, -)
                Exercise 3.pdf -> Archive/Exercise 3.pdf (unknownFile, -)
                GT_Lecture 5 - Matchings.pdf -> Archive/GT_Lecture 5 - Matchings.pdf (unknownFile, -)
                GT_Syllabus_2026.pdf -> Syllabus/GT_Syllabus_2026.pdf (-, -)
                Guideline.pdf -> Exams/Midterm/Guideline.pdf (guessedExam, -)
                HW3.pdf -> Archive/HW3.pdf (unknownFile, -)
                Introduction to Graph Theory.pdf -> Textbooks/Introduction to Graph Theory.pdf (guessedFolder, -)
                Lab 2 manual.pdf -> Archive/Lab 2 manual.pdf (unknownFile, -)
                Lab 2 report.pdf -> Archive/Lab 2 report.pdf (unknownFile, -)
                Matchings.pdf -> Archive/Matchings.pdf (unknownFile, -)
                Midterm seating.pdf -> Exams/Midterm/Seating.pdf (-, -)
                OT.pdf -> Syllabus/OT.pdf (-, -)
                Quiz3 대비 정리.pdf -> Study/Quiz3 대비 정리.pdf (guessedOrigin, Quiz3)
                SP1.pdf -> Archive/SP1.pdf (unknownFile, -)
                chapter 4.pdf -> Archive/chapter 4.pdf (unknownFile, -)
                gt_hw_2_solution.pdf -> Archive/gt_hw_2_solution.pdf (unknownFile, -)
                homework 1.pdf -> Archive/homework 1.pdf (unknownFile, -)
                lec7 notes.pdf -> Archive/lec7 notes.pdf (unknownFile, -)
                lecture5aWp-FP_Representation.pdf -> Archive/lecture5aWp-FP_Representation.pdf (unknownFile, -)
                mid_mock.pdf -> Study/mid_mock.pdf (guessedOrigin, Midterm)
                notes.md -> Notes/notes.md (-, -)
                orientation.pdf -> Syllabus/orientation.pdf (-, -)
                past exam 2022.pdf -> Archive/past exam 2022.pdf (unknownFile, -)
                practice.pdf -> Archive/practice.pdf (unknownFile, -)
                previous_exams.pdf -> Archive/previous_exams.pdf (unknownFile, -)
                project 1.zip -> Archive/project 1.zip (unknownFile, -)
                reading 2.pdf -> Archive/reading 2.pdf (unknownFile, -)
                report3.docx -> Archive/report3.docx (unknownFile, -)
                scan.pdf -> Archive/scan.pdf (unknownFile, -)
                seating.pdf -> Exams/Midterm/Seating (2).pdf (nameCollision, -)
                slow_problem_1.jpg -> Archive/slow_problem_1.jpg (unknownFile, -)
                solution manual.pdf -> Textbooks/solution manual.pdf (guessedFolder, -)
                week3.pdf -> Archive/week3.pdf (unknownFile, -)
                강의계획서.pdf -> Syllabus/강의계획서.pdf (-, -)
                과제1.hwp -> Archive/과제1.hwp (unknownFile, -)
                기말 자리 배치.pdf -> Exams/Final/Seating.pdf (-, -)
                매뉴얼.pdf -> Archive/매뉴얼.pdf (unknownFile, -)
                숙제 2.pdf -> Archive/숙제 2.pdf (unknownFile, -)
                시험 안내.pdf -> Exams/Midterm/Guideline (2).pdf (nameCollision, -)
                실험 안내 3.pdf -> Archive/실험 안내 3.pdf (unknownFile, -)
                연습문제.pdf -> Archive/연습문제.pdf (unknownFile, -)
                족보 2023.pdf -> Archive/족보 2023.pdf (unknownFile, -)
                """)
    }

    @Test func lectureAndAssignmentCleanupStaysTheSame() {
        let lectures = ["week1.pdf", "lecture2.pdf", "Ch3.pdf", "01 intro.pdf", "3주차.pdf", "x.pdf", "26_week5.pdf", "GT_lec6.pdf"]
        let assignments = ["hw1.pdf", "lab 3 data.pdf", "26h3.pdf", "random.pdf", "slow problems 2.pdf", "CG26_assignment4.pdf"]
        #expect(
            Self.cleanup(lectures, in: "강의자료").joined(separator: "\n")
                == """
                강의자료/01 intro.pdf -> Lectures/01-1_intro.pdf (guessedWeek, -)
                강의자료/26_week5.pdf -> Lectures/05_26_week5.pdf (-, -)
                강의자료/3주차.pdf -> Lectures/03-1_3주차.pdf (-, -)
                강의자료/Ch3.pdf -> Lectures/03-2_Ch3.pdf (guessedWeek, -)
                강의자료/GT_lec6.pdf -> Lectures/06_GT_lec6.pdf (guessedWeek, -)
                강의자료/lecture2.pdf -> Lectures/02_lecture2.pdf (guessedWeek, -)
                강의자료/week1.pdf -> Lectures/01-2_week1.pdf (-, -)
                강의자료/x.pdf -> Lectures/07_x.pdf (unknownWeek, -)
                """)
        #expect(
            Self.cleanup(assignments, in: "숙제").joined(separator: "\n")
                == """
                숙제/26h3.pdf -> Assignments/HW03/26h3.pdf (-, -)
                숙제/CG26_assignment4.pdf -> Assignments/HW04/CG26_assignment4.pdf (-, -)
                숙제/hw1.pdf -> Assignments/HW01/hw1.pdf (-, -)
                숙제/lab 3 data.pdf -> Assignments/Lab03/lab 3 data.pdf (-, -)
                숙제/random.pdf -> Assignments/HW00/random.pdf (unknownNumber, -)
                숙제/slow problems 2.pdf -> Assignments/HW02/slow problems 2.pdf (-, -)
                """)
    }
}
