import SwiftUI

/// A PDF with its page column: the PDF renderer of `FileView`. The controller drives it from outside (the bar's page,
/// zoom and search; a link's page), so whatever is laid over the pages later (a progress range on the thumbnails,
/// #147) takes the same controller and stays out of the file view.
struct PDFPane: View {
    let controller: PDFController
    var thumbnails = true

    var body: some View {
        HStack(spacing: 0) {
            if thumbnails {
                PDFThumbnails(controller: controller).frame(width: 128)
                Theme.Palette.lineSoft.frame(width: 1)
            }
            PDFKitView(controller: controller)
        }
    }
}
