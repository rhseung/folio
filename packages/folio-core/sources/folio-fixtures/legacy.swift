extension Fixture {
    static let legacyFiles: [(path: String, content: String?)] = [
        // An earlier cleanup moved `Exam Review` into `Exercises` whole; only the journal still says those files are self-made.
        (".folio/moves.jsonl", #"""
            {"at":"2026-10-22T14:01:03.186Z","batch":"B0000000-0000-4000-8000-000000000001","device":"D0000000-0000-4000-8000-000000000001","from":"2026-3/GS2004 선형대수학/Exam Review/Proofs.pdf","id":"E0000000-0000-4000-8000-000000000001","op":"move","schemaVersion":1,"to":"2026-3/GS2004 선형대수학/Exercises/Proofs.pdf"}
            {"at":"2026-10-22T14:01:03.186Z","batch":"B0000000-0000-4000-8000-000000000001","device":"D0000000-0000-4000-8000-000000000001","from":"2026-3/GS2004 선형대수학/Exam Review/Proofs.tex","id":"E0000000-0000-4000-8000-000000000002","op":"move","schemaVersion":1,"to":"2026-3/GS2004 선형대수학/Exercises/Proofs.tex"}
            {"at":"2026-10-22T14:01:03.186Z","batch":"B0000000-0000-4000-8000-000000000001","device":"D0000000-0000-4000-8000-000000000001","from":"2026-3/GS2004 선형대수학/Exam Review","id":"E0000000-0000-4000-8000-000000000003","op":"removeFolder","schemaVersion":1}

            """#),
        ("2026-1/MA2001 선형대수학/강의계획서.pdf", nil),
        ("2026-1/MA2001 선형대수학/강의자료/26_week5.pdf", nil),
        ("2026-1/MA2001 선형대수학/강의자료/week1.pdf", nil),
        ("2026-1/MA2001 선형대수학/노트/1주차 필기.pdf", nil),
        ("2026-1/MA2001 선형대수학/노트/1주차.md", #"""
            # 1주차

            벡터 공간의 정의

            """#),
        ("2026-1/MA2001 선형대수학/숙제/HW1-5070류현승.pdf", nil),
        ("2026-1/MA2001 선형대수학/숙제/hw1.pdf", nil),
        ("2026-1/MA2001 선형대수학/족보/2024 중간.pdf", nil),
        ("2026-1/수강신청 확인서.pdf", nil),
        ("2026-1/학사/2026-1 시험시간표.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Exam Review/Problems.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Exam Review/Problems.tex", nil),
        ("2026-3/EC4207 그래프 이론/Exam Review/Proofs.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Exam Review/Proofs.tex", nil),
        ("2026-3/EC4207 그래프 이론/Exams/Quiz1/", nil),
        ("2026-3/EC4207 그래프 이론/Exams/Quiz3/Quiz3 대비 정리.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Homeworks/26h3.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Homeworks/HW3-5070류현승.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Introduction to Graph Theory (West).pdf", nil),
        ("2026-3/EC4207 그래프 이론/Lectures/Matchings.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Midterm Guideline.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Midterm Seating.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Slow Problems/SP1.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Syllabus.pdf", nil),
        ("2026-3/EC4207 그래프 이론/족보 (소순범)/2024 Midterm.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Notes/Exports/Matchings.pdf", nil),
        ("2026-3/EC4321 로봇공학/Assignments/robot/.git/HEAD", nil),
        ("2026-3/EC4321 로봇공학/Assignments/robot/main.py", nil),
        ("2026-3/EC4321 로봇공학/Books/Modern Robotics.pdf", nil),
        ("2026-3/EC4321 로봇공학/Lectures/01_Intro.pdf", nil),
        ("2026-3/EC4321 로봇공학/Manuals/Lab1 Manual.pdf", nil),
        ("2026-3/EC4321 로봇공학/Reports/Lab1 Report.pdf", nil),
        ("2026-3/EC4321 로봇공학/실험 스케줄.pdf", nil),
        ("2026-3/GS1211 일반화학실험/Exams/Past/관훈 선배 리포트/Lab1 Report.pdf", nil),
        ("2026-3/GS1211 일반화학실험/Exams/Past/mid-sol.pdf", nil),
        ("2026-3/GS2004 선형대수학/Exercises/Proofs.pdf", nil),
        ("2026-3/GS2004 선형대수학/Exercises/Proofs.tex", nil),
        ("2026-3/GS2004 선형대수학/Exercises/exercise 1.png", nil),
        ("GIST OTP/otp.txt", nil),
        ("과대표/회의록.pdf", nil),
    ]
}
