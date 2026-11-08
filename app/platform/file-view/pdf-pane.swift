import SwiftUI

/// A PDF with its page strip: the PDF renderer of `FileView`. The controller drives it from outside (the bar's page,
/// zoom and search; a link's page), and the strip (`PageStrip`) cuts the thumbnails into the classes' progress (#147),
/// so whatever opens a lecture through `FileView`, the materials tab or a review's source, shows the same sections.
struct PDFPane: View {
    let controller: PDFController
    var thumbnails = true
    let workspace: Workspace
    /// The course and material the file is, for the strip's progress; nil for a file no course tracks.
    var course: UUID?
    var material: UUID?

    var body: some View {
        HStack(spacing: 0) {
            if thumbnails {
                PageStrip(controller: controller, workspace: workspace, course: course, material: material)
                Theme.Palette.lineSoft.frame(width: 1)
            }
            PDFKitView(controller: controller)
        }
    }
}
