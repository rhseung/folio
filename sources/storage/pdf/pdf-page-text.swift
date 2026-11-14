import FolioDomain
import FolioMarkdown
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public struct PDFPageText: Equatable, Sendable {
    public var page: Int
    public var title: String?
    public var text: String
    public var words: Int
    public var figures: Int

    public init(page: Int, title: String? = nil, text: String, words: Int, figures: Int) {
        self.page = page
        self.title = title
        self.text = text
        self.words = words
        self.figures = figures
    }
}
