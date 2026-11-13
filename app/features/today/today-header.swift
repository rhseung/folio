import FolioDomain
import SwiftUI

struct TodayHeader: View {
    let model: TodayModel
    let summary: TodaySummary
    let classes: [TodayModel.RibbonClass]
    let reviews: TodayModel.Reviews

    var body: some View {
        // The counts include ended classes, so the line moves on as the day does.
        let now = model.workspace.liveNow
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: Theme.Space.xl) {
                heading(now: now)
                Spacer(minLength: 0)
                week
            }
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                heading(now: now)
                week
            }
        }
        // The page's own gaps fit block to block; the date sits apart from the day below it, as in the mockup.
        .padding(.top, Theme.Space.l)
        .padding(.bottom, Theme.Space.m)
    }

    func heading(now: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(model.heading(summary, now: now)).font(Theme.Typeface.pageTitle)
            let pieces = model.summaryLine(classes: classes, summary: summary, reviews: reviews, now: now)
            // One count a line where the line doesn't fit: cut short, it dropped the counts at its end.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.m) {
                    ForEach(Array(pieces.enumerated()), id: \.offset) { i, piece in
                        if i > 0 { CourseDot(color: Theme.Palette.lineStrong, size: Theme.Space.xs) }
                        Text(Self.counts(piece.text, urgent: piece.urgent))
                    }
                }
                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in Text(Self.counts(piece.text, urgent: piece.urgent)) }
                }
            }
            .font(Theme.Typeface.bodyLarge)
            .foregroundStyle(Theme.Palette.textSecondary)
            .lineLimit(1)
        }
        // Only its height: fixed in width too, the counts line could never fold and pushed a narrow pane out.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The bold runs of a count line in full text color, or danger when the count needs doing today.
    static func counts(_ text: AttributedString, urgent: Bool) -> AttributedString {
        var text = text
        for run in text.runs where run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
            text[run.range].foregroundColor = urgent ? Theme.Palette.danger : Theme.Palette.text
        }
        return text
    }

    var week: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(model.week(around: summary.studyDay)) { day in
                VStack(spacing: Theme.Space.xs) {
                    Text(day.weekday).font(Theme.Typeface.label)
                    Text("\(day.day.day)").font(Theme.Typeface.bodyStrong).monospacedDigit()
                    HStack(spacing: Theme.Space.xxs) {
                        ForEach(day.courses.prefix(4), id: \.self) { CourseDot(color: model.workspace.accent($0).color, size: Theme.Space.tight) }
                    }
                    .frame(height: Theme.Space.tight)
                }
                .foregroundStyle(day.isToday ? Theme.Palette.text : Theme.Palette.textTertiary)
                .frame(width: 40)
                .padding(.vertical, Theme.Space.s)
                .background {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: Theme.Radius.control).fill(Theme.Palette.card)
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.control).strokeBorder(Theme.Palette.line))
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
