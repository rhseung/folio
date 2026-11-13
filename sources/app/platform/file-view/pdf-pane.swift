import SwiftUI

/// The strip cuts the thumbnails into the classes' progress here (#147), so whatever opens a lecture through
/// `FileView`, the materials tab or a review's source, shows the same sections.
struct PDFPane: View {
    let controller: PDFController
    var thumbnails = true
    let strip: PageStripModel

    var body: some View {
        HStack(spacing: 0) {
            if thumbnails {
                PageStrip(controller: controller, model: strip)
                Theme.Palette.lineSoft.frame(width: 1)
            }
            PDFKitView(controller: controller)
        }
    }
}
