import Markdown

public struct ParsedNote {
    public var frontmatter: Frontmatter
    public var body: String
    /// swift-markdown tree of the math-protected body.
    public var document: Document
    public var links: [WikiLink]
    public var blockIDs: [String]
    /// The body line each line of `document` came from.
    var sourceLine: [Int]
    let bodyLines: [Substring]

    public init(_ text: String) {
        (frontmatter, body) = Frontmatter.split(text)
        let protected = MathProtection.protectMapped(body)
        document = Document(parsing: DraftItem.mask(protected.text))
        sourceLine = protected.origin
        bodyLines = body.split(separator: "\n", omittingEmptySubsequences: false)
        links = WikiLink.all(in: body)
        blockIDs = body.matches(of: /\s\^([A-Za-z0-9-]+)\s*$/.anchorsMatchLineEndings()).map { String($0.1) }
    }

    /// The body lines a block was written on, 1-based.
    public func lines(of node: Markup) -> ClosedRange<Int>? {
        guard let range = node.range, range.upperBound.line <= sourceLine.count else { return nil }
        let first = sourceLine[range.lowerBound.line - 1]
        var last = sourceLine[range.upperBound.line - 1]
        guard first >= 1, first <= last, last <= bodyLines.count else { return nil }
        // A list's range runs on to the blank line after it.
        while last > first, bodyLines[last - 1].allSatisfy(\.isWhitespace) { last -= 1 }
        return first...last
    }

    public func source(_ lines: ClosedRange<Int>) -> String {
        bodyLines[(lines.lowerBound - 1)...(lines.upperBound - 1)].joined(separator: "\n")
    }

    public var text: String {
        frontmatter.render(body: body)
    }
}
