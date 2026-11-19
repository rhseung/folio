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
                Stat(String(localized: .courseGradesSecured), result.secured.oneDecimal)
                Stat(String(localized: .courseGradesProjected), result.projected.map(\.oneDecimal) ?? "-", tint: accent.ink)
                Stat(String(localized: .courseGradesRemainingWeight), "\(result.remainingPercent)%")
                Spacer()
                if relative == nil {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Caption(String(localized: .courseGradesTargetScore))
                        TextField(String(localized: .courseGradesTarget), value: $target, format: .number).pill(
                            width: Theme.Size.numberField)
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
                StandingCurve(
                    z: result.z, estimated: result.zEstimated, curve: result.curve, gap: result.gap, gapFromMedian: result.gapFromMedian,
                    share: relative)
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
                    Theme.Palette.text.frame(width: Theme.Size.line, height: Theme.Size.scoreTarget).offset(
                        x: w * min(target, 100) / 100 - 1)
                }
            }
            .frame(height: Theme.Size.scoreBar)
            HStack(spacing: Theme.Space.l) {
                Text("0").foregroundStyle(Theme.Palette.textTertiary)
                HStack(spacing: Theme.Space.tight) {
                    Capsule().fill(accent.color).frame(Theme.Size.legendBar); Text(.courseGradesLegendSecured(result.secured.oneDecimal))
                }
                if let p = result.projected {
                    HStack(spacing: Theme.Space.tight) {
                        Capsule().fill(accent.color.opacity(Theme.Opacity.projected)).frame(Theme.Size.legendBar)
                        Text(.courseGradesLegendProjected(p.oneDecimal))
                    }
                }
                HStack(spacing: Theme.Space.tight) {
                    Theme.Palette.text.frame(width: Theme.Size.line, height: Theme.Size.scoreBar)
                    Text(.courseGradesLegendTarget(target.formatted()))
                }
                Spacer()
                Text("100").foregroundStyle(Theme.Palette.textTertiary)
            }
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Palette.textSecondary)
        }
    }
}
