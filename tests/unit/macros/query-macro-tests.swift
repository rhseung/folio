import FolioMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class QueryMacroTests: XCTestCase {
    let macros: [String: Macro.Type] = ["Query": QueryMacro.self]

    func refused(_ source: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        assertMacroExpansion(
            source, expandedSource: String(source.drop { $0 != "\n" }.dropFirst()),
            diagnostics: [DiagnosticSpec(message: message, line: 1, column: 1)], macros: macros, file: file, line: line)
    }

    func testReadsMakeNothingNew() {
        refused(
            """
            @Query("exam show", "시험 보기")
            struct ExamShow {
                @New var exam: Exam.ID
            }
            """, "읽기에는 새 항목이 없습니다: exam")
    }

    func testReadsTakeNoPatch() {
        refused(
            """
            @Query("exam show", "시험 보기")
            struct ExamShow {
                var title: Patch<String>
            }
            """, "읽기 입력은 Patch가 아닙니다: title")
    }
}
