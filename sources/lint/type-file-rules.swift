import Foundation
import SwiftSyntax

extension Rules {
    static var oneTypePerFile: Rule {
        Rule(
            name: "one-type-per-file", strict: true,
            advice: "give each type used outside its file a file of its own named after it in kebab case (NoteFigureAdd: "
                + "note-figure-add.swift); private pieces stay in the file that uses them (AGENTS.md \"이름과 주석\")"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(under: "sources") where !file.path.hasSuffix("/main.swift") {
                let types = outsideTypes(in: file)
                let stem = ((file.path as NSString).lastPathComponent as NSString).deletingPathExtension
                if types.count > 1 {
                    hits.append(Hit("one-type-per-file", file, 1, types.map(\.name).joined(separator: ", ")))
                } else if let only = types.first, kebab(only.name) != stem {
                    hits.append(Hit("one-type-per-file", file, file.line(of: only.node), "\(only.name) in \(stem).swift"))
                }
            }
            return hits
        }
    }

    static var actionPath: Rule {
        Rule(
            name: "action-path", strict: true,
            advice: "put an @Action in sources/actions/<object>/[<sub>/]<its name in kebab case>.swift, the folders being the "
                + "front of its name (NoteFigureAdd: note/figure/note-figure-add.swift), so the list folio-gen writes follows"
        ) { code in
            var hits: [Hit] = []
            for file in code.files(under: "sources/actions") {
                for node in file.nodes(StructDeclSyntax.self) where node.attributes.contains(where: isActionAttribute) {
                    let name = node.name.text
                    let folders = file.path.dropFirst("sources/actions/".count).split(separator: "/").dropLast().map(String.init)
                    let front = folders.joined(separator: "-")
                    if folders.isEmpty || !(kebab(name) == front || kebab(name).hasPrefix(front + "-")) {
                        hits.append(Hit("action-path", file, file.line(of: node), "\(name) in \(folders.joined(separator: "/"))/"))
                    }
                }
            }
            return hits
        }
    }

    static func isActionAttribute(_ element: AttributeListSyntax.Element) -> Bool {
        element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "Action"
    }

    // 파일 밖에서 쓰는 최상위 타입. `#if`/`#else`로 같은 타입을 두 번 선언한 것은 하나로 센다.
    static func outsideTypes(in file: SourceFile) -> [(name: String, node: Syntax)] {
        var found: [(name: String, node: Syntax)] = []
        func visit(_ items: CodeBlockItemListSyntax) {
            for item in items {
                guard case .decl(let decl) = item.item else { continue }
                if let ifConfig = decl.as(IfConfigDeclSyntax.self) {
                    for clause in ifConfig.clauses {
                        if case .statements(let inner) = clause.elements { visit(inner) }
                    }
                    continue
                }
                guard let (name, modifiers) = nominal(decl) else { continue }
                if modifiers.contains(where: { ["private", "fileprivate"].contains($0.name.text) }) { continue }
                if !found.contains(where: { $0.name == name }) { found.append((name, Syntax(decl))) }
            }
        }
        visit(file.tree.statements)
        return found
    }

    static func nominal(_ decl: DeclSyntax) -> (String, DeclModifierListSyntax)? {
        if let d = decl.as(StructDeclSyntax.self) { return (d.name.text, d.modifiers) }
        if let d = decl.as(ClassDeclSyntax.self) { return (d.name.text, d.modifiers) }
        if let d = decl.as(EnumDeclSyntax.self) { return (d.name.text, d.modifiers) }
        if let d = decl.as(ActorDeclSyntax.self) { return (d.name.text, d.modifiers) }
        if let d = decl.as(ProtocolDeclSyntax.self) { return (d.name.text, d.modifiers) }
        return nil
    }
}

// 타입 이름을 파일 이름으로 바꾼다. 약어는 한 낱말로 읽고(`LMSClient`: lms-client), TeX처럼 대소문자가 섞인 고유 이름은
// 낱말 하나로 둔다. 이 표가 없으면 `SyncTeX`가 sync-te-x가 된다.
func kebab(_ name: String) -> String {
    var text = name
    for (proper, word) in [("LaTeX", "Latex"), ("SyncTeX", "Synctex"), ("TeX", "Tex"), ("AsciiMath", "Asciimath")] {
        text = text.replacingOccurrences(of: proper, with: word)
    }
    let characters = Array(text)
    var words: [String] = []
    var current = ""
    for (index, character) in characters.enumerated() {
        if index > 0, character.isUppercase {
            let previous = characters[index - 1]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if previous.isLowercase || previous.isNumber || (previous.isUppercase && next?.isLowercase == true) {
                words.append(current)
                current = ""
            }
        }
        current.append(character)
    }
    words.append(current)
    return words.map { $0.lowercased() }.joined(separator: "-")
}
