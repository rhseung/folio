import FolioActions
import FolioDomain
import SwiftUI

struct SessionKindChip: View {
    let kind: Session.Kind

    var body: some View {
        switch kind {
        case .cancelled: Badge(String(localized: .sessionsCancelled))
        case .makeup: Badge(String(localized: .sessionsMakeup), tone: .accent)
        case .lecture: EmptyView()
        }
    }
}
