import Foundation

public struct WikiLink: Hashable, Sendable {
    public var target: String
    public var fragment: String?
    public var blockID: String?
    public var alias: String?
    public var isEmbed: Bool

    public var objectKind: String? {
        if let path = addressPath {
            let kind = path[0].lowercased()
            return WikiLink.objectKinds.contains(kind) ? kind : nil
        }
        guard let colon = target.firstIndex(of: ":") else { return nil }
        let kind = String(target[..<colon])
        return WikiLink.objectKinds.contains(kind) ? kind : nil
    }

    public var objectID: UUID? {
        if let path = addressPath { return objectKind != nil && path.count > 1 ? UUID(uuidString: path[1]) : nil }
        return objectKind.flatMap { UUID(uuidString: String(target.dropFirst($0.count + 1))) }
    }

    public var isAddress: Bool { addressPath != nil }

    public var isAppLink: Bool { objectKind != nil || isAddress }

    static let scheme = "folio://"

    var addressPath: [String]? {
        guard target.count > Self.scheme.count, target.prefix(Self.scheme.count).lowercased() == Self.scheme else { return nil }
        return target.dropFirst(Self.scheme.count).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    }

    public var noteID: UUID? { objectKind == "note" ? objectID : nil }

    // FolioMarkdown은 다른 Folio 모듈에 기대지 않으므로 FolioDomain `AppLink`의 종류 이름을 여기에 되풀이한다.
    // `AppLinkWikiTests`가 양쪽이 맞는지 확인한다.
    public static let objectKinds: Set<String> = [
        "semester", "course", "session", "unit", "note", "material", "assignment", "exam", "card", "problem-set", "person", "recording",
    ]

    public static var pattern: Regex<(Substring, Substring, Substring, Substring?, Substring?, Substring?)> {
        #/(!?)\[\[([^\]\|#]+?)(?:#(\^?)([^\]\|]*?))?(?:\\?\|([^\]]*))?\]\]/#
    }

    public init(_ m: Regex<(Substring, Substring, Substring, Substring?, Substring?, Substring?)>.Match) {
        target = String(m.2).trimmingCharacters(in: .whitespaces)
        let isBlock = m.3 == "^"
        blockID = isBlock ? m.4.map(String.init) : nil
        fragment = isBlock ? nil : m.4.map(String.init)
        alias = m.5.map(String.init)
        isEmbed = m.1 == "!"
        if isAddress, let f = fragment { fragment = f.removingPercentEncoding ?? f }
    }

    public var href: String {
        let fragment = blockID.map { "#^" + $0 } ?? fragment.map { "#" + $0 } ?? ""
        if isAddress { return target + fragment }
        if let kind = objectKind {
            return "folio://\(kind)/\(target.dropFirst(kind.count + 1))\(fragment)"
        }
        return "folio://note/\(target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? target)\(fragment)"
    }

    public static func all(in text: String) -> [WikiLink] {
        text.matches(of: pattern).map(WikiLink.init)
    }

    static func separator(_ link: Substring, _ alias: Substring) -> String {
        link[..<alias.startIndex].hasSuffix("\\|") ? "\\|" : "|"
    }

    public static func retargeted(_ text: String, from old: String, to new: String) -> String {
        text.replacing(pattern) { m in
            let target = m.2.trimmingCharacters(in: .whitespaces)
            guard target.caseInsensitiveCompare(old) == .orderedSame else { return String(m.0) }
            let fragment = m.4.map { "#\(m.3 ?? "")\($0)" } ?? ""
            return "\(m.1)[[\(new)\(fragment)\(m.5.map { separator(m.0, $0) + $0 } ?? "")]]"
        }
    }

    public static func retitled(_ text: String, note id: UUID, from old: String, to new: String) -> String {
        text.replacing(pattern) { m in
            guard WikiLink(m).noteID == id, let alias = m.5, alias.trimmingCharacters(in: .whitespaces) == old else { return String(m.0) }
            let fragment = m.4.map { "#\(m.3 ?? "")\($0)" } ?? ""
            return "\(m.1)[[\(m.2)\(fragment)\(separator(m.0, alias))\(new)]]"
        }
    }
}
