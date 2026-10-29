import FolioMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

final class MarkerMacroTests: XCTestCase {
    let macros: [String: Macro.Type] = ["Arg": MarkerMacro.self, "New": MarkerMacro.self, "Off": MarkerMacro.self]

    func testMarkersLeaveTheFieldAsWritten() {
        assertMacroExpansion(
            """
            struct A {
                @Arg var course: Course.ID
                @Off("undo") var done = true
            }
            """,
            expandedSource: """
            struct A {
                var course: Course.ID
                var done = true
            }
            """,
            macros: macros)
    }
}
