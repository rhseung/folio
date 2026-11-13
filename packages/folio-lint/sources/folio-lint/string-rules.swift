import SwiftSyntax

extension Rules {
    // AGENTS.md "문자열 키": screen copy lives in the string catalog as a key.
    static var uiString: Rule {
        Rule(
            name: "ui-string",
            advice: "put screen copy in app/resources/Localizable.xcstrings as a key; mark data strings `// strings: data, <why>`"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(under: "app") where !isDebugFile(file.path) {
                let marks = file.dataMarks()
                for literal in file.nodes(StringLiteralExprSyntax.self) {
                    let start = literal.positionAfterSkippingLeadingTrivia.utf8Offset
                    if marks.contains(where: { $0.contains(start) }) || file.debugOnly(literal) { continue }
                    let text = literal.plainText
                    if hasHangul(text) || (isScreenCopy(literal) && hasWord(text)) {
                        hits.append(Hit("ui-string", file, file.line(of: literal), "\"\(text)\""))
                    }
                }
            }
            return hits
        }
    }

    // AGENTS.md "단일 출처": folder and file names come from standard-layout.swift alone.
    static var layoutName: Rule {
        Rule(
            name: "layout-name",
            advice: "folder and file names come from FolioDomain's standard-layout.swift (Term, SemesterFolder, CourseFolder)"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(
                under: "app", "packages/folio-core/sources", "packages/folio-markdown/sources",
                "packages/folio-ai/sources")
            where !file.path.hasSuffix("/standard-layout.swift") && !file.path.contains("/folio-fixtures/") {
                for literal in file.nodes(StringLiteralExprSyntax.self) where layoutNames.contains(literal.plainText) {
                    hits.append(Hit("layout-name", file, file.line(of: literal), "\"\(literal.plainText)\""))
                }
            }
            return hits
        }
    }

    static let layoutNames: Set<String> = [
        "Syllabus", "Lectures", "Exercises", "Textbooks", "Inherited", "Assignments", "Exams", "Study", "Notes", "Ink",
        "Recordings", "Archive", ".folio", "_Admin", "_Credited", "course.json", "transcript.json", "catalog.json",
        "settings.json", "moves.jsonl",
    ]

    // An English word is copy only where SwiftUI shows its first argument; anywhere else it is an identifier, a key or
    // a format. Hangul is copy everywhere.
    static let copyViews: Set<String> = [
        "Text", "Button", "Label", "Toggle", "Picker", "Section", "Menu", "TextField", "SecureField", "LabeledContent",
        "GroupBox", "DisclosureGroup", "Link", "NavigationLink", "ContentUnavailableView", "LocalizedStringKey",
    ]
    static let copyModifiers: Set<String> = [
        "help", "navigationTitle", "accessibilityLabel", "accessibilityHint", "alert", "confirmationDialog", "badge",
        "searchable",
    ]

    static func isScreenCopy(_ literal: StringLiteralExprSyntax) -> Bool {
        guard let argument = literal.parent?.as(LabeledExprSyntax.self),
            let arguments = argument.parent?.as(LabeledExprListSyntax.self), arguments.first?.id == argument.id,
            let call = arguments.parent?.as(FunctionCallExprSyntax.self)
        else { return false }
        let label = argument.label?.text
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            return label == nil ? copyViews.contains(name) : name == "String" && label == "localized"
        }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self), label == nil {
            let name = member.declName.baseName.text
            return copyViews.contains(name) || copyModifiers.contains(name)
        }
        return false
    }

    static func hasWord(_ text: String) -> Bool {
        var run = 0
        for character in text {
            run = character.isASCII && character.isLetter ? run + 1 : 0
            if run == 2 { return true }
        }
        return false
    }
}
