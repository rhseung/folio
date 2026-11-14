import FolioDomain
import SwiftUI

struct ScorePanel: View {
    @Environment(\.accent) private var accent
    let result: GradeCalculator.CourseScore
    @Binding var target: Double
    var relative: Double?

    var body: some View {
        let need = GradeCalculator.requiredAverage(for: target, given: result)
        VStack(alignment: .leading, spacing: Theme.Space.l + 2) {
            HStack(alignment: .bottom, spacing: Theme.Space.section) {
                Figure(String(localized: .courseGradesSecured), result.secured.oneDecimal)
                Figure(String(localized: .courseGradesProjected), result.projected.map(\.oneDecimal) ?? "-", tint: accent.ink)
                Figure(String(localized: .courseGradesRemainingWeight), "\(Int(result.remainingWeight.rounded()))%")
                Spacer()
                if relative == nil {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Caption(String(localized: .courseGradesTargetScore))
                        TextField(String(localized: .courseGradesTarget), value: $target, format: .number).pill(width: 72)
                    }
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(.courseGradesNeedTitle).font(Theme.Typeface.label).foregroundStyle(accent.ink)
                        Text(CourseGradesModel.needText(need))
                            .font(Theme.Typeface.figureMedium).foregroundStyle(accent.ink)
                    }
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                    .background(accent.tint, in: .rect(cornerRadius: Theme.Space.s))
                }
            }
            if let relative {
                StandingCurve(z: result.z, estimated: result.zEstimated, gap: result.meanGap, share: relative)
            } else {
                scoreBar
            }
        }
        .padding(.horizontal, Theme.Space.l + 4)
        .padding(.vertical, Theme.Space.l + 2)
        .background(Theme.Palette.card, in: .rect(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.Palette.lineSoft))
    }

    var scoreBar: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l + 2) {
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.fill)
                    if let p = result.projected {
                        Capsule().fill(accent.color.opacity(Theme.Opacity.projected)).frame(width: w * min(p, 100) / 100)
                    }
                    Capsule().fill(accent.color).frame(width: w * min(result.secured, 100) / 100)
                    Theme.Palette.text.frame(width: 2, height: 20).offset(x: w * min(target, 100) / 100 - 1)
                }
            }
            .frame(height: 12)
            HStack(spacing: Theme.Space.l) {
                Text("0").foregroundStyle(Theme.Palette.textTertiary)
                HStack(spacing: Theme.Space.tight) {
                    Capsule().fill(accent.color).frame(width: 14, height: 6); Text(.courseGradesLegendSecured(result.secured.oneDecimal))
                }
                if let p = result.projected {
                    HStack(spacing: Theme.Space.tight) {
                        Capsule().fill(accent.color.opacity(Theme.Opacity.projected)).frame(width: 14, height: 6)
                        Text(.courseGradesLegendProjected(p.oneDecimal))
                    }
                }
                HStack(spacing: Theme.Space.tight) {
                    Theme.Palette.text.frame(width: 2, height: 12); Text(.courseGradesLegendTarget(target.formatted()))
                }
                Spacer()
                Text("100").foregroundStyle(Theme.Palette.textTertiary)
            }
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
