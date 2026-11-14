import FolioDomain
import Foundation
import Testing

@testable import Folio

// `folio note figure/widget render`는 노트의 색으로 그리지만 CLI는 앱의 테마를 링크하지 못해 생성한 사본을 쓴다.
// 사본이 낡으면 Claude가 노트에 없는 색으로 그린 그림을 보게 된다.
struct NoteThemeCopyTests {
    static let copy = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appending(path: "sources/cli/render/note-theme.swift")

    @MainActor static func source() -> String {
        let entries = CourseAccent.presets.map { preset in
            "        \(literal(preset.name)): \(literal(NoteWidgets.themeCSS(preset.accent))),"
        }
        return """
            // CLI가 앱의 테마를 링크하지 못해 tests/unit/app의 NoteThemeCopyTests가 앱의 테마에서 만든 사본이다. 손으로 고치지 않는다.
            // theme.swift나 NoteWidgets.themeCSS를 바꾸면 `TEST_RUNNER_FOLIO_WRITE_NOTE_THEME=1 mise run test-app`을 실행한다.
            enum NoteTheme {
                static let css: [String: String] = [
            \(entries.joined(separator: "\n"))
                ]
            }

            """
    }

    static func literal(_ text: String) -> String {
        "\"" + text.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"").replacing("\n", with: "\\n") + "\""
    }

    @MainActor @Test func theCLIDrawsInTheAppsColors() throws {
        let expected = Self.source()
        if ProcessInfo.processInfo.environment["FOLIO_WRITE_NOTE_THEME"] != nil {
            try expected.write(to: Self.copy, atomically: true, encoding: .utf8)
        }
        #expect(
            try String(contentsOf: Self.copy, encoding: .utf8) == expected,
            "run TEST_RUNNER_FOLIO_WRITE_NOTE_THEME=1 mise run test-app")
        #expect(CourseAccent.presets.contains { $0.name == CourseColor.neutral })
    }
}
