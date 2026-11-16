import FolioDomain
import FolioMarkdown
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ClaudeJPEG {
    static func of(_ image: CGImage, edge: Int) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(
            dest, image,
            [
                kCGImageDestinationLossyCompressionQuality: 0.8,
                kCGImageDestinationImageMaxPixelSize: edge,
            ] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
