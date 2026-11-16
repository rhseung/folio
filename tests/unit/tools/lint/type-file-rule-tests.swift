import FolioLint
import Testing

private func found(_ files: [String: String], _ check: String) -> [String] {
    let code = Codebase(files: files)
    return Rules.all.filter { $0.name == check }.flatMap { $0.hits(in: code) }.map(\.key).sorted()
}

@Suite struct OneTypePerFileTests {
    @Test func twoOutsideTypesInOneFile() {
        let files = ["sources/domain/grades/grade.swift": "struct Grade {}\nenum GradeScale {}"]
        #expect(found(files, "one-type-per-file") == ["Grade, GradeScale"])
    }

    @Test func theFileIsNamedAfterItsType() {
        let files = [
            "sources/lms/client.swift": "struct LMSClient {}",
            "sources/lms/lms-pages.swift": "enum LMSPages {}",
            "app/platform/synctex-view.swift": "final class SyncTeXView {}",
        ]
        #expect(found(files, "one-type-per-file") == ["LMSClient in client.swift"])
    }

    @Test func privatePiecesExtensionsAndPlatformTwinsDoNotCount() {
        let source = """
            #if os(macOS)
            struct TitleRowEdges {}
            #else
            struct TitleRowEdges {}
            #endif
            private struct Row {}
            fileprivate enum Width {}
            extension String { var trimmed: String { self } }
            """
        let files = [
            "app/platform/title-row-edges.swift": source,
            "sources/tools/folio/main.swift": "struct Command {}\nstruct Other {}",
            "tests/unit/domain/grade-tests.swift": "struct GradeTests {}\nstruct GPATests {}",
        ]
        #expect(found(files, "one-type-per-file").isEmpty)
    }
}

@Suite struct ActionPathTests {
    @Test func actionsLiveInTheAreaOfTheirName() {
        let files = [
            "sources/actions/notes/figure/note-figure-add.swift": "@Action struct NoteFigureAdd {}",
            "sources/actions/notes/note-add.swift": "@Action struct NoteAdd {}",
            "sources/actions/exams/exam-add.swift": "@Action struct ExamAdd {}",
            "sources/actions/grades/component/component-add.swift": "@Action struct ComponentAdd {}",
            "sources/actions/sessions/class-start.swift": "@Action struct ClassStart {}",
            "sources/actions/courses/class-time-set.swift": "@Action struct ClassTimeSet {}",
            "sources/actions/notes/exam-scope.swift": "@Action struct ExamScope {}",
            "sources/actions/score-add.swift": "@Action struct ScoreAdd {}",
            "sources/actions/exams/exam-show.swift": "@Query struct ExamShow {}",
            "sources/actions/notes/exam-summary-show.swift": "@Query struct ExamSummaryShow {}",
            "sources/actions/notes/widget/note-figure-list.swift": "@Query struct NoteFigureList {}",
            "sources/actions/exam/exam-list.swift": "@Query struct ExamList {}",
            "sources/actions/notes/notes/note-lookup.swift": "enum NoteLookup {}",
        ]
        #expect(
            found(files, "action-path") == [
                "ExamList in exam/", "ExamScope in notes/", "ExamSummaryShow in notes/", "NoteFigureList in notes/widget/",
                "ScoreAdd in /",
            ])
    }

    @Test func theLongestFrontPicksTheArea() {
        #expect(Area.of("class-time-set") == "courses")
        #expect(Area.of("class-start") == "sessions")
        #expect(Area.of("problem-set-save") == "study")
        #expect(Area.of("lms-accept") == "lms")
        #expect(Area.of("classroom") == nil)
    }
}
