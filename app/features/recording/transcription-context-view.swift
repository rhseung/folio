import FolioDomain
import SwiftUI

/// How a transcription context reads, for the sidebar card's transcript and the player alike.
enum TranscriptionContextText {
    static func pages(_ slides: LecturePages) -> String {
        let name = (slides.path as NSString).lastPathComponent
        let range: String? = switch (slides.first, slides.last) {
        case let (first?, last?) where first == last: String(localized: .recordingContextPage(first))
        case let (first?, last?): String(localized: .recordingContextPages(first, last))
        case let (first?, nil): String(localized: .recordingContextPagesFrom(first))
        case let (nil, last?): String(localized: .recordingContextPagesTo(last))
        case (nil, nil): nil
        }
        return range.map { "\(name) \($0)" } ?? name
    }

    /// Without slides it says what was used instead, in plain gray: a class with no units can be meant that way.
    static func summary(_ context: TranscriptionContext) -> String {
        guard let first = context.slides.first else { return fallback(context) }
        let slides = context.slides.count == 1 ? pages(first) : String(localized: .recordingContextMoreFiles(pages(first), context.slides.count - 1))
        var parts = [slides]
        if !context.topics.isEmpty { parts.append(String(localized: .recordingContextTopicsCount(context.topics.count))) }
        if !context.terms.isEmpty { parts.append(String(localized: .recordingContextTermsCount(context.terms.count))) }
        return parts.joined(separator: " · ")
    }

    static func fallback(_ context: TranscriptionContext) -> String {
        String(localized: context.topics.isEmpty ? .recordingContextNothing : .recordingContextNoSlides)
    }

    static func source(_ source: TranscriptionContext.Source?) -> String? {
        switch source {
        case .recording: String(localized: .recordingContextSourceRecording)
        case .session: String(localized: .recordingContextSourceSession)
        case .tagged: String(localized: .recordingContextSourceTagged)
        case .week: String(localized: .recordingContextSourceWeek)
        case nil: nil
        }
    }
}

/// The slides, topics and terms of a context as rows of a `Card`. `link` leads to where lecture files are linked.
struct TranscriptionContextRows: View {
    let context: TranscriptionContext
    /// Whether the terms have been read; until then the row says so instead of "none".
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
