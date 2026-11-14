import SwiftUI

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
