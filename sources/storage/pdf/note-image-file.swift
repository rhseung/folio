import FolioDomain
import FolioMarkdown
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

public struct NoteImageFile: Equatable, Sendable {
    public var written: String
    public var path: String?

    public init(written: String, path: String?) {
        self.written = written
        self.path = path
    }
}
