import SwiftSyntax

extension Rules {
    static var layer: Rule {
        Rule(
            name: "layer",
            advice: "keep each layer to its job (AGENTS.md \"레이어\"): packages draw no UI, FolioDomain and FolioMarkdown don't "
                + "touch the disk, screens reach files through FolioActions or their model's Workspace"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(under: "sources", except: "sources/app") {
                for declaration in file.nodes(ImportDeclSyntax.self) {
                    guard let module = declaration.path.first?.name, module.text == "SwiftUI" else { continue }
                    hits.append(Hit("layer", file, file.line(of: module), "import SwiftUI"))
                }
            }
            for file in code.files(under: "sources/domain", "sources/markdown") {
                hits += diskAccess(in: file)
            }
            for file in code.files(under: "sources/app/features") where !isDebugFile(file.path) {
                for token in file.tokens where token.tokenKind == .identifier("FileManager") && !file.debugOnly(token) {
                    hits.append(Hit("layer", file, file.line(of: token), "FileManager in a screen"))
                }
            }
            return hits
        }
    }

    static let diskTypes: Set<String> = ["FileManager", "NSFileCoordinator", "FileHandle", "NSFileVersion"]
    static let contentsTypes: Set<String> = ["Data", "String", "NSData", "NSString"]

    static func diskAccess(in file: SourceFile) -> [Hit] {
        var hits: [Hit] = []
        for token in file.tokens {
            guard case .identifier(let name) = token.tokenKind else { continue }
            if diskTypes.contains(name) {
                hits.append(Hit("layer", file, file.line(of: token), "disk: \(name)"))
            } else if name == "atomically", token.nextToken(viewMode: .sourceAccurate)?.tokenKind == .colon {
                hits.append(Hit("layer", file, file.line(of: token), "disk: atomically:"))
            }
        }
        for call in file.nodes(FunctionCallExprSyntax.self) {
            guard let label = call.arguments.first?.label?.text else { continue }
            if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self),
                contentsTypes.contains(reference.baseName.text), label == "contentsOf" || label == "contentsOfFile"
            {
                hits.append(Hit("layer", file, file.line(of: call), "disk: \(reference.baseName.text)(\(label):"))
            }
            if let member = call.calledExpression.as(MemberAccessExprSyntax.self), member.declName.baseName.text == "write",
                label == "to"
            {
                hits.append(Hit("layer", file, file.line(of: member.declName), "disk: .write(to:"))
            }
        }
        return hits
    }
}
