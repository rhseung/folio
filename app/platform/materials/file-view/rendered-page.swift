import CoreGraphics
import PDFKit

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct RenderedPage: @unchecked Sendable {
    let image: CGImage
}
