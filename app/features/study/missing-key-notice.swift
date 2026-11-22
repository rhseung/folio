import FolioDomain
import SwiftUI

struct MissingKeyNotice: View {
    @Environment(\.showSettings) private var showSettings

    var body: some View {
        NoticeCard(
            title: String(localized: .studyMissingKeyTitle), detail: String(localized: .studyMissingKeyDetail),
            systemImage: "key.fill"
        ) {
            Button(.studyMissingKeyOpenSettings) { showSettings(.claude) }.buttonStyle(.ghost)
        }
    }
}
