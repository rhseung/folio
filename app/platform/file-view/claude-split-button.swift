import FolioDomain
import PDFKit
import SwiftUI

struct ClaudeSplitButton: View {
    let asking: Bool
    let retry: () -> Void
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: retry) {
            HStack(spacing: Theme.Space.tight) {
                if asking {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "sparkle").foregroundStyle(accent.color)
                }
                Text(.lectureClaudeRetry)
            }
        }
        .buttonStyle(.ghost)
        .disabled(asking)
        .help(Text(.lectureClaudeHelp))
    }
}
