import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@main
struct FolioMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [MarkerMacro.self, ActionMacro.self]
}
