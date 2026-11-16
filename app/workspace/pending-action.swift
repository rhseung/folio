import FolioActions
import SwiftUI

struct PendingAction: Identifiable {
    let id = UUID()
    let question: String
    let refusal: String?
    let button: LocalizedStringResource
    let role: ButtonRole?
    let perform: @MainActor () -> Void
}
