import Foundation

public struct CompletionItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String?
    public var symbol: String?
    public var preview: String?
    public var previewAsciiMath: Bool
    public var keywords: [String]
    public var body: String
    public var block: Bool
    public var caret: Int?
    public var continues: Bool
    public var category: MathCategory?

    public init(
        id: String, title: String, detail: String? = nil, symbol: String? = nil, preview: String? = nil,
        previewAsciiMath: Bool = false, keywords: [String] = [], body: String, block: Bool = false,
        caret: Int? = nil, continues: Bool = false, category: MathCategory? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.preview = preview
        self.previewAsciiMath = previewAsciiMath
        self.keywords = keywords
        self.body = body
        self.block = block
        self.caret = caret
        self.continues = continues
        self.category = category
    }
}
