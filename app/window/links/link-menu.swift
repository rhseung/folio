import FolioDomain
import FolioMarkdown
import FolioStorage
import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct LinkMenu: View {
    let link: AppLink
    var course: UUID?
    var copies = true
    var trailing = false
    @Environment(\.openLink) private var openLink
    @Environment(\.supportsMultipleWindows) private var multipleWindows

    var body: some View {
        if trailing {
            Divider()
            ShareMenu(link: link, course: course)
        } else {
            openings
            if copies {
                Divider()
                Button(.linkCopy, systemImage: "link") { copyLink(link) }
            }
        }
    }

    var openings: some View {
        ForEach(LinkMenu.placements(multipleWindows: multipleWindows), id: \.self) { placement in
            Button(placement.title, systemImage: placement.symbol) { openLink(link, in: placement, course: course) }
        }
    }

    static func placements(multipleWindows: Bool) -> [LinkPlacement] {
        multipleWindows ? LinkPlacement.allCases : [.here, .beside]
    }
}
