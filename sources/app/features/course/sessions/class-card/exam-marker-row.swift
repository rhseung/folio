import FolioActions
import FolioDomain
import SwiftUI

struct ExamMarkerRow: View {
    let model: SessionsModel
    let exam: Exam
    let date: Date

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            ClassCard.Tile(
                month: model.month(date), day: model.day(date), ink: Theme.Palette.danger, monthInk: Theme.Palette.danger,
                fill: Theme.Palette.danger.opacity(Theme.Opacity.tint))
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "flag").font(Theme.Typeface.caption.weight(.semibold))
                Text(exam.title).font(Theme.Typeface.bodyLarge.weight(.bold)).lineLimit(1).fixedSize()
                Text(model.examLine(exam, date)).font(Theme.Typeface.caption).monospacedDigit().lineLimit(1)
                Capsule().fill(Theme.Palette.danger.opacity(Theme.Opacity.toneEdge)).frame(minWidth: Theme.Space.xl, maxWidth: .infinity)
                    .frame(height: 2)
                if let days = model.examDays(exam, now: model.workspace.now) {
                    Chip(days == 0 ? "D-day" : "D-\(days)", tone: .danger, solid: true)
                }
            }
            .foregroundStyle(Theme.Palette.danger)
        }
        .padding(.vertical, Theme.Space.xs)
        .padding(.leading, Theme.Space.l)
        .padding(.trailing, Theme.Space.m)
        .frame(minHeight: 52)
    }
}
