import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@main
struct FolioMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [MarkerMacro.self, ActionMacro.self]
}

/// `@Arg`, `@New`, `@Off` and `@Hidden` add nothing themselves; `@Action` reads them off the fields it describes.
public struct MarkerMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol,
                                 in context: some MacroExpansionContext) throws -> [DeclSyntax] { [] }
}
