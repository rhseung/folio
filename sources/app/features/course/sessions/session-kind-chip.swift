import FolioActions
import FolioDomain
import SwiftUI

struct SessionKindChip: View {
    let kind: Session.Kind

    var body: some View {
        switch kind {
        case .cancelled: Chip(String(localized: .sessionsCancelled))
        case .makeup: Chip(String(localized: .sessionsMakeup), tone: .accent)
        case .lecture: EmptyView()
        }
    }
}
