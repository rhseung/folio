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
            "sources/app/platform/synctex-view.swift": "final class SyncTeXView {}",
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
            "sources/app/platform/title-row-edges.swift": source,
            "sources/command/main.swift": "struct Command {}\nstruct Other {}",
            "tests/unit/domain/grade-tests.swift": "struct GradeTests {}\nstruct GPATests {}",
        ]
        #expect(found(files, "one-type-per-file").isEmpty)
    }
}

@Suite struct ActionPathTests {
    @Test func actionsLiveInTheFoldersOfTheirName() {
        let files = [
            "sources/actions/note/figure/note-figure-add.swift": "@Action struct NoteFigureAdd {}",
            "sources/actions/note/note-add.swift": "@Action struct NoteAdd {}",
            "sources/actions/exam/exam-add.swift": "@Action struct ExamAdd {}",
            "sources/actions/note/exam-scope.swift": "@Action struct ExamScope {}",
            "sources/actions/score-add.swift": "@Action struct ScoreAdd {}",
            "sources/actions/note/notes/note-lookup.swift": "enum NoteLookup {}",
        ]
        #expect(found(files, "action-path") == ["ExamScope in note/", "ScoreAdd in /"])
    }
}
