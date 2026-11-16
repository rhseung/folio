import FolioDomain
import SwiftUI

enum TranscriptionContextText {
    static func pages(_ slides: LecturePages) -> String {
        let name = (slides.path as NSString).lastPathComponent
        let range: String? =
            switch (slides.first, slides.last) {
            case let (first?, last?) where first == last: String(localized: .recordingContextPage(first))
            case let (first?, last?): String(localized: .recordingContextPages(first, last))
            case let (first?, nil): String(localized: .recordingContextPagesFrom(first))
            case let (nil, last?): String(localized: .recordingContextPagesTo(last))
            case (nil, nil): nil
            }
        return range.map { "\(name) \($0)" } ?? name
    }

    static func summary(_ context: TranscriptionContext) -> String {
        guard let first = context.slides.first else { return fallback(context) }
        let slides =
            context.slides.count == 1 ? pages(first) : String(localized: .recordingContextMoreFiles(pages(first), context.slides.count - 1))
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
