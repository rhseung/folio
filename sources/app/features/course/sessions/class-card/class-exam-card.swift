import FolioActions
import FolioDomain
import SwiftUI

struct ClassExamCard: ViewModifier {
    let model: SessionsModel
    let exams: [Exam]
    let now: Date
    static let tuck: CGFloat = 8

    func body(content: Content) -> some View {
        if exams.isEmpty {
            content
        } else {
            VStack(spacing: 0) {
                card
                content
                    .background {
                        RoundedRectangle(cornerRadius: ClassCard.radius).fill(.clear).shadow(color: .black.opacity(0.06), radius: 3, y: -2)
                    }
                    .padding(.top, -Self.tuck)
            }
            .padding(.top, Theme.Space.s)
        }
    }

    var card: some View {
        VStack(spacing: Theme.Space.xxs) {
            ForEach(exams) { exam in
                HStack(spacing: Theme.Space.l) {
                    Image(systemName: "flag").font(Theme.Typeface.caption.weight(.semibold)).frame(width: ClassCard.tile)
                    HStack(spacing: Theme.Space.s) {
                        Text(exam.title).font(Theme.Typeface.bodyStrong.weight(.bold)).lineLimit(1).fixedSize()
                        if let time = model.examTime(exam) {
                            Text(time).font(Theme.Typeface.caption).monospacedDigit().lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let days = model.examDays(exam, now: now) { Chip(days == 0 ? "D-day" : "D-\(days)", tone: .danger, solid: true) }
                }
                .frame(minHeight: 24)
            }
        }
        .foregroundStyle(Theme.Palette.danger)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.s + Self.tuck)
        .padding(.leading, Theme.Space.xs)
        .padding(.trailing, ClassCard.tile)
        .background(Theme.Palette.dangerFill, in: .rect(topLeadingRadius: ClassCard.radius, topTrailingRadius: ClassCard.radius))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: ClassCard.radius, topTrailingRadius: ClassCard.radius)
                .strokeBorder(Theme.Palette.danger.opacity(Theme.Opacity.toneEdge), lineWidth: 1)
        }
        .padding(.horizontal, Theme.Space.m)
    }
}
