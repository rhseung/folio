import FolioDomain
import SwiftUI

struct TranscriptionContextRows: View {
    let context: TranscriptionContext
    var termsRead = true
    var link: (() -> Void)?

    var body: some View {
        CardRow {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(.recordingContextSlides)
                if let source = TranscriptionContextText.source(context.source) {
                    Text(source).font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            Spacer(minLength: Theme.Space.m)
            if context.slides.isEmpty {
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    Text(TranscriptionContextText.fallback(context)).foregroundStyle(Theme.Palette.textSecondary)
                    if let link {
                        Button(.recordingContextLink, action: link).buttonStyle(.ghost).help(Text(.recordingContextLinkHelp))
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: Theme.Space.xxs) {
                    ForEach(Array(context.slides.enumerated()), id: \.offset) { _, slides in
                        Text(TranscriptionContextText.pages(slides)).lineLimit(1).truncationMode(.middle).help(slides.path)
                    }
                }
            }
        }
        CardRow {
            Text(.recordingContextTopics)
            Spacer(minLength: Theme.Space.m)
            Text(context.topics.isEmpty ? String(localized: .recordingContextNone) : context.topics.joined(separator: " · "))
                .foregroundStyle(context.topics.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.text)
                .multilineTextAlignment(.trailing)
        }
        CardRow(last: true) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(.recordingContextTerms(context.terms.count))
                Group {
                    if !termsRead {
                        Text(.recordingContextReading)
                    } else if context.terms.isEmpty {
                        Text(.recordingContextNone)
                    } else {
                        Text(context.terms.joined(separator: ", ")).textSelection(.enabled)
                    }
                }
                .font(Theme.Typeface.caption).foregroundStyle(Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
