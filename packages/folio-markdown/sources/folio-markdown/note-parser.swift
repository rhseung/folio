import Markdown

public struct ParsedNote {
    public var frontmatter: Frontmatter
    public var body: String
    /// swift-markdown tree of the math-protected body.
    public var document: Document
    public var links: [WikiLink]
    public var blockIDs: [String]

    public init(_ text: String) {
        (frontmatter, body) = Frontmatter.split(text)
        document = Document(parsing: MathProtection.protect(body))
        links = WikiLink.all(in: body)
        blockIDs = body.matches(of: /\s\^([A-Za-z0-9-]+)\s*$/.anchorsMatchLineEndings()).map { String($0.1) }
    }

    public var text: String {
        frontmatter.render(body: body)
    }
}
