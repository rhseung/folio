import Foundation
import PDFKit
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// 채점에 보내는 손필기 답은 PNG만 쓴다. 사진과 PDF를 쪽마다 PNG로 바꾼다.
enum AnswerImages {
    static let types: [UTType] = [.image, .pdf]

    // PDF는 앞의 네 쪽만 보낸다. 답 한 문제가 그보다 길지 않고, 요청 크기를 줄이기 위해서다.
    static func png(from url: URL) -> [Data] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let pdf = PDFDocument(url: url) {
            return (0..<min(pdf.pageCount, 4)).compactMap { i in
                guard let page = pdf.page(at: i) else { return nil }
                let box = page.bounds(for: .mediaBox).size
                return png(page.thumbnail(of: CGSize(width: box.width * 2, height: box.height * 2), for: .mediaBox))
            }
        }
        #if os(macOS)
        return NSImage(contentsOf: url).flatMap(png).map { [$0] } ?? []
        #else
        return (try? Data(contentsOf: url)).flatMap(UIImage.init(data:)).flatMap(png).map { [$0] } ?? []
        #endif
    }

    #if os(macOS)
    private static func png(_ image: NSImage) -> Data? {
        image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?.representation(using: .png, properties: [:])
    }
    #else
    private static func png(_ image: UIImage) -> Data? { image.pngData() }
    #endif
}
