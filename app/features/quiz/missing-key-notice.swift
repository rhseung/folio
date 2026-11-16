import FolioDomain
import SwiftUI

struct MissingKeyNotice: View {
    @Environment(\.showSettings) private var showSettings

    var body: some View {
        NoticeCard(
            title: String(localized: .quizMissingKeyTitle), detail: String(localized: .quizMissingKeyDetail),
            systemImage: "key.fill"
        ) {
            Button(.quizMissingKeyOpenSettings) { showSettings(.claude) }.buttonStyle(.ghost)
        }
    }
}
