import FolioMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// The mistakes @Action turns into compile errors. What it generates is checked by the actions that use it.
final class ActionMacroTests: XCTestCase {
    let macros: [String: Macro.Type] = ["Action": ActionMacro.self]

    func refused(_ source: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        assertMacroExpansion(source, expandedSource: String(source.drop { $0 != "\n" }.dropFirst()),
                             diagnostics: [DiagnosticSpec(message: message, line: 1, column: 1)], macros: macros, file: file, line: line)
    }

    func testRemovingNeedsAConfirmation() {
        refused("""
            @Action("exam rm", "시험 지우기", effect: .removes, done: "지웠습니다")
            struct ExamRemove {
                var exam: Exam.ID
            }
            """, "지우거나 옮기는 액션(.removes)은 confirm:으로 확인 문구를 줘야 합니다")
    }

    func testPlaceholdersNameAField() {
        refused("""
            @Action("exam rm", "시험 지우기", effect: .removes, confirm: "{exam}을 지웁니다", done: "{title}을 지웠습니다")
            struct ExamRemove {
                var exam: Exam.ID
            }
            """, "done의 {title}에 맞는 필드가 없습니다")
    }

    func testIdsSayWhatTheyPointAt() {
        refused("""
            @Action("exam set", "시험 바꾸기", done: "바꿨습니다")
            struct ExamSet {
                var exam: UUID
            }
            """, "exam: 맨 UUID 대신 가리키는 종류의 ID(예: Exam.ID)를 씁니다")
    }
}
