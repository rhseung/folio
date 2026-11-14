import CoreImage
import Observation
import PDFKit
import SwiftUI

#if os(macOS)
extension PDFKitView: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFView {
        controller.restore()
        PDFLinks.attach(to: controller.view, opener: context.environment.openLink)
        return controller.view
    }
    func updateNSView(_ view: PDFView, context: Context) {}
}
#else
extension PDFKitView: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFView {
        controller.restore()
        PDFLinks.attach(to: controller.view, opener: context.environment.openLink)
        return controller.view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}
#endif
