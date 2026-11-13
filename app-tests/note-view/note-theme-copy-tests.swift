import FolioDomain
import Foundation
import Testing
@testable import Folio

/// `folio note figure/widget render` draws a page in the note's colors, but the CLI can't link the app's theme, so it
/// keeps a generated copy. A stale copy would show Claude a figure in colors the note no longer has.
struct NoteThemeCopyTests {
    static let copy = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "packages/folio-core/sources/folio-cli/render/note-theme.swift")

    @MainActor static func source() -> String {
        let entries = CourseAccent.presets.map { preset in
            "        \(literal(preset.name)): \(literal(NoteWidgets.themeCSS(preset.accent))),"
        }
        return """
        // Written by NoteThemeCopyTests in app-tests from the app's theme, which the CLI can't link. Don't edit by hand: after
        // changing theme.swift or NoteWidgets.themeCSS, run `TEST_RUNNER_FOLIO_WRITE_NOTE_THEME=1 mise run test-app`.
        enum NoteTheme {
            /// `NoteWidgets.themeCSS` for each course color preset, by name.
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
        #expect(try String(contentsOf: Self.copy, encoding: .utf8) == expected,
                "run TEST_RUNNER_FOLIO_WRITE_NOTE_THEME=1 mise run test-app")
        #expect(CourseAccent.presets.contains { $0.name == CourseColor.neutral })
    }
}
