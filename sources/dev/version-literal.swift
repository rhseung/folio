import Foundation
import SwiftParser
import SwiftSyntax

// 버전은 `FolioVersion.marketing`의 문자열 리터럴 하나다. 읽기와 올리기가 같은 구문 노드를 찾으므로, 그 줄의 모양
// (공백, 주석, 다른 선언)이 바뀌어도 둘이 어긋나지 않는다.
enum VersionLiteral {
    static let path = "sources/domain/shared/app/folio-version.swift"

    static func read(_ source: String) -> String? {
        literal(in: Parser.parse(source: source))?.representedLiteralValue
    }

    static func replacing(_ source: String, with version: String) -> String? {
        let tree = Parser.parse(source: source)
        guard let node = literal(in: tree) else { return nil }
        let start = node.positionAfterSkippingLeadingTrivia.utf8Offset
        let end = node.endPositionBeforeTrailingTrivia.utf8Offset
        var bytes = Array(source.utf8)
        bytes.replaceSubrange(start..<end, with: Array("\"\(version)\"".utf8))
        return String(bytes: bytes, encoding: .utf8)
    }

    static func literal(in tree: SourceFileSyntax) -> StringLiteralExprSyntax? {
        for item in tree.statements {
            guard let type = item.item.as(EnumDeclSyntax.self), type.name.text == "FolioVersion" else { continue }
            for member in type.memberBlock.members {
                guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
                for binding in variable.bindings where binding.pattern.trimmedDescription == "marketing" {
                    return binding.initializer?.value.as(StringLiteralExprSyntax.self)
                }
            }
        }
        return nil
    }

    static func file() throws -> String { try String(contentsOf: URL(filePath: path), encoding: .utf8) }
}
