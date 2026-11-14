import FolioDomain
import SwiftUI

struct StandingCurve: View {
    @Environment(\.accent) private var accent
    let z: Double?
    var estimated = false
    var gap: Double?
    let share: Double

    // z는 -3부터 3까지 그린다. 그 밖에서는 곡선이 평평하고, 넘는 표시는 가장자리에 그린다.
    static let span = 3.0

    var body: some View {
        let cut = GradeCalculator.standing(z: 0, topGradeRatio: share).cutZ
        let s = z.map { GradeCalculator.standing(z: $0, topGradeRatio: share) }
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                let x = { (t: Double) in w * (min(max(t, -Self.span), Self.span) + Self.span) / (2 * Self.span) }
                let y = { (t: Double) in h - (h - 26) * exp(-t * t / 2) }
                let top = Path { p in
                    for i in 0...120 {
                        let t = -Self.span + 2 * Self.span * Double(i) / 120
                        let point = CGPoint(x: x(t), y: y(t))
                        if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                    }
                }
                let area = Path { p in
                    p.addPath(top)
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                    p.closeSubpath()
                }
                let split = x(cut)
                ZStack(alignment: .topLeading) {
                    area.fill(
                        LinearGradient(colors: [accent.color.opacity(0.22), accent.color.opacity(0)], startPoint: .top, endPoint: .bottom)
                    )
                    .mask(alignment: .leading) { Rectangle().frame(width: split) }
                    area.fill(
                        LinearGradient(
                            colors: [accent.color.opacity(0.6), accent.color.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                    )
                    .mask(alignment: .trailing) { Rectangle().frame(width: max(w - split, 0)) }
                    top.stroke(accent.color.opacity(0.45), lineWidth: 1.5)
                        .mask(alignment: .leading) { Rectangle().frame(width: split) }
                    top.stroke(accent.color, lineWidth: 1.5)
                        .mask(alignment: .trailing) { Rectangle().frame(width: max(w - split, 0)) }
                    Path { p in
                        p.move(to: CGPoint(x: x(cut), y: y(cut))); p.addLine(to: CGPoint(x: x(cut), y: h))
                    }
                    .stroke(Theme.Palette.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    Rectangle().fill(Theme.Palette.line).frame(width: w, height: 1).offset(y: h - 1)
                    if let s {
                        let mx = x(s.z), my = y(s.z)
                        Path { p in
                            p.move(to: CGPoint(x: mx, y: 18)); p.addLine(to: CGPoint(x: mx, y: h))
                        }
                        .stroke(Theme.Palette.text.opacity(0.7), lineWidth: 1.5)
                        Circle().fill(Theme.Palette.text).frame(width: 10, height: 10)
                            .overlay(Circle().strokeBorder(Theme.Palette.card, lineWidth: 2))
                            .offset(x: mx - 5, y: my - 5)
                        HStack(spacing: 0) {
                            if mx > w * 0.7 { Spacer(minLength: 0) } else { Color.clear.frame(width: max(mx - 8, 0), height: 0) }
                            Text(
                                String(localized: .courseGradesStandingMe(Int((s.above * 100).rounded())))
                                    + (estimated ? String(localized: .courseGradesStandingEstimated) : "")
                            )
                            .font(Theme.Typeface.label).foregroundStyle(Theme.Palette.text).fixedSize()
                            if mx > w * 0.7 { Color.clear.frame(width: max(w - mx - 8, 0), height: 0) } else { Spacer(minLength: 0) }
                        }
                        .frame(width: w)
                    }
                }
            }
            .frame(height: 104)
            GeometryReader { proxy in
                let w = proxy.size.width
                Text(.courseGradesStandingCut).fixedSize()
                    .position(x: min(max(w * (min(max(cut, -Self.span), Self.span) + Self.span) / (2 * Self.span), 24), w - 24), y: 7)
            }
            .frame(height: 14)
            .font(Theme.Typeface.caption)
            .foregroundStyle(Theme.Palette.textTertiary)
            HStack(spacing: Theme.Space.l) {
                Text(.courseGradesStandingShares(Int((share * 100).rounded()), Int(((1 - share) * 100).rounded())))
                    .foregroundStyle(Theme.Palette.textSecondary)
                Spacer()
                if let s {
                    Text(s.inTopGrade ? .courseGradesStandingInA : .courseGradesStandingOutA).fontWeight(.semibold)
                        .foregroundStyle(s.inTopGrade ? accent.ink : Theme.Palette.warning)
                } else if let gap {
                    let inA = GradeCalculator.inTopGrade(meanGap: gap, topGradeRatio: share)
                    Text(gap >= 0 ? .courseGradesStandingAboveMean : .courseGradesStandingBelowMean).foregroundStyle(
                        Theme.Palette.textSecondary)
                    Text(inA.map { $0 ? .courseGradesStandingInA : .courseGradesStandingOutA } ?? .courseGradesStandingUnknown).fontWeight(
                        inA == nil ? .regular : .semibold
                    )
                    .foregroundStyle(inA == true ? accent.ink : inA == false ? Theme.Palette.warning : Theme.Palette.textTertiary)
                } else {
                    Text(.courseGradesStandingNoMean).foregroundStyle(Theme.Palette.textTertiary)
                }
            }
            .font(Theme.Typeface.caption)
        }
        .help(Text(estimated ? .courseGradesStandingHelpEstimated : .courseGradesStandingHelp))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            s.map {
                String(
                    localized: .courseGradesStandingAccessibility(
                        Int(($0.above * 100).rounded()),
                        String(localized: $0.inTopGrade ? .courseGradesStandingInA : .courseGradesStandingOutA)))
            }
                ?? gap.map { String(localized: $0 >= 0 ? .courseGradesStandingAboveMean : .courseGradesStandingBelowMean) }
                ?? String(localized: .courseGradesStandingUnknownPlace))
    }
}
