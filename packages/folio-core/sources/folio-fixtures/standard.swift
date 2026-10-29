extension Fixture {
    static let standardFiles: [(path: String, content: String?)] = [
        (".folio/transcript.json", #"""
            {
              "schemaVersion" : 1,
              "semesters" : [
                {
                  "createdAt" : "2026-02-20T09:00:00.000Z",
                  "end" : "2026-06-19",
                  "id" : "5E4F1A00-0000-4000-8000-000000000001",
                  "memo" : "",
                  "start" : "2026-03-02",
                  "term" : "spring",
                  "updatedAt" : "2026-02-20T09:00:00.000Z",
                  "updatedBy" : "D0000000-0000-4000-8000-000000000001",
                  "year" : 2026
                },
                {
                  "createdAt" : "2026-08-25T09:00:00.000Z",
                  "end" : "2026-12-18",
                  "id" : "5E4F1A00-0000-4000-8000-000000000003",
                  "memo" : "",
                  "start" : "2026-09-01",
                  "term" : "fall",
                  "updatedAt" : "2026-08-25T09:00:00.000Z",
                  "updatedBy" : "D0000000-0000-4000-8000-000000000001",
                  "year" : 2026
                }
              ]
            }

            """#),
        ("2026-1/MA2001 선형대수학/.folio/course.json", #"""
            {
              "course" : {
                "categoryIds" : [],
                "codes" : [],
                "color" : "",
                "createdAt" : "2026-08-25T09:00:00.000Z",
                "credits" : 3,
                "folderRoles" : {},
                "gradingMode" : "relative",
                "id" : "C0000000-0000-4000-8000-000000000001",
                "instructorIds" : [],
                "memo" : "",
                "number" : "",
                "schedule" : [],
                "semesterId" : "5E4F1A00-0000-4000-8000-000000000001",
                "title" : "선형대수학",
                "titleEn" : "",
                "updatedAt" : "2026-08-25T09:00:00.000Z",
                "updatedBy" : "D0000000-0000-4000-8000-000000000001"
              },
              "materials" : [],
              "schemaVersion" : 1
            }

            """#),
        ("2026-1/MA2001 선형대수학/Archive/선형대수학 노타빌리티.pdf", nil),
        ("2026-1/MA2001 선형대수학/Assignments/HW01/HW1-5070류현승.pdf", nil),
        ("2026-1/MA2001 선형대수학/Assignments/HW01/hw1.pdf", nil),
        ("2026-1/MA2001 선형대수학/Exams/Past/2024 Midterm.pdf", nil),
        ("2026-1/MA2001 선형대수학/Lectures/01_Vectors.pdf", nil),
        ("2026-1/MA2001 선형대수학/Lectures/05-1_Determinants.pdf", nil),
        ("2026-1/MA2001 선형대수학/Lectures/05-2_Cofactors.pdf", nil),
        ("2026-1/MA2001 선형대수학/Notes/1주차-1.md", #"""
            ---
            id: 0b9e7a51-3c2d-4e8f-a6b4-1d5c9f2e7a83
            kind: rough
            ---

            # 1주차-1

            """#),
        ("2026-1/MA2001 선형대수학/Syllabus/Syllabus.pdf", nil),
        ("2026-1/_Admin/2026-1 시험시간표.pdf", nil),
        ("2026-3/EC4207 그래프 이론/.folio/course.json", #"""
            {
              "course" : {
                "categoryIds" : [],
                "codes" : [],
                "color" : "",
                "createdAt" : "2026-08-25T09:00:00.000Z",
                "credits" : 3,
                "folderRoles" : {},
                "gradingMode" : "relative",
                "id" : "C0000000-0000-4000-8000-000000000002",
                "instructorIds" : [],
                "memo" : "",
                "number" : "",
                "schedule" : [],
                "semesterId" : "5E4F1A00-0000-4000-8000-000000000003",
                "title" : "그래프 이론",
                "titleEn" : "",
                "updatedAt" : "2026-08-25T09:00:00.000Z",
                "updatedBy" : "D0000000-0000-4000-8000-000000000001"
              },
              "materials" : [],
              "schemaVersion" : 1
            }

            """#),
        ("2026-3/EC4207 그래프 이론/Assignments/HW03/26h3.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Assignments/HW03/HW3-5070류현승.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Assignments/SP01/SP1.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Exams/Midterm/Guideline.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Exams/Midterm/Problems.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Exams/Midterm/Problems.tex", nil),
        ("2026-3/EC4207 그래프 이론/Exams/Midterm/Seating.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Exams/Past/2024 Midterm (소순범) Solution.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Exams/Past/2024 Midterm (소순범).pdf", nil),
        ("2026-3/EC4207 그래프 이론/Exercises/Exercise 1.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Lectures/05_Matchings.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Notes/2주차-1.md", #"""
            ---
            id: 6f1d2c4e-8a3b-4f5e-9c1d-2b7a8e0f3d41
            kind: rough
            ---

            # 2주차-1

            > [!definition] Matching
            > A set of pairwise non-adjacent edges.

            """#),
        ("2026-3/EC4207 그래프 이론/Syllabus/Syllabus.pdf", nil),
        ("2026-3/EC4207 그래프 이론/Textbooks/Introduction to Graph Theory (West).pdf", nil),
        ("2026-3/EC4321 로봇공학/.folio/course.json", #"""
            {
              "course" : {
                "categoryIds" : [],
                "codes" : [],
                "color" : "",
                "createdAt" : "2026-08-25T09:00:00.000Z",
                "credits" : 3,
                "folderRoles" : {},
                "gradingMode" : "relative",
                "id" : "C0000000-0000-4000-8000-000000000003",
                "instructorIds" : [],
                "memo" : "",
                "number" : "",
                "schedule" : [],
                "semesterId" : "5E4F1A00-0000-4000-8000-000000000003",
                "title" : "로봇공학",
                "titleEn" : "",
                "updatedAt" : "2026-08-25T09:00:00.000Z",
                "updatedBy" : "D0000000-0000-4000-8000-000000000001"
              },
              "materials" : [],
              "schemaVersion" : 1
            }

            """#),
        ("2026-3/EC4321 로봇공학/Assignments/Lab01/Lab1 Manual.pdf", nil),
        ("2026-3/EC4321 로봇공학/Assignments/Lab01/Lab1 Report.pdf", nil),
        ("2026-3/EC4321 로봇공학/Assignments/Project01/robot/.git/HEAD", nil),
        ("2026-3/EC4321 로봇공학/Assignments/Project01/robot/main.py", nil),
        ("2026-3/EC4321 로봇공학/Exams/Past/2025 Final.pdf", nil),
        ("2026-3/EC4321 로봇공학/Lectures/01_Intro.pdf", nil),
        ("2026-3/EC4321 로봇공학/Notes/1주차-1.md", #"""
            ---
            id: 9a4c1e7b-5d3f-4b2a-8e6c-7f0d2b9a1c55
            kind: rough
            ---

            # 1주차-1

            """#),
        ("2026-3/EC4321 로봇공학/Syllabus/Syllabus.pdf", nil),
        ("2026-3/_Admin/2026-3 강의실 배정.pdf", nil),
    ]
}
