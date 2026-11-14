import FolioDomain
import FolioMarkdown
import FolioStorage
import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct OpenLinkAction {
    var handler: @MainActor (AppLink, LinkPlacement, UUID?) -> Void = { _, _, _ in }

    @MainActor func callAsFunction(_ link: AppLink, in placement: LinkPlacement = .here, course: UUID? = nil) {
        handler(link, placement, course)
    }
}
